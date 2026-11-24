import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/file_api.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editorial_widgets.dart';
import 'data/image_api.dart';
import 'data/image_models.dart';
import 'image_create_page.dart';
import 'image_loop_detail_page.dart';
import 'image_widgets.dart';

class ImageDetailPage extends StatefulWidget {
  const ImageDetailPage({
    super.key,
    required this.config,
    required this.id,
    this.initialTask,
    this.api,
    this.files,
  });

  final AppConfig config;
  final int id;
  final ImageTask? initialTask;
  final ImageApi? api;
  final FileApi? files;

  @override
  State<ImageDetailPage> createState() => _ImageDetailPageState();
}

class _ImageDetailPageState extends State<ImageDetailPage>
    with WidgetsBindingObserver {
  late final _api = widget.api ?? ImageApi(widget.config);
  late final _files = widget.files ?? FileApi(widget.config);
  ImageTask? _task;
  Timer? _poll;
  bool _fetching = false, _editing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _task = widget.initialTask;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      final foreground =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (foreground &&
          ModalRoute.isCurrentOf(context) == true &&
          _task?.status.isActive == true) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.isCurrentOf(context) == true) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.api == null) _api.close();
    if (widget.files == null) _files.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_fetching || _editing) return;
    setState(() => _fetching = true);
    try {
      final task = await _api.detail(widget.id);
      if (!mounted) return;
      setState(() {
        _task = task;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (error is ApiException && error.statusCode == 404) _task = null;
        _error = imageError(error);
      });
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _editImage(ImageTask source) async {
    final created = await Navigator.of(context).push<ImageTask>(
      MaterialPageRoute(
        builder: (_) =>
            ImageCreatePage(api: _api, files: _files, source: source),
      ),
    );
    if (!mounted || created == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImageDetailPage(
          config: widget.config,
          id: created.id,
          initialTask: created,
          api: _api,
          files: _files,
        ),
      ),
    );
  }

  Future<void> _rename(ImageTask task) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initialTitle: task.title),
    );
    if (!mounted || title == null || title == task.title) return;
    setState(() {
      _editing = true;
      _error = null;
    });
    try {
      final updated = await _api.rename(task.id, title);
      if (mounted) setState(() => _task = updated);
    } catch (error) {
      if (mounted) setState(() => _error = imageError(error));
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _delete(ImageTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这张图像？'),
        content: const Text('这项任务将从作品中移除，无法在 App 内恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _editing = true;
      _error = null;
    });
    try {
      await _api.delete(task.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 404) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _error = '删除未确认，请刷新核实。';
      });
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _openLoop(ImageTask task) async {
    final rootId = task.loopRootImageId ?? task.id;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImageLoopDetailPage(
          rootId: rootId,
          initialRoot: rootId == task.id ? task : null,
          api: _api,
          files: _files,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final result = task?.resultUri;
    final palette = AppPalette(context);
    final busy = _editing || _fetching;
    return Scaffold(
      appBar: AppBar(
        title: const Text('图像详情'),
        actions: [
          IconButton(
            tooltip: '刷新图像状态',
            onPressed: busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (task != null)
            PopupMenuButton<String>(
              tooltip: '图像操作',
              enabled: !busy,
              onSelected: (action) {
                if (action == 'rename') {
                  unawaited(_rename(task));
                } else {
                  unawaited(_delete(task));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('修改标题')),
                if (task.status.canDelete)
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      '删除图像',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: EditorialLayout(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              if (task == null && busy)
                const EditorialPanel(child: Text('正在读取图像详情…')),
              if (_error case final error?) ...[
                ImageNotice(text: error, onRetry: busy ? null : _refresh),
                const SizedBox(height: 16),
              ],
              if (task != null) ...[
                Text(
                  task.displayTitle,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(height: 1.35, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ImageStatusLine(status: task.status),
                    Text('#${task.id}', style: TextStyle(color: palette.muted)),
                    if (task.createdAt case final date?)
                      Text(
                        imageStudioDate(date),
                        style: TextStyle(color: palette.muted),
                      ),
                    if (task.loopVersion case final version?)
                      Text(
                        'LOOP 第 $version 版',
                        style: TextStyle(color: palette.accentInk),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (result != null) ...[
                  ImageArtwork(image: task),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (task.loopRootImageId == null)
                        FilledButton.icon(
                          onPressed: busy ? null : () => _editImage(task),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('继续编辑'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => openImageOriginal(context, task),
                        icon: const Icon(Icons.open_in_full_rounded),
                        label: const Text('查看原图'),
                      ),
                    ],
                  ),
                ] else
                  EditorialPanel(
                    child: Text(switch (task.status) {
                      ImageTaskStatus.storing => '图像已生成，正在保存到云端。',
                      ImageTaskStatus.failed => '生成未完成。请检查画面描述和参考图后再试。',
                      ImageTaskStatus.submissionUnknown =>
                        '服务暂时无法确认这次提交。可以刷新核实当前状态。',
                      ImageTaskStatus.canceled => '这项图像任务已取消。',
                      ImageTaskStatus.succeeded => '图像地址暂不可用，请刷新。',
                      ImageTaskStatus.unknown => '请刷新查询任务状态。',
                      _ => '可以返回作品列表。生成进度会在后台更新。',
                    }, style: TextStyle(color: palette.muted, height: 1.7)),
                  ),
                if (task.loopRootImageId != null || result != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: busy ? null : () => _openLoop(task),
                      icon: const Icon(Icons.history_rounded),
                      label: Text(
                        task.loopRootImageId == null ? 'LOOP 编辑' : '查看 LOOP',
                      ),
                    ),
                  ),
                ],
                if (task.prompt case final prompt?) ...[
                  const SizedBox(height: 28),
                  const Divider(height: 1),
                  const SizedBox(height: 24),
                  Text(
                    task.sourceImageId == null ? '画面描述' : '修改描述',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    prompt,
                    style: TextStyle(height: 1.7, color: palette.ink),
                  ),
                ],
                if (task.sourceImageId case final parentId?) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => ImageDetailPage(
                            config: widget.config,
                            id: parentId,
                            api: _api,
                            files: _files,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.history_rounded),
                      label: Text('查看编辑底图 #$parentId'),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({this.initialTitle});

  final String? initialTitle;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改标题'),
    scrollable: true,
    content: Form(
      key: _form,
      child: TextFormField(
        autofocus: true,
        controller: _controller,
        decoration: const InputDecoration(labelText: '标题'),
        validator: (value) {
          final length = value?.trim().runes.length ?? 0;
          return length == 0 || length > ImageDraft.maxTitleLength
              ? '请输入 1–${ImageDraft.maxTitleLength} 个字符'
              : null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState?.validate() ?? false) {
            Navigator.of(context).pop(_controller.text.trim());
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}
