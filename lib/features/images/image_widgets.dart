import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/content/message_image_loader.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editorial_widgets.dart';
import 'data/image_models.dart';

String imageStudioDate(DateTime value) {
  final date = value.toLocal();
  return '${date.year}年${date.month}月${date.day}日';
}

Future<void> openImageOriginal(
  BuildContext context,
  ImageTask image, {
  Uri? previewUri,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (context) => Scaffold(
      appBar: AppBar(title: const Text('查看原图')),
      body: SafeArea(
        top: false,
        child: InteractiveViewer(
          maxScale: 4,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: EditorialLayout(
                child: ImagePreview(
                  uri: previewUri ?? image.resultUri,
                  label: image.displayTitle,
                  fit: BoxFit.contain,
                  showFeedback: true,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

class ImageArtwork extends StatelessWidget {
  const ImageArtwork({super.key, required this.image, this.previewUri});

  final ImageTask image;
  final Uri? previewUri;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.min(520, MediaQuery.sizeOf(context).height * .60),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ImagePreview(
          uri: previewUri ?? image.resultUri,
          label: image.displayTitle,
          fit: BoxFit.contain,
          showFeedback: true,
          onOpen: () =>
              openImageOriginal(context, image, previewUri: previewUri),
        ),
      ),
    ),
  );
}

class ImageGalleryTile extends StatelessWidget {
  const ImageGalleryTile({
    super.key,
    required this.title,
    required this.uri,
    required this.metadata,
    required this.onTap,
  });

  final String title;
  final Uri? uri;
  final Widget metadata;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 1,
            child: ImagePreview(uri: uri, label: title),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: AppPalette(context).muted),
          child: metadata,
        ),
      ],
    ),
  );
}

class ImagePreview extends StatefulWidget {
  const ImagePreview({
    super.key,
    required this.uri,
    required this.label,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.showFeedback = false,
    this.onOpen,
  });

  final Uri? uri;
  final String label;
  final BoxFit fit;
  final int? cacheWidth;
  final bool showFeedback;
  final VoidCallback? onOpen;

  @override
  State<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<ImagePreview> {
  int _attempt = 0;

  Future<void> _retry(ImageProvider provider) async {
    final uri = widget.uri;
    await provider.evict();
    if (mounted && widget.uri == uri) setState(() => _attempt++);
  }

  @override
  Widget build(BuildContext context) {
    final uri = widget.uri;
    final palette = AppPalette(context);
    if (uri == null) {
      return ColoredBox(
        color: palette.blush,
        child: Center(
          child: Icon(Icons.image_outlined, size: 30, color: palette.muted),
        ),
      );
    }
    // Finished works use the same cache key from gallery through zoom. Uploads
    // use the platform decoder so reference formats such as TIFF still work.
    final width = widget.cacheWidth;
    final imageProvider = width != null
        ? ResizeImage(NetworkImage(uri.toString()), width: width)
        : ResizeImage(
            _StudioImage(uri),
            width: 1440,
            height: 1440,
            policy: ResizeImagePolicy.fit,
          );
    return Image(
      key: ValueKey((uri, _attempt)),
      image: imageProvider,
      fit: widget.fit,
      semanticLabel: widget.label,
      frameBuilder: (context, image, frame, synchronous) {
        if (!synchronous && frame == null) {
          return _feedback(context, '正在加载图片…');
        }
        final open = widget.onOpen;
        return open == null
            ? image
            : Tooltip(
                message: '放大图片',
                child: InkWell(onTap: open, child: image),
              );
      },
      errorBuilder: (context, error, _) => _feedback(
        context,
        error is TimeoutException ? '图片加载超时' : '图片暂时无法加载',
        onRetry: () => _retry(imageProvider),
      ),
    );
  }

  Widget _feedback(
    BuildContext context,
    String label, {
    VoidCallback? onRetry,
  }) {
    final palette = AppPalette(context);
    final icon = Icon(
      onRetry == null
          ? Icons.hourglass_top_rounded
          : Icons.broken_image_outlined,
      size: 24,
      color: palette.accentInk,
    );
    final detailed = widget.showFeedback;
    return ColoredBox(
      color: palette.blush,
      child: detailed
          ? SizedBox(
              width: double.infinity,
              height: 176,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onRetry != null ||
                          MediaQuery.disableAnimationsOf(context))
                        icon
                      else
                        const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(label, textAlign: TextAlign.center),
                      ),
                      if (onRetry != null)
                        TextButton(
                          onPressed: onRetry,
                          child: const Text('重新加载图片'),
                        ),
                    ],
                  ),
                ),
              ),
            )
          : Center(
              child: onRetry == null
                  ? Semantics(label: label, child: icon)
                  : IconButton(
                      tooltip: '$label，重新加载图片',
                      onPressed: onRetry,
                      icon: icon,
                    ),
            ),
    );
  }
}

class _StudioImage extends ImageProvider<Uri> {
  const _StudioImage(this.uri);

  final Uri uri;

  @override
  Future<Uri> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(uri);

  @override
  ImageStreamCompleter loadImage(Uri key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: 1);

  Future<ui.Codec> _load(Uri uri, ImageDecoderCallback decode) async {
    final bytes = await MessageImageLoader(byteLimit: 32 * 1024 * 1024)
        .load(uri);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }
}

class ImageStatusLine extends StatelessWidget {
  const ImageStatusLine({super.key, required this.status});

  final ImageTaskStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette(context);
    final color = status == ImageTaskStatus.failed
        ? Theme.of(context).colorScheme.error
        : palette.accentInk;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status.isActive) ...[
          SizedBox.square(
            dimension: 12,
            child: MediaQuery.disableAnimationsOf(context)
                ? Icon(Icons.timelapse, size: 12, color: color)
                : CircularProgressIndicator(strokeWidth: 1.5, color: color),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            status.label,
            style: TextStyle(color: color, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class ImageNotice extends StatelessWidget {
  const ImageNotice({super.key, required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          height: 1.6,
        ),
      ),
      if (onRetry != null)
        TextButton(onPressed: onRetry, child: const Text('重试')),
    ],
  );
}
