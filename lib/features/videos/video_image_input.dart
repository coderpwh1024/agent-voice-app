import 'package:flutter/material.dart';

import '../../core/api/file_api.dart';
import 'data/video_image.dart';
import 'data/video_models.dart';
import 'video_widgets.dart';

class VideoImageInput extends StatelessWidget {
  const VideoImageInput({
    super.key,
    required this.label,
    required this.fieldKey,
    required this.attachment,
    required this.api,
    required this.picker,
    this.enabled = true,
    this.helper,
    this.previewLabel,
    this.preferUploadedPreview = false,
    this.expandAddressInitially,
    this.allowRemove = true,
  });
  final String label, fieldKey;
  final String? helper, previewLabel;
  final VideoImageAttachment attachment;
  final FileApi api;
  final VideoImagePicker picker;
  final bool enabled;
  final bool preferUploadedPreview;
  final bool? expandAddressInitially;
  final bool allowRemove;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: attachment,
    builder: (context, _) {
      final p = VideoPalette(context);
      final a = attachment;
      final canEdit = enabled && !a.busy;
      final hasImage = a.file != null || a.url.text.trim().isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              color: p.ink,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 6),
            Text(
              helper!,
              style: TextStyle(color: p.muted, fontSize: 12, height: 1.7),
            ),
          ],
          const SizedBox(height: 12),
          if (a.file != null || a.previewUri != null) ...[
            Semantics(
              label: '$label预览',
              image: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child:
                    a.file != null &&
                        !(preferUploadedPreview && a.uploaded != null)
                    ? Container(
                        color: p.blush,
                        height: 176,
                        child: Image.memory(
                          a.file!.bytes,
                          fit: BoxFit.contain,
                          cacheWidth: 640,
                          errorBuilder: (_, _, _) =>
                              const Center(child: Text('图片预览暂不可用')),
                        ),
                      )
                    : VideoCover(uri: a.previewUri),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (a.file != null)
            Text(
              a.file!.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 12, height: 1.6),
            ),
          if (a.uploaded != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: p.accentInk,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '图片已上传',
                      style: TextStyle(color: p.accentInk, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (a.busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      a.file == null ? '正在准备图片…' : '正在上传图片…',
                      style: TextStyle(color: p.muted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: Key('$fieldKey-pick'),
                onPressed: canEdit ? () => a.pick(picker, api) : null,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                label: Text(hasImage ? '更换$label' : '选择$label'),
              ),
              if (a.needsUpload && !a.busy)
                TextButton.icon(
                  key: Key('$fieldKey-retry'),
                  onPressed: canEdit ? () => a.retry(api) : null,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重新上传'),
                ),
              if (hasImage && allowRemove)
                TextButton(
                  key: Key('$fieldKey-remove'),
                  onPressed: canEdit ? a.clear : null,
                  child: const Text('移除'),
                ),
            ],
          ),
          if (a.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: VideoNotice(a.error!, error: true),
            ),
          ExpansionTile(
            key: Key('$fieldKey-address'),
            tilePadding: EdgeInsets.zero,
            maintainState: true,
            initiallyExpanded:
                expandAddressInitially ??
                (a.file == null && a.url.text.trim().isNotEmpty),
            title: Text(
              '使用图片地址',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextFormField(
                  key: Key(fieldKey),
                  controller: a.url,
                  enabled: canEdit,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '$label地址（可选）',
                    hintText: 'https://…/image.jpg',
                  ),
                  validator: (v) => label == '暂存封面'
                      ? VideoDraft.coverError(v)
                      : VideoDraft.frameError(v, label),
                  onChanged: (_) => a.addressChanged(),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: canEdit
                      ? () => a.previewAddress(
                          label: label,
                          cover: label == '暂存封面',
                        )
                      : null,
                  icon: const Icon(Icons.image_outlined, size: 17),
                  label: Text(previewLabel ?? '预览图片'),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
