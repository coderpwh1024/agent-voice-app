import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/file_api.dart';
import 'data/video_image.dart';
import 'video_image_input.dart';
import '../../core/config/app_config.dart';
import '../../core/api/video_reference.dart';
import 'data/video_api.dart';
import 'data/video_models.dart';
import 'video_detail_page.dart';
import 'video_widgets.dart';

class VideoCreatePage extends StatefulWidget {
  const VideoCreatePage({
    super.key,
    required this.config,
    this.api,
    this.fileApi,
    this.imagePicker,
  });
  final AppConfig config;
  final VideoApi? api;
  final FileApi? fileApi;
  final VideoImagePicker? imagePicker;
  @override
  State<VideoCreatePage> createState() => _VideoCreatePageState();
}

class _VideoCreatePageState extends State<VideoCreatePage> {
  final _prompt = TextEditingController();
  final _seed = TextEditingController();
  final _title = TextEditingController();
  final _cover = TextEditingController();
  final _firstFrame = TextEditingController();
  final _lastFrame = TextEditingController();
  bool _audio = true, _promptExtend = true;
  bool get _isWan => VideoDraft.isWanModel(_model);
  late final FileApi _files;
  late final VideoImagePicker _imagePicker;
  late final VideoImageAttachment _firstImage, _lastImage, _coverImage;
  bool get _uploading =>
      _firstImage.busy || _lastImage.busy || _coverImage.busy;
  bool get _editingLocked => _locked || _uploading;
  final _form = GlobalKey<FormState>();
  late final VideoApi _api;
  String _model = VideoDraft.models.first,
      _resolution = '1080P',
      _ratio = '16:9';
  int _duration = 5;
  bool _watermark = true, _submitting = false;
  VideoDraft? _submittedDraft;
  String? _idempotencyKey, _error;
  bool get _locked => _submittedDraft != null;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? VideoApi(widget.config);
    _files = widget.fileApi ?? FileApi(widget.config);
    _imagePicker = widget.imagePicker ?? VideoImagePicker();
    final pending = _api.pendingSubmission;
    if (pending != null) {
      final draft = pending.draft;
      _submittedDraft = draft;
      _idempotencyKey = pending.key;
      _prompt.text = draft.prompt;
      _title.text = draft.title ?? '';
      _cover.text = draft.coverUrl ?? '';

      _model = draft.model;
      _firstFrame.text = draft.firstFrameUrl ?? '';
      _lastFrame.text = draft.lastFrameUrl ?? '';
      _audio = draft.audio ?? true;
      _promptExtend = draft.promptExtend ?? true;
      _resolution = draft.resolution;
      _ratio = draft.ratio;
      _duration = draft.duration;
      _watermark = draft.watermark;
      _seed.text = draft.seed?.toString() ?? '';
      _error = '还有一次提交的结果待确认。重试会核对原提交，避免重复生成。';
    }
    _firstImage = VideoImageAttachment(_firstFrame)..addListener(_mediaChanged);
    _lastImage = VideoImageAttachment(_lastFrame)..addListener(_mediaChanged);
    _coverImage = VideoImageAttachment(_cover, forFrame: false)
      ..addListener(_mediaChanged);
  }

  void _mediaChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _firstImage.dispose();
    _lastImage.dispose();
    _coverImage.dispose();
    if (widget.fileApi == null) _files.close();
    _prompt.dispose();
    _seed.dispose();
    _title.dispose();
    _cover.dispose();
    _firstFrame.dispose();
    _lastFrame.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _uploading) return;
    if ((_isWan && (_firstImage.needsUpload || _lastImage.needsUpload)) ||
        _coverImage.needsUpload) {
      setState(() => _error = '请先完成图片上传，或移除未上传的图片');
      return;
    }
    if (VideoDraft.seedError(_seed.text, _model) case final error?) {
      setState(() => _error = error);
      return;
    }
    final draft =
        _submittedDraft ??
        VideoDraft(
          prompt: _prompt.text,
          title: _title.text,
          coverUrl: _cover.text,
          model: _model,
          firstFrameUrl: _isWan ? _firstFrame.text : null,
          lastFrameUrl: _isWan ? _lastFrame.text : null,
          audio: _isWan ? _audio : null,
          promptExtend: _isWan ? _promptExtend : null,
          resolution: _resolution,
          ratio: _ratio,
          duration: _duration,
          watermark: _watermark,
          seed: int.tryParse(_seed.text.trim()),
        );
    if (draft.validationError case final error?) {
      setState(() => _error = error);
      return;
    }
    if (!_form.currentState!.validate()) {
      setState(() => _error = '请检查表单中的输入，修正后再提交');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submittedDraft = draft;
      _idempotencyKey ??= VideoApi.newIdempotencyKey();
      _submitting = true;
      _error = null;
    });
    try {
      _api.pendingSubmission = VideoSubmission(draft, _idempotencyKey!);
      final task = await _api.create(draft, _idempotencyKey!);
      _api.pendingSubmission = null;
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => VideoDetailPage(
            config: widget.config,
            initialTask: task,
            recordId: task.id,
            api: widget.api,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        final rejected =
            error is ApiException &&
            [401, 403, 422, 503].contains(error.statusCode);
        if (rejected) {
          _submittedDraft = null;
          _idempotencyKey = null;
          _api.pendingSubmission = null;
        }
        _error = rejected
            ? videoError(error)
            : '${videoError(error)}\n重试会核对同一次提交，不会新建重复任务。';
      });
    }
  }

  Widget _select(
    String label,
    String value,
    List<String> values,
    ValueChanged<String> onChanged, {
    String Function(String)? display,
  }) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$value'),
    initialValue: value,
    dropdownColor: VideoPalette(context).surface,
    isExpanded: true,
    isDense: false,
    itemHeight: null,
    decoration: InputDecoration(labelText: label, filled: false),
    items: values
        .map(
          (v) => DropdownMenuItem(
            value: v,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(display?.call(v) ?? v),
            ),
          ),
        )
        .toList(),
    onChanged: _editingLocked
        ? null
        : (v) {
            if (v != null) setState(() => onChanged(v));
          },
  );

  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    return VideoTheme(
      child: PopScope(
        canPop: !_submitting,
        child: Scaffold(
          backgroundColor: p.background,
          appBar: AppBar(
            title: const Text('创作视频'),
            backgroundColor: p.background,
            surfaceTintColor: Colors.transparent,
          ),
          body: SafeArea(
            top: false,
            child: VideoLayout(
              child: Form(
                key: _form,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  // Keep the complete form mounted so validation includes every field.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const VideoPageHeading(
                        eyebrow: 'THE CREATIVE DESK',
                        title: '从一个画面开始。',
                        subtitle: '文字是起点，下一帧交给想象。',
                      ),
                      const SizedBox(height: 28),
                      _select('生成模型', _model, VideoDraft.models, (v) {
                        _model = v;
                        if (!VideoDraft.resolutionsFor(v)
                            .contains(_resolution)) {
                          _resolution = '720P';
                        }
                        if (!VideoDraft.ratiosFor(v).contains(_ratio)) {
                          _ratio = '16:9';
                        }
                        if (!_isWan) {
                          _duration = _duration == -1
                              ? 5
                              : _duration.clamp(3, 15);
                          if (int.tryParse(_seed.text.trim()) == -1) {
                            _seed.clear();
                          }
                        }
                        _error = null;
                      }, display: VideoReference.modelName),
                      const SizedBox(height: 20),
                      VideoPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const VideoEyebrow('01 / SCENE'),
                            const SizedBox(height: 14),
                            Text(
                              '想看见什么？',
                              style: TextStyle(
                                color: p.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('video-prompt'),
                              controller: _prompt,
                              enabled: !_editingLocked,
                              minLines: 4,
                              maxLines: 9,
                              decoration: const InputDecoration(
                                hintText:
                                    '比如：落日洒进海边咖啡馆，白色纱帘随风轻轻摆动，镜头缓慢推进，温暖的胶片质感。',
                                hintStyle: TextStyle(height: 1.8, fontSize: 14),
                              ),
                              validator: (v) => VideoDraft(
                                prompt: v ?? '',
                                model: _model,
                                firstFrameUrl: _isWan ? _firstFrame.text : null,
                              ).promptError,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final entry in const {
                                  '海边日落':
                                      '夕阳下的海岸，浪花轻轻拍打沙滩，镜头缓慢横移，暖色胶片质感，宁静而浪漫。',
                                  '日常切片': '午后阳光穿过窗边的绿植，一杯咖啡升起热气，镜头缓慢推进，柔和自然光，生活电影感。',
                                  '城市漫游': '雨后的城市街道，霓虹倒映在水面上，镜头低角度缓慢前行，细腻的电影光影。',
                                }.entries)
                                  ActionChip(
                                    label: Text(entry.key),
                                    avatar: const Icon(
                                      Icons.auto_awesome_outlined,
                                      size: 14,
                                    ),
                                    onPressed: _editingLocked
                                        ? null
                                        : () => setState(
                                            () => _prompt.text = entry.value,
                                          ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isWan ? '描述主体、动作、光线与镜头。最多 20000 个字符；提供首帧时可留空。' : '描述主体、动作、光线与镜头，让画面更接近你的想象。\n最多 5000 个字符，其中中文最多 2500 字。',
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 11,
                                height: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isWan) ...[
                        const SizedBox(height: 16),
                        VideoPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const VideoEyebrow('FRAME INPUTS'),
                              const SizedBox(height: 14),
                              Text(
                                '从图片开始（可选）',
                                style: TextStyle(
                                  color: p.ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '从相册选择图片，上传完成后即可用于生成。也可以只写文字。',
                                style: TextStyle(
                                  color: p.muted,
                                  fontSize: 12,
                                  height: 1.7,
                                ),
                              ),
                              const SizedBox(height: 16),
                              VideoImageInput(
                                label: '首帧图片',
                                fieldKey: 'video-first-frame',
                                attachment: _firstImage,
                                api: _files,
                                picker: _imagePicker,
                                enabled: !_editingLocked,
                                helper: '选择一张图片，让它成为影片的开始。有首帧时，画面描述可以留空。',
                              ),
                              const SizedBox(height: 20),
                              VideoImageInput(
                                label: '尾帧图片',
                                fieldKey: 'video-last-frame',
                                attachment: _lastImage,
                                api: _files,
                                picker: _imagePicker,
                                enabled: !_editingLocked,
                                helper: '可选；需要同时提供首帧，用它指定影片结束的画面。',
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '支持 JPG、PNG（无透明通道）、WebP、BMP；每张不超过 20 MB，宽高 240–8000 像素，宽高比不超过 8:1。',
                                style: TextStyle(
                                  color: p.muted,
                                  fontSize: 12,
                                  height: 1.7,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      VideoPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const VideoEyebrow('02 / THE COVER'),
                            const SizedBox(height: 14),
                            Text(
                              '给作品一个名字',
                              style: TextStyle(
                                color: p.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isWan
                                  ? '标题可选；未填写时从描述提取，仅图片创作使用默认标题。'
                                  : '标题可选；未填写时，会从画面描述中提取。',
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 12,
                                height: 1.7,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const Key('video-title'),
                              controller: _title,
                              enabled: !_editingLocked,
                              maxLines: 2,
                              minLines: 1,
                              decoration: const InputDecoration(
                                labelText: '视频标题（可选）',
                                hintText: '比如：在海边，等一场日落',
                                helperText: '最多 200 个字符；最终标题以任务返回结果为准',
                              ),
                              validator: VideoDraft.titleError,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '封面会从成片自动提取，无需另外准备。',
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 12,
                                height: 1.7,
                              ),
                            ),
                            ExpansionTile(
                              key: const Key('video-custom-cover'),
                              tilePadding: EdgeInsets.zero,
                              maintainState: true,
                              initiallyExpanded: _cover.text.isNotEmpty,
                              title: const Text(
                                '自定义暂存封面（可选）',
                                style: TextStyle(fontSize: 13),
                              ),
                              children: [
                                VideoImageInput(
                                  label: '暂存封面',
                                  fieldKey: 'video-cover-url',
                                  attachment: _coverImage,
                                  api: _files,
                                  picker: _imagePicker,
                                  enabled: !_editingLocked,
                                  helper: '仅作生成期间的展示封面，成片后由视频画面替换。',
                                  previewLabel: '预览封面',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      VideoPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const VideoEyebrow('03 / FILM SETTINGS'),
                            const SizedBox(height: 18),
                            _select(
                              '画面比例',
                              _ratio,
                              VideoDraft.ratiosFor(_model),
                              (v) => _ratio = v,
                              display: (v) => switch (v) {
                                'adaptive' => '自适应画幅',
                                '16:9' => '16:9 · 横向电影',
                                '9:16' => '9:16 · 竖屏故事',
                                '1:1' => '1:1 · 方形画幅',
                                _ => v,
                              },
                            ),
                            const SizedBox(height: 16),
                            _select(
                              '清晰度',
                              _resolution,
                              VideoDraft.resolutionsFor(_model),
                              (v) => _resolution = v,
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                Text(
                                  '影片时长',
                                  style: TextStyle(
                                    color: p.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  _duration == -1 ? '智能时长' : '$_duration 秒',
                                  style: TextStyle(
                                    color: p.accentInk,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            if (_isWan)
                              SwitchListTile(
                                key: const Key('video-smart-duration'),
                                contentPadding: EdgeInsets.zero,
                                title: const Text('智能时长'),
                                subtitle: const Text('由模型决定影片长度'),
                                value: _duration == -1,
                                onChanged: _editingLocked
                                    ? null
                                    : (v) => setState(
                                        () => _duration = v ? -1 : 5,
                                      ),
                              ),
                            if (_duration != -1)
                              Slider(
                                value: _duration.toDouble(),
                                min: _isWan ? 2 : 3,
                                max: _isWan ? 30 : 15,
                                divisions: _isWan ? 28 : 12,
                                label: '$_duration 秒',
                                activeColor: p.accentInk,
                                onChanged: _editingLocked
                                    ? null
                                    : (v) =>
                                          setState(() => _duration = v.round()),
                              ),
                            const SizedBox(height: 2),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: const Text(
                                '更多设置',
                                style: TextStyle(fontSize: 14),
                              ),
                              children: [
                                if (_isWan) ...[
                                  SwitchListTile(
                                    key: const Key('video-audio'),
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('生成音轨'),
                                    value: _audio,
                                    onChanged: _editingLocked
                                        ? null
                                        : (v) => setState(() => _audio = v),
                                  ),
                                  SwitchListTile(
                                    key: const Key('video-prompt-extend'),
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('智能改写提示词'),
                                    value: _promptExtend,
                                    onChanged: _editingLocked
                                        ? null
                                        : (v) =>
                                              setState(() => _promptExtend = v),
                                  ),
                                ],
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    '保留水印',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  value: _watermark,
                                  onChanged: _editingLocked
                                      ? null
                                      : (v) => setState(() => _watermark = v),
                                ),
                                TextFormField(
                                  key: const Key('video-seed'),
                                  controller: _seed,
                                  enabled: !_editingLocked,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        signed: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: '随机种子（可选）',
                                    hintText: _isWan
                                        ? '-1 或 0–2147483647'
                                        : '0–2147483647',
                                    helperText: _isWan
                                        ? '-1 表示随机；留空采用服务默认值'
                                        : null,
                                  ),
                                  validator: (v) =>
                                      VideoDraft.seedError(v, _model),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        VideoNotice(_error!, error: true),
                        const SizedBox(height: 16),
                      ],
                      FilledButton.icon(
                        key: const Key('video-submit'),
                        onPressed: _submitting || _uploading ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: p.ink,
                          foregroundColor: p.background,
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: _submitting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: p.background,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_rounded, size: 19),
                        label: Text(
                          _uploading
                              ? '图片上传中…'
                              : _submitting
                              ? '正在提交，请稍候…'
                              : _locked
                              ? '核对并重试原提交'
                              : '生成我的影片',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '提交后会在后台生成，可在「我的作品」查看进展。\n生成使用服务端模型额度，提交后暂不支持撤回。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: p.muted,
                          fontSize: 11,
                          height: 1.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
