import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/file_api.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editorial_widgets.dart';
import 'data/image_api.dart';
import 'data/image_asset_picker.dart';
import 'data/image_models.dart';
import 'image_widgets.dart';

class ImageCreatePage extends StatefulWidget {
  const ImageCreatePage({
    super.key,
    required this.api,
    required this.files,
    this.source,
    this.picker,
  });

  final ImageApi api;
  final FileApi files;
  final ImageTask? source;
  final StudioImagePicker? picker;

  @override
  State<ImageCreatePage> createState() => _ImageCreatePageState();
}

class _ImageCreatePageState extends State<ImageCreatePage> {
  final _form = GlobalKey<FormState>();
  final _prompt = TextEditingController();
  final _title = TextEditingController();
  final _attachments = <UploadedFileMetadata>[];
  late final _picker = widget.picker ?? StudioImagePicker();

  ImageCanvasSize _size = ImageCanvasSize.automatic;
  ImageSubmission? _pending;
  StudioImageAsset? _failedUpload;
  String? _uploadError, _submitError;
  bool _uploading = false, _submitting = false;

  int? get _sourceId => widget.source?.id;
  int get _limit => _sourceId == null ? 3 : 2;
  bool get _formEnabled => _pending == null && !_submitting;

  @override
  void initState() {
    super.initState();
    _pending = widget.api.pendingSubmissions[_sourceId];
    if (_pending case final submission?) {
      _prompt.text = submission.draft.prompt;
      _title.text = submission.draft.title ?? '';
      _size = submission.draft.size;
      _submitError = '上次提交结果待核实。确认提交会使用原请求编号。';
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _chooseImage({bool retry = false}) async {
    if (_uploading || !_formEnabled || _attachments.length >= _limit) return;
    setState(() => _uploading = true);
    try {
      final picked = retry ? _failedUpload : await _picker.pick();
      if (picked == null || !mounted) return;
      setState(() {
        _failedUpload = picked;
        _uploadError = null;
      });
      final result = await widget.files.upload(
        bytes: picked.bytes,
        name: picked.name,
        contentType: picked.contentType,
      );
      if (!mounted) return;
      if (result.sizeBytes > StudioImagePicker.maxReferenceBytes) {
        throw const FormatException('图片超过大小限制，请更换图片');
      }
      setState(() {
        _attachments.add(result);
        _failedUpload = null;
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _uploadError = error.message);
    } catch (error) {
      if (mounted) setState(() => _uploadError = fileUploadError(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting || _uploading || _failedUpload != null) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final submission =
        _pending ??
        ImageSubmission(
          ImageDraft(
            prompt: _prompt.text,
            title: _title.text,
            sourceFileIds: [
              for (final attachment in _attachments) attachment.id,
            ],
            size: _size,
          ),
          _sourceId,
        );
    if (submission.draft.validate(hasSourceImage: _sourceId != null)
        case final error?) {
      setState(() => _submitError = error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
      _pending = submission;
    });
    final pendingSubmissions = widget.api.pendingSubmissions;
    pendingSubmissions[_sourceId] = submission;
    try {
      final task = await widget.api.submit(submission);
      pendingSubmissions.remove(_sourceId);
      if (mounted) Navigator.of(context).pop(task);
    } catch (error) {
      final uncertain =
          error is! ApiException ||
          error.statusCode == 0 ||
          error.statusCode >= 500;
      if (!uncertain) pendingSubmissions.remove(_sourceId);
      if (!mounted) return;
      setState(() {
        if (!uncertain) _pending = null;
        _submitError = uncertain ? '提交结果待核实。确认提交会使用原请求编号。' : imageError(error);
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final edit = _sourceId != null;
    final palette = AppPalette(context);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: EditorialLayout(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                EditorialHeading(eyebrow: '', title: edit ? '继续编辑' : '新建图像'),
                const SizedBox(height: 24),
                if (widget.source case final source?) ...[
                  Text(
                    '原图 · ${source.displayTitle}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 184),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ImagePreview(
                          uri: source.resultUri,
                          label: '原图预览',
                          fit: BoxFit.contain,
                          showFeedback: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                TextFormField(
                  key: const Key('image-prompt'),
                  controller: _prompt,
                  enabled: _formEnabled,
                  textInputAction: TextInputAction.newline,
                  minLines: 4,
                  maxLines: 7,
                  decoration: InputDecoration(
                    alignLabelWithHint: true,
                    labelText: edit ? '修改描述' : '画面描述',
                    hintText: edit
                        ? '例如：保留构图，把天空换成薄雾下的清晨'
                        : '例如：雨后的山间小屋，窗里透出暖黄色的灯光',
                  ),
                  validator: (value) {
                    final length = value?.trim().runes.length ?? 0;
                    if (length == 0) return '请输入画面描述';
                    if (length > ImageDraft.maxPromptLength) {
                      return '描述最多 ${ImageDraft.maxPromptLength} 个字符';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  enabled: _formEnabled,
                  decoration: const InputDecoration(labelText: '标题（选填）'),
                  validator: (value) =>
                      (value?.trim().runes.length ?? 0) >
                          ImageDraft.maxTitleLength
                      ? '标题最多 ${ImageDraft.maxTitleLength} 个字符'
                      : null,
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<ImageCanvasSize>(
                  initialValue: _size,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '画幅'),
                  items: [
                    for (final size in ImageCanvasSize.values)
                      DropdownMenuItem(value: size, child: Text(size.label)),
                  ],
                  onChanged: _formEnabled
                      ? (size) => setState(() => _size = size!)
                      : null,
                ),
                const SizedBox(height: 24),
                Text(
                  '参考图（选填，最多 $_limit 张）',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '单张不超过 10 MB',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_attachments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final file in _attachments)
                        SizedBox(
                          width: 96,
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox.square(
                                  dimension: 96,
                                  child: ImagePreview(
                                    uri: Uri.parse(file.url),
                                    label: file.name,
                                    cacheWidth: 256,
                                  ),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: _formEnabled && !_uploading
                                    ? () => setState(
                                        () => _attachments.remove(file),
                                      )
                                    : null,
                                child: const Text('移除'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                if (_pending case final pending?
                    when _attachments.isEmpty &&
                        pending.draft.sourceFileIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '将复用已上传的 ${pending.draft.sourceFileIds.length} 张参考图',
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('image-choose-asset'),
                    onPressed:
                        _formEnabled &&
                            !_uploading &&
                            _attachments.length < _limit
                        ? _chooseImage
                        : null,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(_uploading ? '正在上传…' : '从相册添加'),
                  ),
                ),
                if (_uploading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_uploadError case final error?) ImageNotice(text: error),
                if (_failedUpload != null && !_uploading)
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => _chooseImage(retry: true),
                        child: const Text('重新上传'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _failedUpload = null;
                          _uploadError = null;
                        }),
                        child: const Text('移除失败的参考图'),
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
                if (_submitError case final error?) ...[
                  ImageNotice(text: error),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  key: const Key('image-submit'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: palette.ink,
                    foregroundColor: palette.background,
                  ),
                  onPressed: _uploading || _submitting || _failedUpload != null
                      ? null
                      : _submit,
                  icon: Icon(
                    _pending == null
                        ? Icons.arrow_forward_rounded
                        : Icons.refresh,
                  ),
                  label: Text(
                    _submitting
                        ? '正在提交…'
                        : _pending != null
                        ? '确认提交'
                        : edit
                        ? '提交编辑'
                        : '生成图像',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
