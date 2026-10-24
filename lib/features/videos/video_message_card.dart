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

class VideoResultList extends StatelessWidget {
  const VideoResultList({
    super.key,
    required this.results,
    required this.config,
    this.onOpen,
  });

  final VideoResultPage results;
  final AppConfig config;
  final Future<void> Function(VideoReference video, bool play)? onOpen;

  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Text(
          '共找到 ${results.total} 个视频，本页 ${results.items.length} 个',
          style: TextStyle(color: p.muted, fontSize: 12, height: 1.7),
        ),
        for (final (index, video) in results.items.indexed) ...[
          const SizedBox(height: 12),
          Text(
            '第 ${index + 1} 个',
            style: TextStyle(
              color: p.accentInk,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          VideoMessageCard(
            video: video,
            config: config,
            onOpen: onOpen == null ? null : (play) => onOpen!(video, play),
          ),
        ],
        if (results.items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '没有找到这一页的视频，可以换个标题或内容关键词再说一次。',
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.7),
            ),
          ),
        if (results.page < results.totalPages)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '还有更多结果，可以说“下一页”；查看某条可以说“查询第二个”。',
              style: TextStyle(color: p.muted, fontSize: 12, height: 1.7),
            ),
          ),
      ],
    );
  }
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
    return VideoTheme(
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Material(
          color: p.background,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: p.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: VideoCover(uri: video.coverUri),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: p.blush,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        ready
                            ? Icons.play_circle_outline_rounded
                            : Icons.movie_outlined,
                        color: p.accentInk,
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
                            video.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (video.modelLabel != null) ...[
                  Text(
                    video.modelLabel!,
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.6),
                  ),
                  const SizedBox(height: 8),
                ],
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
                          backgroundColor: p.ink,
                          foregroundColor: p.background,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 19),
                        label: const Text('播放视频'),
                      ),
                    TextButton.icon(
                      onPressed: () => _open(context, false),
                      icon: Icon(
                        ready
                            ? Icons.open_in_new_rounded
                            : Icons.refresh_rounded,
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
    return VideoTheme(
      child: Scaffold(
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
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              children: [
                const VideoPageHeading(
                  eyebrow: 'FROM OUR CONVERSATION',
                  title: '故事，还在继续。',
                ),
                const SizedBox(height: 24),
                VideoPlayback(
                  uri: video.playableUri!,
                  coverUri: video.coverUri,
                  autoPlay: true,
                  onDisposed: onPlayerDisposed,
                ),
                const SizedBox(height: 20),
                VideoPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.displayTitle,
                        style: TextStyle(
                          color: p.ink,
                          fontWeight: FontWeight.w500,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (video.modelLabel != null) ...[
                        Text(
                          video.modelLabel!,
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
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
                    backgroundColor: p.ink,
                    foregroundColor: p.background,
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text('返回对话'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
