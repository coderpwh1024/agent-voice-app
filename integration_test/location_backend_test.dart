import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/api/voice_protocol.dart';
import 'package:agent_voice_app/core/api/voice_socket.dart';
import 'package:agent_voice_app/core/location/device_location.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/backend_auth.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'foreground location reaches the USB backend before a map question',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final config = await backendTestConfig();
      expect(config.baseUrl, 'http://127.0.0.1:8000');
      final provider = GeolocatorDeviceLocationProvider();
      final warmup = Stopwatch()..start();
      final result = await provider.currentLocation();
      expect(
        result.status,
        DeviceLocationStatus.ok,
        reason: result.failure?.name,
      );
      final fix = result.location!;
      expect(fix.isFresh, isTrue);
      final firstFixMs = warmup.elapsedMilliseconds;
      final cached = Stopwatch()..start();
      expect(
        (await provider.currentLocation()).status,
        DeviceLocationStatus.ok,
      );
      final cachedFixMs = cached.elapsedMilliseconds;
      expect(cachedFixMs, lessThan(1000));
      final positionUpdates = <DeviceLocationResult>[];
      final tracking = provider.watch().listen(positionUpdates.add);
      addTearDown(tracking.cancel);
      final api = AgentApiClient(config);
      addTearDown(api.close);
      final capabilities = await api.capabilities();
      final session = await api.createVoiceSession(
        agentId: capabilities.defaultAgentId!,
        voice: capabilities.defaultVoice!,
        threadId: 'usb-location-${newEventId()}',
        inputMode: 'text',
      );
      addTearDown(() => api.closeVoiceSession(session.sessionId));
      final socket = await VoiceSocket.connect(
        api.websocketUri(session.sessionId),
        headers: api.websocketHeaders(),
      );
      addTearDown(socket.close);
      final events = <Map<String, dynamic>>[];
      final messages = socket.messages.listen((message) {
        if (message is VoiceSocketEventMessage) events.add(message.event);
      });
      addTearDown(messages.cancel);
      socket.sendJson(clientEvent('session.configure'));
      await _wait(
        () => events.any((event) => event['type'] == 'session.ready'),
      );
      expect(events.last['location_updates'], isTrue);
      socket.sendJson(
        clientEvent('location.update', {
          'status': 'ok',
          'device_location': fix.toJson(),
        }),
      );
      final timings = <String, int>{};
      final replies = <String, String>{};
      final lookups = <String, bool>{};
      for (final query in ['我现在在哪里？', '附近有哪些商场？']) {
        events.clear();
        final clock = Stopwatch()..start();
        socket.sendJson(clientEvent('input.text', {'text': query}));
        await _wait(
          () => events.any((event) => event['type'] == 'response.done'),
        );
        timings[query] = clock.elapsedMilliseconds;
        expect(
          events.where((event) => event['type'] == 'location.request'),
          isEmpty,
        );
        expect(events.where((event) => event['type'] == 'error'), isEmpty);
        final done = events.lastWhere(
          (event) => event['type'] == 'response.done',
        );
        expect(done['execution_status'], 'completed');
        final text = events
            .where((event) => event['type'] == 'text.delta')
            .map((event) => event['text'] as String)
            .join();
        expect(text, isNotEmpty);
        expect(text, isNot(contains('还没有收到有效的手机定位')));
        replies[query] = text;
        lookups[query] = events
            .where((event) => event['type'] == 'agent.custom')
            .map((event) => event['data'])
            .whereType<Map>()
            .expand(
              (data) =>
                  data['steps'] is List ? data['steps'] as List : const [],
            )
            .whereType<Map>()
            .any(
              (step) =>
                  step['stage'] == 'map.lookup' &&
                  step['status'] == 'succeeded',
            );
      }
      final nearby = replies['附近有哪些商场？']!;
      final nearbyStatus = lookups['附近有哪些商场？'] == true
          ? 'succeeded'
          : nearby.contains('配额')
          ? 'quota_exhausted'
          : 'unavailable';
      binding.reportData = {
        ...?binding.reportData,
        'backend': config.baseUrl,
        'native_first_fix_ms': firstFixMs,
        'native_cached_fix_ms': cachedFixMs,
        'native_foreground_updates': positionUpdates.length,
        'authenticated_proactive_location': true,
        'location_query_ms': timings['我现在在哪里？'],
        'nearby_query_ms': timings['附近有哪些商场？'],
        'position_lookup_succeeded': lookups['我现在在哪里？'],
        'nearby_status': nearbyStatus,
        'coordinates_logged': false,
      };
      debugPrint('LOCATION_CHECK ${binding.reportData}');
      socket.sendJson(clientEvent('session.close'));
      if (const bool.fromEnvironment('REQUIRE_MAP_SUCCESS')) {
        expect(nearbyStatus, 'succeeded', reason: '商业地图验收必须返回真实查询结果');
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _wait(bool Function() condition) async {
  final clock = Stopwatch()..start();
  while (!condition()) {
    if (clock.elapsed > const Duration(seconds: 45)) {
      fail('Local location integration exceeded its response deadline');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}
