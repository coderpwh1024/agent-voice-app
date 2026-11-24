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
  bool _pageError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      final foreground =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (!foreground || ModalRoute.isCurrentOf(context) != true) {
        return;
      }
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
        setState(() {
          _error = imageError(error);
          _pageError = more;
        });
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
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final count = _tasks.length;
    final error = _error;
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
              final textScaler = MediaQuery.textScalerOf(context);
              final largeText = textScaler.scale(14) >= 20;
              final wrapHeading =
                  textScaler.scale(30) * 5 + 8 > constraints.maxWidth - 48;
              final columns = constraints.maxWidth >= 378 && !largeText ? 2 : 1;
              return RefreshIndicator(
                onRefresh: _load,
                child: CustomScrollView(
                  key: const PageStorageKey('image-studio-works'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            EditorialHeading(
                              eyebrow: '',
                              title: wrapHeading ? '图像\n工作室' : '图像工作室',
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _create,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('新建图像'),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '我的作品',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            const Divider(height: 1),
                          ],
                        ),
                      ),
                    ),
                    if (_loading && !_loaded)
                      const SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverToBoxAdapter(
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      ),
                    if (error != null && !_pageError)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                        sliver: SliverToBoxAdapter(
                          child: ImageNotice(text: error, onRetry: _load),
                        ),
                      ),
                    if (_loaded && count == 0 && error == null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                        sliver: SliverToBoxAdapter(
                          child: const _EmptyGallery(),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverList.builder(
                        itemCount: (count + columns - 1) ~/ columns,
                        itemBuilder: (context, row) {
                          final index = row * columns;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _tile(index)),
                                if (columns == 2) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: index + 1 < count
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
                    if (_page < _totalPages || (error != null && _pageError))
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            children: [
                              if (error != null && _pageError)
                                ImageNotice(text: error),
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () => _load(more: true),
                                child: Text(
                                  _loading
                                      ? '正在查询…'
                                      : error != null && _pageError
                                      ? '重试加载更多'
                                      : '加载更多',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
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
    return ImageGalleryTile(
      key: ValueKey(task.id),
      title: task.displayTitle,
      uri: task.resultUri,
      metadata: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImageStatusLine(status: task.status),
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              Text('#${task.id}'),
              if (task.createdAt case final date?) Text(imageStudioDate(date)),
            ],
          ),
        ],
      ),
      onTap: () => _open(task),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        child: Column(
          children: [
            Icon(Icons.photo_library_outlined, color: palette.accentInk),
            const SizedBox(height: 12),
            Text(
              '还没有图像作品',
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '新建图像后，可以在这里查看进度和成图。',
              style: TextStyle(color: palette.muted, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
