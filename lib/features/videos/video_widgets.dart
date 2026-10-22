import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/video_reference.dart';

class VideoPalette {
  VideoPalette(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get background =>
      dark ? const Color(0xff151419) : const Color(0xfffaf8f5);
  Color get surface => dark ? const Color(0xff242129) : Colors.white;
  Color get ink => dark ? const Color(0xfff7f0ee) : const Color(0xff29232c);
  Color get muted => dark ? const Color(0xffbbb0bc) : const Color(0xff827782);
  Color get border => dark ? const Color(0xff3c3540) : const Color(0xffeae3e5);
  Color get blush => dark ? const Color(0xff3d2935) : const Color(0xfff7e8eb);
  static const accent = Color(0xffaa496b);
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

class VideoEyebrow extends StatelessWidget {
  const VideoEyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: color ?? VideoPalette(context).muted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.3,
    ),
  );
}

class VideoPanel extends StatelessWidget {
  const VideoPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class VideoStatusBadge extends StatelessWidget {
  const VideoStatusBadge(this.task, {super.key});
  final VideoReference task;
  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    final color = task.playableUri != null
        ? const Color(0xff477c67)
        : VideoPalette.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(30),
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
        borderRadius: BorderRadius.circular(18),
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
              ? [const Color(0xff443548), const Color(0xff252839)]
              : [const Color(0xffe9dce1), const Color(0xffc3bdcf)],
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

class VideoLandscape extends StatelessWidget {
  const VideoLandscape({
    super.key,
    this.variant = 0,
    this.child,
    this.height = 230,
  });
  final int variant;
  final Widget? child;
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(26),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _LandscapePainter(variant)),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xb31e1928)],
                ),
              ),
            ),
          ),
          child ?? SizedBox(height: height, width: double.infinity),
        ],
      ),
    ),
  );
}

class _LandscapePainter extends CustomPainter {
  _LandscapePainter(this.variant);
  final int variant;
  @override
  void paint(Canvas canvas, Size size) {
    final alternate = variant.isOdd;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: alternate
              ? [
                  const Color(0xff353d5c),
                  const Color(0xffb191ac),
                  const Color(0xffe3bca4),
                ]
              : [
                  const Color(0xff706279),
                  const Color(0xffd6999c),
                  const Color(0xffffd4af),
                ],
        ).createShader(Offset.zero & size),
    );
    final sun = Offset(size.width * .73, size.height * .31);
    canvas.drawCircle(
      sun,
      size.height * .14,
      Paint()..color = const Color(0xffffd4b1),
    );
    canvas.drawCircle(
      sun,
      size.height * .19,
      Paint()..color = const Color(0x18ffe0c2),
    );
    for (var i = 0; i < 4; i++) {
      final path = Path()..moveTo(0, size.height * (.49 + i * .12));
      path.cubicTo(
        size.width * .24,
        size.height * (.12 + i * .16),
        size.width * .5,
        size.height * (.89 - i * .04),
        size.width,
        size.height * (.42 + i * .15),
      );
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = [
            const Color(0xffa77f91),
            const Color(0xff795d7c),
            const Color(0xff514762),
            const Color(0xff343247),
          ][i],
      );
    }
    final random = math.Random(8);
    final paint = Paint()..color = const Color(0x12ffffff);
    for (var i = 0; i < 1300; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        .6,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LandscapePainter oldDelegate) =>
      variant != oldDelegate.variant;
}

String videoDate(DateTime date) {
  final local = date.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${local.year}.${pad(local.month)}.${pad(local.day)}  ${pad(local.hour)}:${pad(local.minute)}';
}
