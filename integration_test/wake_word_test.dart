import 'dart:io';
import 'dart:typed_data';

import 'package:agent_voice_app/core/audio/wake_word_detector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native wake detection survives tuning, pauses and quiet speech',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final detector = SherpaWakeWordDetector();
      final hits = <WakeDetection>[];
      final subscription = detector.detections.listen(hits.add);
      addTearDown(() async {
        await subscription.cancel();
        await detector.dispose();
      });

      final normal = await _fixture('normal');
      await detector.initialize(
        const WakeWordConfig(keyword: '小美小美', score: 0.1, threshold: 1),
      );
      await _feed(detector, normal);
      expect(hits, isEmpty);

      await detector.initialize(
        const WakeWordConfig(keyword: '小美小美', score: 1.5, threshold: 0.25),
      );
      for (final scenario in <(String, double, double, bool)>[
        ('normal', 0, 1, true),
        ('alternate_voice', 1.35, 1, true),
        ('paused', 1.35, .15, true),
        ('with_command', 2.9, .15, true),
        ('single_call', 1.35, 1, false),
        ('similar_words', 1.35, 1, false),
        ('unrelated', 1.35, 1, false),
      ]) {
        detector.reset();
        hits.clear();
        final samples = await _fixture(scenario.$1);
        await _feed(
          detector,
          samples,
          leadSeconds: scenario.$2,
          gain: scenario.$3,
        );
        expect(hits.length, scenario.$4 ? 1 : 0, reason: scenario.$1);
        if (scenario.$4) expect(hits.single.keyword, '小美小美');
        debugPrint('Native wake fixture passed: ${scenario.$1}');
      }
    },
  );
}

Future<Int16List> _fixture(String name) async {
  const root = String.fromEnvironment(
    'WAKE_CORPUS_URL',
    defaultValue: 'http://127.0.0.1:8766',
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  late Uint8List wav;
  try {
    final response = await (await client.getUrl(Uri.parse('$root/$name.wav')))
        .close();
    expect(response.statusCode, 200);
    final bytes = BytesBuilder();
    await response.forEach(bytes.add);
    wav = bytes.takeBytes();
  } finally {
    client.close(force: true);
  }
  final data = ByteData.sublistView(wav);
  var offset = 12;
  while (offset + 8 <= wav.length) {
    final size = data.getUint32(offset + 4, Endian.little);
    if (String.fromCharCodes(wav.sublist(offset, offset + 4)) == 'data') {
      final values = Int16List(size ~/ 2);
      for (var i = 0; i < values.length; i++) {
        values[i] = data.getInt16(offset + 8 + i * 2, Endian.little);
      }
      final first = values.indexWhere((value) => value.abs() > 98);
      final last = values.lastIndexWhere((value) => value.abs() > 98);
      return Int16List.sublistView(
        values,
        (first - 1600).clamp(0, values.length),
        (last + 1600).clamp(0, values.length),
      );
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw StateError('No PCM data in synthetic fixture $name');
}

Future<void> _feed(
  SherpaWakeWordDetector detector,
  Int16List audio, {
  double leadSeconds = 0,
  double gain = 1,
}) async {
  final leadSamples = (leadSeconds * 16000).round();
  final samples = leadSamples + audio.length + 16000;
  final processing = Stopwatch()..start();
  for (var offset = 0; offset < samples; offset += 640) {
    final pcm = ByteData(1280);
    for (var i = 0; i < 640; i++) {
      final index = offset + i - leadSamples;
      if (index >= 0 && index < audio.length) {
        pcm.setInt16(i * 2, (audio[index] * gain).round(), Endian.little);
      }
    }
    detector.addPcm(pcm.buffer.asUint8List());
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  await detector.flushPendingAudio();
  expect(
    processing.elapsedMilliseconds,
    lessThan(samples / 16),
    reason: 'The native decoder must keep up with realtime capture',
  );
  await Future<void>.delayed(const Duration(milliseconds: 50));
}
