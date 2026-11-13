import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/core/location/device_location.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'voice_session_controller_test.dart' show FakeAudioBridge, waitUntil;

class TrackingLocationProvider
    implements DeviceLocationProvider, DeviceLocationTracking {
  final updates = StreamController<DeviceLocationResult>.broadcast();
  DeviceLocationResult latest = const DeviceLocationResult(
    DeviceLocationStatus.unavailable,
  );

  void emit(DeviceLocationResult result) {
    latest = result;
    updates.add(result);
  }

  @override
  Future<DeviceLocationResult> currentLocation() async => latest;

  @override
  Stream<DeviceLocationResult> watch() => updates.stream;
}

void main() {
  for (final supportsUpdates in [true, false]) {
    test(
      'foreground location follows the negotiated socket: $supportsUpdates',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final received = <Map<String, dynamic>>[];
        WebSocket? socket;
        server.listen((request) async {
          if (WebSocketTransformer.isUpgradeRequest(request)) {
            socket = await WebSocketTransformer.upgrade(request);
            socket!.listen((message) {
              final event =
                  jsonDecode(message as String) as Map<String, dynamic>;
              received.add(event);
              if (event['type'] == 'session.configure') {
                socket!.add(
                  jsonEncode({
                    'type': 'session.ready',
                    'connection_id': '00112233-4455-6677-8899-aabbccddeeff',
                    if (supportsUpdates) 'location_updates': true,
                  }),
                );
              }
            });
            return;
          }
          final data = request.uri.path == '/voice/capabilities'
              ? {
                  'enabled': true,
                  'protocol_version': 1,
                  'voices': ['Cherry'],
                  'default_voice': 'Cherry',
                  'input_modes': ['conversation', 'text'],
                }
              : request.method == 'POST'
              ? {
                  'session_id': 'session-1',
                  'thread_id': 'thread-1',
                  'agent_id': 'mem0-chatbot',
                  'voice': 'Cherry',
                  'input_mode': 'text',
                  'expires_at': '2099-01-01T00:00:00Z',
                }
              : {'status': 'closing'};
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'code': 200, 'data': data}));
          await request.response.close();
        });
        final provider = TrackingLocationProvider();
        final audio = FakeAudioBridge();
        final controller = VoiceSessionController(
          config: AppConfig(
            baseUrl: 'http://127.0.0.1:${server.port}',
            accessToken: 'test-token',
            userId: '42',
          ),
          audio: audio,
          locationProvider: provider,
        );
        addTearDown(() async {
          controller.dispose();
          await provider.updates.close();
          await audio.close();
          await server.close(force: true);
        });
        controller.prepareDeviceLocation();
        final fix = DeviceLocationResult(
          DeviceLocationStatus.ok,
          DeviceLocation(
            latitude: 39.9,
            longitude: 116.4,
            accuracyMeters: 20,
            capturedAt: DateTime.now().toUtc(),
          ),
        );
        provider.emit(fix);
        await Future<void>.delayed(Duration.zero);
        await controller.connect(
          agentId: 'mem0-chatbot',
          voice: 'Cherry',
          inputMode: 'text',
        );
        if (supportsUpdates) {
          await waitUntil(
            () => received.any((e) => e['type'] == 'location.update'),
          );
          expect(received.last['device_location']['longitude'], 116.4);
        }
        expect(await controller.sendUserTextWithLocation('附近有哪些商场？'), isTrue);
        await waitUntil(() => received.any((e) => e['type'] == 'input.text'));
        expect(received.last['device_location']['latitude'], 39.9);
        socket!.add(
          jsonEncode({'type': 'location.request', 'request_id': 'lookup'}),
        );
        await waitUntil(
          () => received.any((e) => e['type'] == 'location.result'),
        );
        expect(received.last['status'], 'ok');
        expect(received.last['request_id'], 'lookup');
        if (supportsUpdates) {
          provider.emit(
            const DeviceLocationResult(DeviceLocationStatus.denied),
          );
          await waitUntil(() => received.last['status'] == 'denied');
        }
        controller.setBackgroundActive(false);
        await Future<void>.delayed(Duration.zero);
        expect(provider.updates.hasListener, isFalse);
        if (supportsUpdates) {
          await waitUntil(() => received.last['status'] == 'unavailable');
        } else {
          expect(
            received.where((e) => e['type'] == 'location.update'),
            isEmpty,
          );
        }
        await controller.disconnect();
        provider.emit(fix);
        await Future<void>.delayed(Duration.zero);
        expect(provider.updates.hasListener, isFalse);
      },
    );
  }
}
