import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_config.dart';
import 'data/video_api.dart';
import 'data/video_models.dart';
import 'video_widgets.dart';
import 'video_playback.dart';

class VideoDetailPage extends StatefulWidget {
  const VideoDetailPage({
    super.key,
    required this.config,
    required this.recordId,
    this.initialTask,
    this.api,
    this.onPlayerDisposed,
  });
  final AppConfig config;
  final int recordId;
  final VideoTask? initialTask;
  final VideoApi? api;
  final ValueChanged<Future<void>>? onPlayerDisposed;
  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage>
    with WidgetsBindingObserver {
  late final VideoApi _api;
  VideoTask? _task;
  String? _error;
  bool _loading = false, _active = true;
  Timer? _timer;
  int _polls = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = widget.api ?? VideoApi(widget.config);
    _task = widget.initialTask;
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _timer?.cancel();
    } else {
      _polls = 0;
      _refresh();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_active && _task?.shouldPoll == true && _polls < 60 && _error == null) {
      _timer = Timer(const Duration(seconds: 10), () {
        _polls++;
        _refresh();
      });
    }
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final task = await _api.detail(widget.recordId);
      if (mounted) setState(() => _task = task);
    } catch (error) {
      if (mounted) setState(() => _error = videoError(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _schedule();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    final task = _task;
    final title = task?.displayTitle ?? '正在读取影片';
    return VideoTheme(
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          title: const Text('影片详情'),
          backgroundColor: p.background,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: '刷新任务',
              onPressed: _loading
                  ? null
                  : () {
                      _polls = 0;
                      _refresh();
                    },
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: VideoLayout(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
                children: [
                  VideoEyebrow(
                    'THE FILM / ${task?.id.toString().padLeft(3, '0') ?? '…'}',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      color: p.ink,
                      fontSize: title.runes.length > 40 ? 20 : 26,
                      height: 1.6,
                      letterSpacing: .1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (task?.playableUri case final uri?)
                    VideoPlayback(
                      key: ValueKey(uri.toString()),
                      uri: uri,
                      coverUri: task?.coverUri,
                      onDisposed: widget.onPlayerDisposed,
                    )
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: VideoCover(
                        uri: task?.coverUri,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: task == null
                                ? const Chip(label: Text('正在读取影片'))
                                : VideoStatusBadge(task),
                          ),
                        ),
                      ),
                    ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    VideoNotice(
                      _error!,
                      error: true,
                      onRetry: _loading ? null : _refresh,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (task != null) ...[
                    VideoPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          VideoStatusBadge(task),
                          const SizedBox(height: 16),
                          Text(
                            task.description,
                            style: TextStyle(color: p.muted, height: 1.8),
                          ),
                          const SizedBox(height: 8),
                          ExpansionTile(
                            initiallyExpanded: task.shouldPoll,
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(
                              top: 12,
                              bottom: 12,
                            ),
                            title: const Text(
                              '创作进程',
                              style: TextStyle(fontSize: 13),
                            ),
                            children: [
                              _Stage(
                                number: '01',
                                title: '提交灵感',
                                subtitle: '任务已记录',
                                done: true,
                              ),
                              _Stage(
                                number: '02',
                                title: '生成画面',
                                subtitle: switch (task.status) {
                                  'SUCCEEDED' => '生成完成',
                                  _ => task.label,
                                },
                                done: task.status == 'SUCCEEDED',
                              ),
                              _Stage(
                                number: '03',
                                title: '保存影片',
                                subtitle: switch (task.storageStatus) {
                                  'STORED' =>
                                    task.playableUri != null
                                        ? '已保存，可播放'
                                        : '已保存，播放地址待核对',
                                  'FAILED' => '保存待重试',
                                  'PENDING' => '正在保存',
                                  _ => '等待生成完成',
                                },
                                done: task.storageStatus == 'STORED',
                                last: true,
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
                          const VideoEyebrow('ABOUT THIS FILM'),
                          const SizedBox(height: 16),
                          _Info(
                            '作品编号',
                            '#${task.id.toString().padLeft(4, '0')}',
                          ),
                          if (task.modelLabel != null)
                            _Info('生成模型', task.modelLabel!),
                          _Info('创建时间', videoDate(task.createdAt)),
                          _Info('最近更新', videoDate(task.updatedAt)),
                          _Info('生成状态', task.status),
                          _Info('保存状态', task.storageStatus),
                          if (task.taskId != null) _Info('任务编号', task.taskId!),
                          if (task.errorCode != null)
                            _Info('状态提示', task.errorCode!),
                        ],
                      ),
                    ),
                    if (task.firstFrameUrl?.isNotEmpty == true ||
                        task.lastFrameUrl?.isNotEmpty == true) ...[
                      const SizedBox(height: 16),
                      VideoPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const VideoEyebrow('SOURCE FRAMES'),
                            const SizedBox(height: 12),
                            Text(
                              '生成素材',
                              style: TextStyle(
                                color: p.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '首尾帧用于生成，作品封面以成片返回结果为准。',
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 12,
                                height: 1.7,
                              ),
                            ),
                            if (task.firstFrameUrl?.isNotEmpty == true)
                              _Info('首帧图片', task.firstFrameUrl!),
                            if (task.lastFrameUrl?.isNotEmpty == true)
                              _Info('尾帧图片', task.lastFrameUrl!),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (task.playableUri != null)
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: task.playableUri.toString()),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('影片链接已复制')),
                            );
                          }
                        },
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('复制影片链接'),
                      ),
                    if (task.shouldPoll)
                      Text(
                        _polls < 60
                            ? '停留此页时每 10 秒查询一次，切到后台会暂停。'
                            : '自动查询已暂停，可下拉刷新；后台生成仍会继续。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: p.muted,
                          fontSize: 11,
                          height: 1.8,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: VideoPalette(context).muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(color: VideoPalette(context).ink, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.done,
    this.last = false,
  });
  final String number, title, subtitle;
  final bool done, last;
  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 20),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: done ? p.blush : p.background,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Center(
              child: done
                  ? Icon(Icons.check_rounded, size: 17, color: p.accentInk)
                  : Text(
                      number,
                      style: TextStyle(color: p.muted, fontSize: 11),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(color: p.muted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
