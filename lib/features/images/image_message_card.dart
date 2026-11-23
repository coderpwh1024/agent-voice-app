import 'package:flutter/material.dart';

import '../../core/api/image_task.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import 'image_detail_page.dart';
import 'image_widgets.dart';

class ImageMessageGallery extends StatelessWidget {
  const ImageMessageGallery({
    super.key,
    required this.images,
    required this.config,
    this.onOpen,
  });

  final List<ImageTask> images;
  final AppConfig config;
  final ValueChanged<ImageTask>? onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final twoColumns =
            images.length > 1 &&
            constraints.maxWidth >= 248 &&
            MediaQuery.textScalerOf(context).scale(14) < 20;
        final width = twoColumns
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final image in images)
              SizedBox(
                key: ValueKey(image.id),
                width: width,
                child: ImageMessageCard(
                  image: image,
                  config: config,
                  compact: twoColumns,
                  onOpen: onOpen == null ? null : () => onOpen!(image),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class ImageMessageCard extends StatelessWidget {
  const ImageMessageCard({
    super.key,
    required this.image,
    required this.config,
    this.compact = false,
    this.onOpen,
  });

  final ImageTask image;
  final AppConfig config;
  final bool compact;
  final VoidCallback? onOpen;

  double get _aspectRatio {
    final size = image.size?.split('*');
    if (compact || size == null || size.length != 2) return 1;
    final width = int.tryParse(size[0]);
    final height = int.tryParse(size[1]);
    if (width == null || width <= 0 || height == null || height <= 0) return 1;
    return (width / height).clamp(0.8, 1.78);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette(context);
    final theme = Theme.of(context);
    final uri = image.resultUri;
    return Material(
      color: palette.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap:
            onOpen ??
            () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ImageDetailPage(
                  config: config,
                  id: image.id,
                  initialTask: image,
                ),
              ),
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (uri != null)
              AspectRatio(
                aspectRatio: _aspectRatio,
                child: ColoredBox(
                  color: palette.blush,
                  child: ImagePreview(
                    uri: uri,
                    label: image.displayTitle,
                    fit: compact ? BoxFit.cover : BoxFit.contain,
                    showFeedback: !compact,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          image.displayTitle,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '#${image.id}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.muted,
                          ),
                        ),
                        if (uri == null) ...[
                          const SizedBox(height: 4),
                          ImageStatusLine(status: image.status),
                        ],
                      ],
                    ),
                  ),
                  if (!compact)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: palette.muted,
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
