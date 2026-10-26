import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/api/file_api.dart';
import '../../core/config/app_config.dart';
import 'data/video_api.dart';
import 'data/video_image.dart';
import 'data/video_models.dart';
import 'video_image_input.dart';
import 'video_widgets.dart';

class VideoEditPage extends StatefulWidget {
  const VideoEditPage({
    super.key,
    required this.config,
    required this.task,
    this.api,
    this.fileApi,
    this.imagePicker,
  });

  final AppConfig config;
  final VideoTask task;
  final VideoApi? api;
  final FileApi? fileApi;
  final VideoImagePicker? imagePicker;

  @override
  State<VideoEditPage> createState() => _VideoEditPageState();
}

class _VideoEditPageState extends State<VideoEditPage> {
  late final VideoApi _api;
  late final FileApi _files;
  late final VideoImagePicker _picker;
  late final TextEditingController _title, _cover;
  late final VideoImageAttachment _image;
  bool _saving = false;
  String? _error;

  bool get _canEditCover =>
      widget.task.status == 'SUCCEEDED' &&
      widget.task.storageStatus == 'STORED';

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? VideoApi(widget.config);
    _files = widget.fileApi ?? FileApi(widget.config);
    _picker = widget.imagePicker ?? VideoImagePicker();
    _title = TextEditingController(text: widget.task.title ?? '')
      ..addListener(_changed);
    _cover = TextEditingController(text: widget.task.coverUrl ?? '');
    _image = VideoImageAttachment(_cover, forFrame: false)
      ..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() => _error = null);
  }

  @override
  void dispose() {
    _image.dispose();
    _title.dispose();
    _cover.dispose();
    if (widget.fileApi == null) _files.close();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _image.busy) return;
    final originalTitle = widget.task.title?.trim() ?? '';
    final originalCover = widget.task.coverUrl?.trim() ?? '';
    final currentTitle = _title.text.trim();
    final currentCover = _cover.text.trim();
    final titleChanged = currentTitle != originalTitle;
    final coverChanged = _canEditCover && currentCover != originalCover;
    if (_image.needsUpload) {
      setState(() => _error = '请先完成封面上传，或重新选择图片');
      return;
    }
    if (_canEditCover && _image.file != null && _image.uploaded == null) {
      setState(() => _error = '封面尚未上传成功，请重试上传');
      return;
    }
    final update = VideoMetadataUpdate(
      title: titleChanged ? currentTitle : null,
      coverUrl: coverChanged ? currentCover : null,
    );
    if (update.validationError case final error?) {
      setState(() => _error = error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final task = await _api.updateMetadata(widget.task.id, update);
      if (mounted) Navigator.of(context).pop(task);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ApiException && error.statusCode == 409
              ? '作品正在同步，或封面尚未完成保存。请稍后刷新详情再试。'
              : videoError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    final titleLength = _title.text.trim().runes.length;
    final titleChanged =
        _title.text.trim() != (widget.task.title?.trim() ?? '');
    final longOriginalTitle = !titleChanged && titleLength > 35;
    final titleError = titleChanged
        ? VideoMetadataUpdate.titleError(_title.text)
        : null;
    return VideoTheme(
      child: PopScope(
        canPop: !_saving,
        child: Scaffold(
          backgroundColor: p.background,
          appBar: AppBar(
            title: const Text('编辑影片'),
            backgroundColor: p.background,
            surfaceTintColor: Colors.transparent,
          ),
          body: SafeArea(
            top: false,
            child: VideoLayout(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                children: [
                  const VideoEyebrow('EDIT THE FILM'),
                  const SizedBox(height: 10),
                  Text(
                    '让作品更贴近你的想法',
                    style: TextStyle(
                      color: p.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '只修改展示信息，影片内容和生成记录不会改变。',
                    style: TextStyle(color: p.muted, fontSize: 13, height: 1.7),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    '作品标题',
                    style: TextStyle(
                      color: p.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('video-edit-title'),
                    controller: _title,
                    enabled: !_saving,
                    maxLength: 35,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    buildCounter: (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                    maxLines: 2,
                    minLines: 1,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: '给这部影片一个名字',
                      errorText: titleError,
                      helperText: longOriginalTitle
                          ? '原标题超过 35 字；修改标题时请缩短'
                          : '最多 35 字；已有标题不可清空',
                    ),
                  ),
                  Text(
                    longOriginalTitle
                        ? '原标题 $titleLength 字'
                        : '$titleLength / 35',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: titleError == null
                          ? p.muted
                          : Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(color: p.border),
                  const SizedBox(height: 24),
                  if (_canEditCover)
                    VideoImageInput(
                      label: '作品封面',
                      fieldKey: 'video-edit-cover',
                      attachment: _image,
                      api: _files,
                      picker: _picker,
                      enabled: !_saving,
                      allowRemove: false,
                      preferUploadedPreview: true,
                      expandAddressInitially: false,
                      helper: '从相册选择后先上传，获得图片地址并预览，再保存到作品。也可展开图片地址输入。',
                    )
                  else ...[
                    Text(
                      '作品封面',
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: VideoCover(uri: widget.task.coverUri),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '影片与自动封面完成保存后，才能更换封面；现在仍可修改标题。',
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 12,
                        height: 1.7,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (_error != null) ...[
                    VideoNotice(_error!, error: true),
                    const SizedBox(height: 16),
                  ],
                  FilledButton(
                    key: const Key('video-edit-save'),
                    onPressed: _saving || _image.busy ? null : _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(_saving ? '正在保存…' : '保存修改'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '保存后会同步显示在作品列表和影片详情。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 11, height: 1.7),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
