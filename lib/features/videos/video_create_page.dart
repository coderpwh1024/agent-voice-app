import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import 'data/video_api.dart';
import 'data/video_models.dart';
import 'video_detail_page.dart';
import 'video_widgets.dart';

class VideoCreatePage extends StatefulWidget {
  const VideoCreatePage({super.key, required this.config, this.api});
  final AppConfig config;
  final VideoApi? api;
  @override
  State<VideoCreatePage> createState() => _VideoCreatePageState();
}

class _VideoCreatePageState extends State<VideoCreatePage> {
  final _prompt = TextEditingController();
  final _seed = TextEditingController();
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
    final pending = _api.pendingSubmission;
    if (pending != null) {
      final draft = pending.draft;
      _submittedDraft = draft;
      _idempotencyKey = pending.key;
      _prompt.text = draft.prompt;
      _model = draft.model;
      _resolution = draft.resolution;
      _ratio = draft.ratio;
      _duration = draft.duration;
      _watermark = draft.watermark;
      _seed.text = draft.seed?.toString() ?? '';
      _error = '还有一次提交的结果待确认。重试会核对原提交，避免重复生成。';
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _seed.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    final draft =
        _submittedDraft ??
        VideoDraft(
          prompt: _prompt.text,
          model: _model,
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
    isExpanded: true,
    decoration: InputDecoration(labelText: label, filled: false),
    items: values
        .map(
          (v) => DropdownMenuItem(
            value: v,
            child: Text(display?.call(v) ?? v, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: _locked
        ? null
        : (v) {
            if (v != null) setState(() => onChanged(v));
          },
  );

  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    return PopScope(
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
                children: [
                  const VideoEyebrow('FROM A THOUGHT TO A FILM'),
                  const SizedBox(height: 10),
                  Text(
                    '让想象，\n有了下一帧。',
                    style: TextStyle(
                      fontSize: 32,
                      height: 1.3,
                      letterSpacing: -1.2,
                      fontWeight: FontWeight.w800,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '一句描述，一段属于你的电影。',
                    style: TextStyle(color: p.muted, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  VideoPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const VideoEyebrow('01 / YOUR SCENE'),
                        const SizedBox(height: 14),
                        Text(
                          '想看见什么？',
                          style: TextStyle(
                            color: p.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('video-prompt'),
                          controller: _prompt,
                          enabled: !_locked,
                          minLines: 5,
                          maxLines: 9,
                          decoration: const InputDecoration(
                            hintText: '比如：落日洒进海边咖啡馆，白色纱帘随风轻轻摆动，镜头缓慢推进，温暖的胶片质感。',
                            hintStyle: TextStyle(height: 1.8, fontSize: 14),
                          ),
                          validator: (v) =>
                              VideoDraft(prompt: v ?? '').validationError,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final entry in const {
                              '海边日落': '夕阳下的海岸，浪花轻轻拍打沙滩，镜头缓慢横移，暖色胶片质感，宁静而浪漫。',
                              '日常切片':
                                  '午后阳光穿过窗边的绿植，一杯咖啡升起热气，镜头缓慢推进，柔和自然光，生活电影感。',
                              '城市漫游': '雨后的城市街道，霓虹倒映在水面上，镜头低角度缓慢前行，细腻的电影光影。',
                            }.entries)
                              ActionChip(
                                label: Text(entry.key),
                                avatar: const Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 14,
                                ),
                                onPressed: _locked
                                    ? null
                                    : () => setState(
                                        () => _prompt.text = entry.value,
                                      ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '描述主体、动作、光线与镜头，让画面更接近你的想象。\n最多 5000 个字符，其中中文最多 2500 字。',
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 11,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  VideoPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const VideoEyebrow('02 / THE LITTLE DETAILS'),
                        const SizedBox(height: 18),
                        _select(
                          '生成模型',
                          _model,
                          VideoDraft.models,
                          (v) {
                            _model = v;
                            if (v == VideoDraft.models.last &&
                                _resolution == '480P') {
                              _resolution = '720P';
                            }
                          },
                          display: (v) => v == VideoDraft.models.first
                              ? 'HappyHorse 1.1'
                              : 'HappyHorse 1.0',
                        ),
                        const SizedBox(height: 16),
                        _select(
                          '画面比例',
                          _ratio,
                          VideoDraft.ratios,
                          (v) => _ratio = v,
                          display: (v) => switch (v) {
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
                          _model == VideoDraft.models.last
                              ? ['720P', '1080P']
                              : ['480P', '720P', '1080P'],
                          (v) => _resolution = v,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '影片时长',
                                style: TextStyle(
                                  color: p.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '$_duration 秒',
                              style: const TextStyle(
                                color: VideoPalette.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _duration.toDouble(),
                          min: 3,
                          max: 15,
                          divisions: 12,
                          label: '$_duration 秒',
                          activeColor: VideoPalette.accent,
                          onChanged: _locked
                              ? null
                              : (v) => setState(() => _duration = v.round()),
                        ),
                        const SizedBox(height: 2),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text(
                            '更多设置',
                            style: TextStyle(fontSize: 14),
                          ),
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                '保留水印',
                                style: TextStyle(fontSize: 14),
                              ),
                              value: _watermark,
                              onChanged: _locked
                                  ? null
                                  : (v) => setState(() => _watermark = v),
                            ),
                            TextFormField(
                              controller: _seed,
                              enabled: !_locked,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '随机种子（可选）',
                                hintText: '0–2147483647',
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                final n = int.tryParse(v.trim());
                                return n == null || n < 0 || n > 2147483647
                                    ? '请输入 0–2147483647 的整数'
                                    : null;
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    VideoNotice(_error!),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    key: const Key('video-submit'),
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: VideoPalette.accent,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_rounded, size: 19),
                    label: Text(
                      _submitting
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
                    style: TextStyle(color: p.muted, fontSize: 11, height: 1.8),
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
