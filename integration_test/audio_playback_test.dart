import 'dart:typed_data';

import 'package:agent_voice_app/core/audio/audio_bridge.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'paused PCM is retained and cancellation resets the playback clock',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final audio = NativeAudioBridge();
      final events = <Map<String, dynamic>>[];
      final subscription = audio.playbackEvents.listen(events.add);
      addTearDown(() async {
        await audio.stop();
        await subscription.cancel();
      });
      expect(await audio.requestMicrophonePermission(), isTrue);
      await audio.start(AudioCaptureMode.conversation);

      const pausedResponse = '11111111-2222-4333-8444-555555555555';
      await audio.pause();
      for (var index = 0; index < 12; index++) {
        await audio.enqueue(
          Uint8List(4000),
          responseId: pausedResponse,
          segmentIndex: 1,
        );
      }
      await audio.completeSegment(
        responseId: pausedResponse,
        segmentIndex: 1,
        samples: 24000,
      );
      await audio.completeResponse(pausedResponse);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(events, isEmpty);
      final resumed = Stopwatch()..start();
      await audio.resume();
      await _waitForResponse(events, pausedResponse);
      expect(
        resumed.elapsedMilliseconds,
        greaterThanOrEqualTo(850),
        reason: 'All one second of queued PCM must play after resume',
      );

      for (var cycle = 0; cycle < 3; cycle++) {
        final cancelled = 'cancelled-$cycle';
        await audio.enqueue(
          Uint8List(96000),
          responseId: cancelled,
          segmentIndex: 1,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await audio.pause();
        final cancellation = Stopwatch()..start();
        await audio.cancel(cancelled).timeout(const Duration(seconds: 1));
        expect(cancellation.elapsedMilliseconds, lessThan(250));
        final next = 'after-cancel-$cycle';
        final started = Stopwatch()..start();
        await audio.enqueue(
          Uint8List(48000),
          responseId: next,
          segmentIndex: 1,
        );
        await audio.completeSegment(
          responseId: next,
          segmentIndex: 1,
          samples: 24000,
        );
        await audio.completeResponse(next);
        await _waitForResponse(events, next);
        expect(
          started.elapsedMilliseconds,
          greaterThanOrEqualTo(850),
          reason:
              'Flushing must not report the next response as already played',
        );
        expect(
          events.where((event) => event['responseId'] == cancelled),
          isEmpty,
        );
      }
    },
  );
}

Future<void> _waitForResponse(
  List<Map<String, dynamic>> events,
  String responseId,
) async {
  final deadline = Stopwatch()..start();
  while (!events.any(
    (event) =>
        event['type'] == 'response.finished' &&
        event['responseId'] == responseId,
  )) {
    if (deadline.elapsed > const Duration(seconds: 8)) {
      fail('Native playback did not finish response $responseId');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
