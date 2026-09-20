import 'package:flutter/services.dart';

abstract interface class AudioBridge {
  Stream<Uint8List> get microphoneFrames;
  Stream<Map<String, dynamic>> get playbackEvents;

  Future<bool> requestMicrophonePermission();
  Future<void> start();
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
  Future<void> start() => _methods.invokeMethod<void>('start');

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
