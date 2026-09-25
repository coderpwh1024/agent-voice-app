import 'package:flutter/services.dart';

abstract interface class AudioBridge {
  Stream<Uint8List> get microphoneFrames;
  Stream<Map<String, dynamic>> get playbackEvents;

  Future<bool> requestMicrophonePermission();
  Future<AudioProcessingState> start(AudioCaptureMode mode);
  Future<void> enqueue(
    Uint8List pcm, {
    required String responseId,
    required int segmentIndex,
  });
  Future<void> completeSegment({
    required String responseId,
    required int segmentIndex,
    required int samples,
  });
  Future<void> completeResponse(String responseId);
  Future<void> cancel(String responseId);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
}

enum AudioCaptureMode { standby, conversation }

class AudioProcessingState {
  const AudioProcessingState({
    required this.mode,
    required this.aecAvailable,
    required this.aecEnabled,
    required this.noiseSuppressionAvailable,
    required this.noiseSuppressionEnabled,
  });

  factory AudioProcessingState.fromJson(Map<dynamic, dynamic>? json) {
    final value = json ?? const <Object?, Object?>{};
    return AudioProcessingState(
      mode: value['mode'] == 'standby'
          ? AudioCaptureMode.standby
          : AudioCaptureMode.conversation,
      aecAvailable: value['aecAvailable'] as bool? ?? false,
      aecEnabled: value['aecEnabled'] as bool? ?? false,
      noiseSuppressionAvailable:
          value['noiseSuppressionAvailable'] as bool? ?? false,
      noiseSuppressionEnabled:
          value['noiseSuppressionEnabled'] as bool? ?? false,
    );
  }

  final AudioCaptureMode mode;
  final bool aecAvailable;
  final bool aecEnabled;
  final bool noiseSuppressionAvailable;
  final bool noiseSuppressionEnabled;
}

class NativeAudioBridge implements AudioBridge {
  static const MethodChannel _methods = MethodChannel('agent_voice/audio');
  static const EventChannel _microphone = EventChannel(
    'agent_voice/microphone',
  );
  static const EventChannel _playback = EventChannel('agent_voice/playback');

  @override
  Stream<Uint8List> get microphoneFrames => _microphone
      .receiveBroadcastStream()
      .where((event) => event is Uint8List)
      .cast<Uint8List>();

  @override
  Stream<Map<String, dynamic>> get playbackEvents => _playback
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => Map<String, dynamic>.from(event as Map));

  @override
  Future<bool> requestMicrophonePermission() async {
    return await _methods.invokeMethod<bool>('requestMicrophonePermission') ??
        false;
  }

  @override
  Future<AudioProcessingState> start(AudioCaptureMode mode) async {
    final value = await _methods.invokeMethod<Map<dynamic, dynamic>>(
      'start',
      <String, Object>{'mode': mode.name},
    );
    return AudioProcessingState.fromJson(value);
  }

  @override
  Future<void> enqueue(
    Uint8List pcm, {
    required String responseId,
    required int segmentIndex,
  }) {
    return _methods.invokeMethod<void>('enqueuePlayback', <String, Object>{
      'pcm': pcm,
      'responseId': responseId,
      'segmentIndex': segmentIndex,
    });
  }

  @override
  Future<void> completeSegment({
    required String responseId,
    required int segmentIndex,
    required int samples,
  }) {
    return _methods.invokeMethod<void>('completeSegment', <String, Object>{
      'responseId': responseId,
      'segmentIndex': segmentIndex,
      'samples': samples,
    });
  }

  @override
  Future<void> completeResponse(String responseId) =>
      _methods.invokeMethod<void>('completeResponse', <String, Object>{
        'responseId': responseId,
      });

  @override
  Future<void> cancel(String responseId) => _methods.invokeMethod<void>(
    'cancelPlayback',
    <String, Object>{'responseId': responseId},
  );

  @override
  Future<void> pause() => _methods.invokeMethod<void>('pausePlayback');

  @override
  Future<void> resume() => _methods.invokeMethod<void>('resumePlayback');

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');
}
