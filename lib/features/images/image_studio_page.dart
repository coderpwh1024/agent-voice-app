import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/file_api.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editorial_widgets.dart';
import 'data/image_api.dart';
import 'data/image_asset_picker.dart';
import 'data/image_models.dart';
import 'image_create_page.dart';
import 'image_detail_page.dart';
import 'image_widgets.dart';

class ImageStudioPage extends StatefulWidget {
  const ImageStudioPage({
    super.key,
    required this.config,
    this.api,
    this.files,
    this.picker,
  });

  final AppConfig config;
  final ImageApi? api;
  final FileApi? files;
  final StudioImagePicker? picker;

  @override
  State<ImageStudioPage> createState() => _ImageStudioPageState();
}

class _ImageStudioPageState extends State<ImageStudioPage>
    with WidgetsBindingObserver {
  late final _api = widget.api ?? ImageApi(widget.config);
  late final _files = widget.files ?? FileApi(widget.config);
  final _tasks = <ImageTask>[];
  final _pages = <int, List<ImageTask>>{};
  int _lastPolledPage = 0;
  Timer? _poll;
  bool _loading = false, _loaded = false;
  int _page = 1, _totalPages = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      final foreground =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (!foreground || ModalRoute.isCurrentOf(context) != true) return;
      final activePages = _pages.keys.where(
        (page) => _pages[page]!.any((task) => task.status.isActive),
      );
      if (activePages.isEmpty) return;
      final next = activePages
          .where((page) => page > _lastPolledPage)
          .firstOrNull;
      unawaited(_load(pollPage: next ?? activePages.first));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.isCurrentOf(context) == true) {
      unawaited(_load());
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

  Future<void> _load({bool more = false, int? pollPage}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (pollPage == null) _error = null;
    });
    final requested = pollPage ?? (more ? _page + 1 : 1);
    if (pollPage != null) _lastPolledPage = pollPage;
    try {
      final page = await _api.list(page: requested);
      if (!mounted) return;
      setState(() {
        if (!more && pollPage == null) _pages.clear();
        _pages[requested] = page.items;
        _pages.removeWhere((key, _) => key > page.totalPages);
        final seen = <int>{};
        _tasks
          ..clear()
          ..addAll(
            _pages.values
                .expand((tasks) => tasks)
                .where((task) => seen.add(task.id)),
          );
        _page = _pages.keys.lastOrNull ?? 1;
        _totalPages = page.totalPages;
        _loaded = true;
      });
    } catch (error) {
      if (mounted && pollPage == null) {
        setState(() => _error = imageError(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final task = await Navigator.of(context).push<ImageTask>(
      MaterialPageRoute(
        builder: (_) =>
            ImageCreatePage(api: _api, files: _files, picker: widget.picker),
      ),
    );
    if (!mounted) return;
    if (task != null) {
      setState(() {
        _tasks.removeWhere((item) => item.id == task.id);
        _tasks.insert(0, task);
      });
      await _open(task);
    } else {
      await _load();
    }
  }

  Future<void> _open(ImageTask task) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImageDetailPage(
          config: widget.config,
          id: task.id,
          initialTask: task,
          api: _api,
          files: _files,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette(context);
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: '刷新图像作品',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: EditorialLayout(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 392 &&
                      MediaQuery.textScalerOf(context).scale(14) < 20
                  ? 2
                  : 1;
              return RefreshIndicator(
                onRefresh: _load,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const EditorialHeading(
                              eyebrow: '',
                              title: '图像工作室',
                              subtitle: '用文字生成画面，也可以添加参考图或继续编辑已有作品。',
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _create,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                backgroundColor: palette.ink,
                                foregroundColor: palette.background,
                              ),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('新建图像'),
                            ),
                            const SizedBox(height: 28),
                            const Divider(height: 1),
                            const SizedBox(height: 20),
                            Text(
                              '我的作品',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (_loading && !_loaded) ...[
                              const SizedBox(height: 20),
                              const LinearProgressIndicator(minHeight: 2),
                            ],
                            if (_loaded &&
                                _tasks.isEmpty &&
                                _error == null) ...[
                              const SizedBox(height: 12),
                              Text(
                                '新建图像后，可以在这里查看进度与成品。',
                                style: TextStyle(
                                  color: palette.muted,
                                  height: 1.7,
                                ),
                              ),
                            ],
                            if (_error != null && !_loaded) ...[
                              const SizedBox(height: 12),
                              ImageNotice(text: _error!, onRetry: _load),
                            ],
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverList.builder(
                        itemCount: (_tasks.length + columns - 1) ~/ columns,
                        itemBuilder: (context, row) {
                          final index = row * columns;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _tile(index)),
                                if (columns == 2) ...[
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: index + 1 < _tasks.length
                                        ? _tile(index + 1)
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (_loaded && (_page < _totalPages || _error != null))
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            children: [
                              if (_error case final error?)
                                ImageNotice(text: error),
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () => _load(more: _page < _totalPages),
                                child: Text(
                                  _loading
                                      ? '正在查询…'
                                      : _page < _totalPages
                                      ? '加载更多'
                                      : '重试',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _tile(int index) {
    final task = _tasks[index];
    return _ImageTile(
      key: ValueKey(task.id),
      task: task,
      onTap: () => _open(task),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({super.key, required this.task, required this.onTap});

  final ImageTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette(context);
    final theme = Theme.of(context);
    return Material(
      color: palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: palette.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ImagePreview(
                uri: task.resultUri,
                label: task.displayTitle,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.displayTitle,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  DefaultTextStyle.merge(
                    style: theme.textTheme.bodySmall!,
                    child: ImageStatusLine(status: task.status),
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
