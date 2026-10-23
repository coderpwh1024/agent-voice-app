import 'package:flutter/material.dart';

import '../../core/api/video_reference.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editorial_widgets.dart';

class VideoPalette extends AppPalette {
  VideoPalette(super.context);
  static const accent = AppPalette.baseAccent;
}

class VideoTheme extends AppThemeScope {
  const VideoTheme({super.key, required super.child});
}

class VideoWordmark extends StatelessWidget {
  const VideoWordmark({super.key});
  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    return Semantics(
      label: '映像 · 视频工作室',
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 190 ||
              MediaQuery.textScalerOf(context).scale(12) > 18) {
            return Text(
              '映像',
              style: TextStyle(
                fontFamily: 'StudioSerif',
                fontSize: 24,
                color: p.ink,
                letterSpacing: 2,
              ),
            );
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '映像',
                style: TextStyle(
                  fontFamily: 'StudioSerif',
                  fontSize: 26,
                  color: p.ink,
                  letterSpacing: 3,
                  height: 1.2,
                ),
              ),
              Container(
                height: 23,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: p.border,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'STUDIO',
                    style: TextStyle(
                      color: p.ink,
                      fontSize: 9,
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '视频工作室',
                    style: TextStyle(
                      color: p.muted,
                      fontSize: 9,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class VideoPageHeading extends EditorialHeading {
  const VideoPageHeading({
    super.key,
    required super.eyebrow,
    required super.title,
    super.subtitle,
  });
}

class VideoLayout extends StatelessWidget {
  const VideoLayout({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: child,
    ),
  );
}

class VideoEyebrow extends EditorialEyebrow {
  const VideoEyebrow(super.text, {super.key, super.color});
}

class VideoPanel extends EditorialPanel {
  const VideoPanel({super.key, required super.child, super.padding});
}

class VideoStatusBadge extends StatelessWidget {
  const VideoStatusBadge(this.task, {super.key});
  final VideoReference task;
  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    final color = task.playableUri != null
        ? (p.dark ? const Color(0xffa6c6af) : const Color(0xff477c67))
        : p.accentInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            task.playableUri != null
                ? Icons.check_circle_rounded
                : task.shouldPoll
                ? Icons.timelapse_rounded
                : Icons.info_outline_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            task.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class VideoNotice extends StatelessWidget {
  const VideoNotice(
    this.message, {
    super.key,
    this.onRetry,
    this.retryLabel = '重试',
  });
  final String message, retryLabel;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.blush,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 19,
                color: VideoPalette.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: p.ink, height: 1.6, fontSize: 13),
                ),
              ),
            ],
          ),
          if (onRetry != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onRetry, child: Text(retryLabel)),
            ),
        ],
      ),
    );
  }
}

class VideoCover extends StatelessWidget {
  const VideoCover({
    super.key,
    this.uri,
    this.child,
    this.aspectRatio = 16 / 9,
  });
  final Uri? uri;
  final Widget? child;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    Widget placeholder(String label, IconData icon) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p.dark
              ? [const Color(0xff30372c), const Color(0xff232820)]
              : [const Color(0xffefeee6), const Color(0xffdbded2)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: p.ink.withValues(alpha: .5)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: p.ink.withValues(alpha: .65),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      label: '视频封面',
      image: true,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (uri == null)
              placeholder('暂无封面', Icons.movie_outlined)
            else
              Image.network(
                uri.toString(),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                frameBuilder: (_, image, frame, synchronous) =>
                    frame != null || synchronous
                    ? image
                    : placeholder('封面加载中', Icons.image_outlined),
                loadingBuilder: (_, image, progress) => progress == null
                    ? image
                    : placeholder('封面加载中', Icons.image_outlined),
                errorBuilder: (_, error, stack) =>
                    placeholder('封面暂不可用', Icons.broken_image_outlined),
              ),
            ?child,
          ],
        ),
      ),
    );
  }
}

String videoDate(DateTime date) {
  final local = date.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${local.year}.${pad(local.month)}.${pad(local.day)}  ${pad(local.hour)}:${pad(local.minute)}';
}
