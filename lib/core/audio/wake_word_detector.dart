import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class WakeWordConfig {
  const WakeWordConfig({
    required this.keyword,
    required this.score,
    required this.threshold,
  });

  final String keyword;
  final double score;
  final double threshold;
}

class WakeDetection {
  const WakeDetection({required this.keyword});

  final String keyword;
}

abstract interface class WakeWordDetector {
  Stream<WakeDetection> get detections;

  Future<void> initialize(WakeWordConfig config);
  void addPcm(Uint8List pcm);
  void reset();
  Future<void> dispose();
}

class SherpaWakeWordDetector implements WakeWordDetector {
  static const _audioMethods = MethodChannel('agent_voice/audio');
  static const supportedKeyword = '小美';
  static const _assetRoot = 'assets/models/sherpa_kws';
  static const _modelVersion = 'wenetspeech-3.3m-int8-xiaomei-v3';
  static const _modelFiles = <String>[
    'encoder.int8.onnx',
    'decoder.int8.onnx',
    'joiner.int8.onnx',
    'tokens.txt',
    'keywords.txt',
  ];

  final StreamController<WakeDetection> _detections =
      StreamController<WakeDetection>.broadcast();
  ReceivePort? _results;
  ReceivePort? _errors;
  Isolate? _isolate;
  SendPort? _commands;

  @override
  Stream<WakeDetection> get detections => _detections.stream;

  @override
  Future<void> initialize(WakeWordConfig config) async {
    if (config.keyword != supportedKeyword) {
      throw UnsupportedError(
        '当前离线模型仅支持唤醒词“$supportedKeyword”，后端下发的是“${config.keyword}”',
      );
    }
    if (_commands != null) {
      return;
    }
    final paths = await _materializeModel();
    final ready = Completer<void>();
    final results = ReceivePort();
    final errors = ReceivePort();
    _results = results;
    _errors = errors;
    results.listen((dynamic message) {
      if (message is! Map) {
        return;
      }
      switch (message['type']) {
        case 'ready':
          _commands = message['port'] as SendPort;
          if (!ready.isCompleted) {
            ready.complete();
          }
        case 'detected':
          _detections.add(WakeDetection(keyword: message['keyword'] as String));
        case 'error':
          final error = StateError(message['message'] as String);
          if (!ready.isCompleted) {
            ready.completeError(error);
          } else {
            _detections.addError(error);
          }
      }
    });
    errors.listen((dynamic error) {
      final value = StateError('唤醒引擎异常：$error');
      if (!ready.isCompleted) {
        ready.completeError(value);
      } else {
        _detections.addError(value);
      }
    });
    _isolate = await Isolate.spawn<Map<String, Object>>(
      _wakeWordWorker,
      <String, Object>{
        'result_port': results.sendPort,
        'encoder': paths['encoder.int8.onnx']!,
        'decoder': paths['decoder.int8.onnx']!,
        'joiner': paths['joiner.int8.onnx']!,
        'tokens': paths['tokens.txt']!,
        'keywords': paths['keywords.txt']!,
        'score': config.score,
        'threshold': config.threshold,
      },
      onError: errors.sendPort,
      debugName: 'agent-voice-kws',
    );
    await ready.future.timeout(const Duration(seconds: 20));
  }

  Future<Map<String, String>> _materializeModel() async {
    final support = await _audioMethods.invokeMethod<String>(
      'applicationSupportDirectory',
    );
    if (support == null || support.isEmpty) {
      throw StateError('原生端没有返回应用支持目录');
    }
    final directory = Directory('$support/agent_voice_models/$_modelVersion');
    await directory.create(recursive: true);
    final paths = <String, String>{};
    for (final name in _modelFiles) {
      final file = File('${directory.path}/$name');
      if (!await file.exists() || await file.length() == 0) {
        final data = await rootBundle.load('$_assetRoot/$name');
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      paths[name] = file.path;
    }
    return paths;
  }

  @override
  void addPcm(Uint8List pcm) {
    if (_commands == null || pcm.isEmpty || pcm.length.isOdd) {
      return;
    }
    _commands!.send(<String, Object>{
      'type': 'audio',
      'data': TransferableTypedData.fromList(<Uint8List>[pcm]),
    });
  }

  @override
  void reset() {
    _commands?.send(<String, Object>{'type': 'reset'});
  }

  @override
  Future<void> dispose() async {
    _commands?.send(<String, Object>{'type': 'stop'});
    _commands = null;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _results?.close();
    _errors?.close();
    _results = null;
    _errors = null;
    await _detections.close();
  }
}

@pragma('vm:entry-point')
void _wakeWordWorker(Map<String, Object> arguments) {
  final resultPort = arguments['result_port']! as SendPort;
  final commands = ReceivePort();
  sherpa.KeywordSpotter? spotter;
  sherpa.OnlineStream? stream;
  try {
    sherpa.initBindings();
    spotter = sherpa.KeywordSpotter(
      sherpa.KeywordSpotterConfig(
        feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: arguments['encoder']! as String,
            decoder: arguments['decoder']! as String,
            joiner: arguments['joiner']! as String,
          ),
          tokens: arguments['tokens']! as String,
          numThreads: 1,
          debug: false,
        ),
        maxActivePaths: 4,
        numTrailingBlanks: 1,
        keywordsScore: arguments['score']! as double,
        keywordsThreshold: arguments['threshold']! as double,
        keywordsFile: arguments['keywords']! as String,
      ),
    );
    stream = spotter.createStream();
    resultPort.send(<String, Object>{
      'type': 'ready',
      'port': commands.sendPort,
    });
  } catch (error) {
    resultPort.send(<String, Object>{
      'type': 'error',
      'message': error.toString(),
    });
    commands.close();
    return;
  }
  final activeSpotter = spotter;
  final activeStream = stream;

  commands.listen((dynamic raw) {
    if (raw is! Map) {
      return;
    }
    try {
      switch (raw['type']) {
        case 'audio':
          final bytes = (raw['data'] as TransferableTypedData)
              .materialize()
              .asUint8List();
          final samples = Float32List(bytes.length ~/ 2);
          final pcm = ByteData.sublistView(bytes);
          for (var index = 0; index < samples.length; index++) {
            samples[index] = pcm.getInt16(index * 2, Endian.little) / 32768.0;
          }
          activeStream.acceptWaveform(samples: samples, sampleRate: 16000);
          while (activeSpotter.isReady(activeStream)) {
            activeSpotter.decode(activeStream);
            final result = activeSpotter.getResult(activeStream);
            if (result.keyword.isNotEmpty) {
              resultPort.send(<String, Object>{
                'type': 'detected',
                'keyword': result.keyword,
              });
              activeSpotter.reset(activeStream);
            }
          }
        case 'reset':
          activeSpotter.reset(activeStream);
        case 'stop':
          activeStream.free();
          activeSpotter.free();
          commands.close();
          Isolate.exit();
      }
    } catch (error) {
      resultPort.send(<String, Object>{
        'type': 'error',
        'message': error.toString(),
      });
    }
  });
}
