import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeVideoPlatform extends VideoPlayerPlatform {
  FakeVideoPlatform(this.operations);
  final List<String> operations;
  final players = <int, StreamController<VideoEvent>>{};
  final sources = <String?>[];
  Completer<void>? disposeGate;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = players.length + 1;
    sources.add(options.dataSource.uri);
    final stream = StreamController<VideoEvent>();
    stream.onListen = () => stream.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 3),
        size: const Size(1280, 720),
      ),
    );
    players[id] = stream;
    operations.add('video-created');
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => players[playerId]!.stream;
  @override
  Future<void> play(int playerId) async {
    operations.add('video-play');
    players[playerId]!.add(VideoEvent(eventType: VideoEventType.completed));
  }

  @override
  Future<void> pause(int playerId) async {
    operations.add('video-pause');
  }

  @override
  Future<void> dispose(int playerId) async {
    operations.add('video-dispose-start');
    await disposeGate?.future;
    await players[playerId]!.close();
    operations.add('video-disposed');
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Color(0xff222222));
}
