import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/video_reference.dart';
import '../../core/config/app_config.dart';
import 'video_detail_page.dart';
import 'video_playback.dart';
import 'video_widgets.dart';

Future<void> openConversationVideo(
  BuildContext context,
  AppConfig config,
  VideoReference video, {
  required bool play,
}) async {
  final releases = <Future<void>>[];
  final route = MaterialPageRoute<void>(
    builder: (_) => play && video.playableUri != null
        ? _ConversationVideoPage(video: video, onPlayerDisposed: releases.add)
        : VideoDetailPage(
            config: config,
            recordId: video.recordId,
            onPlayerDisposed: releases.add,
          ),
  );
  await Navigator.of(context).push<void>(route);
  await route.completed;
  await Future.wait(releases);
}

class VideoMessageCard extends StatelessWidget {
  const VideoMessageCard({
    super.key,
    required this.video,
    required this.config,
    this.onOpen,
  });

  final VideoReference video;
  final AppConfig config;
  final Future<void> Function(bool play)? onOpen;

  Future<void> _open(BuildContext context, bool play) async {
    if (onOpen != null) {
      await onOpen!(play);
    } else {
      await openConversationVideo(context, config, video, play: play);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    final ready = video.playableUri != null;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: p.background,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: p.blush,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      ready
                          ? Icons.play_circle_outline_rounded
                          : Icons.movie_outlined,
                      color: VideoPalette.accent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '对话中的影片',
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '视频 #${video.recordId.toString().padLeft(4, '0')}',
                          style: TextStyle(
                            color: p.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              VideoStatusBadge(video),
              const SizedBox(height: 10),
              Text(
                video.description,
                style: TextStyle(color: p.muted, fontSize: 12, height: 1.7),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (ready)
                    FilledButton.icon(
                      onPressed: () => _open(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: VideoPalette.accent,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 19),
                      label: const Text('播放视频'),
                    ),
                  TextButton.icon(
                    onPressed: () => _open(context, false),
                    icon: Icon(
                      ready ? Icons.open_in_new_rounded : Icons.refresh_rounded,
                      size: 17,
                    ),
                    label: Text(ready ? '查看详情' : '查看进度'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationVideoPage extends StatelessWidget {
  const _ConversationVideoPage({
    required this.video,
    required this.onPlayerDisposed,
  });
  final VideoReference video;
  final ValueChanged<Future<void>> onPlayerDisposed;

  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text('对话中的影片'),
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: '返回对话',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        top: false,
        child: VideoLayout(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 32),
            children: [
              const VideoEyebrow('A MOMENT FROM OUR CONVERSATION'),
              const SizedBox(height: 12),
              Text(
                '把这一刻，留给自己。',
                style: TextStyle(
                  color: p.ink,
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 24),
              VideoPlayback(
                uri: video.playableUri!,
                autoPlay: true,
                onDisposed: onPlayerDisposed,
              ),
              const SizedBox(height: 20),
              VideoPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '视频 #${video.recordId.toString().padLeft(4, '0')}',
                      style: TextStyle(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    VideoStatusBadge(video),
                    const SizedBox(height: 14),
                    Text(
                      '这段画面，来自刚才的灵感。看完以后，我们接着聊。',
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 13,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: video.playableUri.toString()),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('影片链接已复制')),
                          );
                        }
                      },
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('复制视频链接'),
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        '完整视频地址',
                        style: TextStyle(fontSize: 13),
                      ),
                      children: [
                        SelectableText(
                          video.playableUri.toString(),
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 12,
                            height: 1.7,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: VideoPalette.accent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text('返回对话'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
