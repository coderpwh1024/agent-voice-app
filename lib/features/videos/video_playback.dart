import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'video_widgets.dart';

class VideoPlayback extends StatefulWidget {
  const VideoPlayback({
    super.key,
    required this.uri,
    this.autoPlay = false,
    this.coverUri,
    this.onDisposed,
  });
  final Uri uri;
  final Uri? coverUri;
  final bool autoPlay;
  final ValueChanged<Future<void>>? onDisposed;
  @override
  State<VideoPlayback> createState() => _VideoPlaybackState();
}

class _VideoPlaybackState extends State<VideoPlayback>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String? _error;
  bool _ready = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_controller?.pause());
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    final previous = _controller;
    _controller = null;
    if (previous != null) {
      previous.removeListener(_changed);
      await previous.dispose();
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _error = null;
      _ready = false;
    });
    final controller = VideoPlayerController.networkUrl(
      widget.uri,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 30));
      if (!mounted || generation != _generation) return;
      controller.addListener(_changed);
      setState(() => _ready = true);
      if (widget.autoPlay &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        await controller.play();
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '影片暂时无法加载，请重试');
      }
    }
  }

  void _changed() {
    if (mounted) {
      setState(() {
        if (_controller?.value.hasError == true) _error = '播放中断，请检查网络后重试';
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_changed);
    final release = _controller?.dispose() ?? Future<void>.value();
    widget.onDisposed?.call(release);
    unawaited(release);
    super.dispose();
  }

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null || !_ready) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        if (controller.value.position >= controller.value.duration) {
          await controller.seekTo(Duration.zero);
        }
        await controller.play();
      }
    } catch (_) {
      if (mounted) setState(() => _error = '播放中断，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) return VideoNotice(_error!, onRetry: _initialize);
    if (!_ready || controller == null) {
      return const SizedBox(
        height: 230,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: const Color(0xff191c17),
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 440),
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio > 0
                    ? controller.value.aspectRatio
                    : 16 / 9,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(controller),
                    if (!controller.value.isPlaying &&
                        controller.value.position == Duration.zero &&
                        widget.coverUri != null)
                      Positioned.fill(
                        child: VideoCover(
                          uri: widget.coverUri,
                          aspectRatio: controller.value.aspectRatio > 0
                              ? controller.value.aspectRatio
                              : 16 / 9,
                        ),
                      ),
                    if (!controller.value.isPlaying)
                      IconButton.filled(
                        tooltip: '播放影片',
                        onPressed: _toggle,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                        ),
                        iconSize: 40,
                        icon: const Icon(Icons.play_arrow_rounded),
                      ),
                    if (controller.value.isBuffering)
                      const CircularProgressIndicator(color: Colors.white),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: controller.value.isPlaying ? '暂停影片' : '播放影片',
                    onPressed: _toggle,
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xffd5dcc6),
                        bufferedColor: Colors.white30,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${controller.value.position.inSeconds} / ${controller.value.duration.inSeconds}s',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
