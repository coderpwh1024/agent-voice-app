import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import 'data/video_api.dart';
import 'data/video_models.dart';
import 'video_create_page.dart';
import 'video_detail_page.dart';
import 'video_widgets.dart';

class VideoStudioPage extends StatefulWidget {
  const VideoStudioPage({super.key, required this.config, this.api});
  final AppConfig config;
  final VideoApi? api;
  @override
  State<VideoStudioPage> createState() => _VideoStudioPageState();
}

class _VideoStudioPageState extends State<VideoStudioPage> {
  late final VideoApi _api;
  List<VideoTask> _items = [];
  int _filter = 0, _total = 0, _page = 0, _totalPages = 0, _generation = 0;
  bool _loading = false, _loadingMore = false, _hasLoaded = false;
  String? _error;
  bool _failedMore = false;
  bool _grid = true;
  static const _filters = ['全部', '已完成', '生成中', '排队中', '生成失败'];
  static const _statuses = <String?>[
    null,
    'SUCCEEDED',
    'RUNNING',
    'PENDING',
    'FAILED',
  ];
  @override
  void initState() {
    super.initState();
    _api = widget.api ?? VideoApi(widget.config);
    _load();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loading || _loadingMore || _page >= _totalPages)) return;
    final generation = more ? _generation : ++_generation;
    final page = more ? _page + 1 : 1;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _loadingMore = false;
      }
      _error = null;
    });
    try {
      final result = await _api.list(
        page: page,
        status: _statuses[_filter],
        storageStatus: _filter == 1 ? 'STORED' : null,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = more
            ? <int, VideoTask>{
                for (final t in [..._items, ...result.items]) t.id: t,
              }.values.toList()
            : result.items;
        _total = result.total;
        _page = result.page;
        _totalPages = result.totalPages;
        _hasLoaded = true;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = videoError(error);
          _failedMore = more;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _create() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => VideoCreatePage(config: widget.config, api: _api),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _detail(VideoTask task) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(
          config: widget.config,
          recordId: task.id,
          initialTask: task,
          api: _api,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _lookup() async {
    final input = TextEditingController();
    final form = GlobalKey<FormState>();
    final id = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('查找影片'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: input,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '影片编号'),
            validator: (v) {
              final n = int.tryParse(v?.trim() ?? '');
              return n == null || n <= 0 ? '请输入有效的影片编号' : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, int.parse(input.text.trim()));
              }
            },
            child: const Text('查询'),
          ),
        ],
      ),
    );
    // The dialog owns its text field until the reverse transition completes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (!mounted || id == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            VideoDetailPage(config: widget.config, recordId: id, api: _api),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    return VideoTheme(
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          toolbarHeight: 68,
          title: const VideoWordmark(),
          actions: [
            IconButton(
              tooltip: '按编号查询',
              onPressed: _lookup,
              icon: const Icon(Icons.search_rounded, size: 23),
            ),
            IconButton(
              tooltip: '新建影片',
              onPressed: _create,
              icon: const Icon(Icons.add_rounded, size: 25),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          top: false,
          child: VideoLayout(
            child: RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    sliver: SliverList.list(
                      children: [
                        const VideoPageHeading(
                          eyebrow: 'XIAOMEI  /  MOTION JOURNAL',
                          title: '让灵感，慢慢成片。',
                          subtitle: '写下一个画面，收藏一段属于你的日常。',
                        ),
                        const SizedBox(height: 22),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            onPressed: _create,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('开始创作'),
                                SizedBox(width: 24),
                                Icon(Icons.arrow_forward_rounded, size: 18),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Divider(height: 1, color: p.border),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const VideoEyebrow('THE COLLECTION'),
                                  const SizedBox(height: 7),
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 10,
                                    children: [
                                      Text(
                                        '我的作品',
                                        style: TextStyle(
                                          color: p.ink,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      if (_hasLoaded && !_loading)
                                        Text(
                                          '$_total 部',
                                          style: TextStyle(
                                            color: p.muted,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '网格视图',
                              onPressed: () => setState(() => _grid = true),
                              isSelected: _grid,
                              color: _grid
                                  ? p.ink
                                  : p.muted.withValues(alpha: .6),
                              icon: const Icon(
                                Icons.grid_view_outlined,
                                size: 20,
                              ),
                              selectedIcon: const Icon(
                                Icons.grid_view_rounded,
                                size: 20,
                              ),
                            ),
                            IconButton(
                              tooltip: '列表视图',
                              onPressed: () => setState(() => _grid = false),
                              isSelected: !_grid,
                              color: !_grid
                                  ? p.ink
                                  : p.muted.withValues(alpha: .6),
                              icon: const Icon(
                                Icons.view_agenda_outlined,
                                size: 20,
                              ),
                              selectedIcon: const Icon(
                                Icons.view_agenda_rounded,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (var i = 0; i < _filters.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(right: 22),
                                  child: InkWell(
                                    onTap: () {
                                      if (_filter == i) return;
                                      setState(() {
                                        _filter = i;
                                        _items = [];
                                        _hasLoaded = false;
                                      });
                                      _load();
                                    },
                                    child: Semantics(
                                      selected: _filter == i,
                                      button: true,
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          minHeight: 48,
                                        ),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: _filter == i
                                                  ? p.ink
                                                  : Colors.transparent,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          _filters[i],
                                          style: TextStyle(
                                            color: _filter == i
                                                ? p.ink
                                                : p.muted,
                                            fontSize: 13,
                                            fontWeight: _filter == i
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            ),
                          ),
                        if (_error != null && !_failedMore) ...[
                          VideoNotice(
                            _error!,
                            onRetry: () => _load(more: _failedMore),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (!_loading && _error == null && _items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.movie_creation_outlined,
                                  color: p.muted,
                                  size: 34,
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  _filter == 0 ? '故事，留一页给你。' : '这里还没有影片',
                                  style: TextStyle(
                                    fontFamily: 'StudioSerif',
                                    color: p.ink,
                                    fontSize: 22,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _filter == 0
                                      ? '从第一段灵感，开始你的映像集。'
                                      : '换个筛选，看看其他作品。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 12,
                                    height: 1.8,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: _create,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('创作一部影片'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final columns =
                            _grid &&
                                constraints.crossAxisExtent >= 330 &&
                                MediaQuery.textScalerOf(context).scale(14) < 20
                            ? 2
                            : 1;
                        final rows = (_items.length / columns).ceil();
                        return SliverList.separated(
                          itemCount: rows,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 24),
                          itemBuilder: (_, row) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var col = 0; col < columns; col++) ...[
                                if (col > 0) const SizedBox(width: 14),
                                Expanded(
                                  child: row * columns + col < _items.length
                                      ? _FilmCard(
                                          task: _items[row * columns + col],
                                          compact: columns > 1,
                                          onTap: () => _detail(
                                            _items[row * columns + col],
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          if (_error != null && _failedMore) ...[
                            VideoNotice(
                              _error!,
                              onRetry: () => _load(more: true),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_page < _totalPages && !_loading)
                            OutlinedButton.icon(
                              onPressed: _loadingMore
                                  ? null
                                  : () => _load(more: true),
                              icon: _loadingMore
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.expand_more_rounded,
                                      size: 18,
                                    ),
                              label: Text(_loadingMore ? '正在加载…' : '加载更多作品'),
                            ),
                          const SizedBox(height: 28),
                          Divider(height: 1, color: p.border),
                          const SizedBox(height: 20),
                          const VideoEyebrow(
                            'LITTLE MOMENTS, TIMELESS STORIES.',
                          ),
                        ],
                      ),
                    ),
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

class _FilmCard extends StatelessWidget {
  const _FilmCard({
    required this.task,
    required this.onTap,
    required this.compact,
  });
  final VideoTask task;
  final VoidCallback onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    return Semantics(
      button: true,
      label: '${task.displayTitle}，${task.label}，查看影片',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: VideoCover(
                  uri: task.coverUri,
                  aspectRatio: compact ? 4 / 5 : 16 / 9,
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.transparent,
                                Color(0x5c000000),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 12,
                        left: 12,
                        child: Text(
                          'NO. ${task.id.toString().padLeft(3, '0')}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      if (task.playableUri != null)
                        const Positioned(
                          top: 10,
                          right: 10,
                          child: Icon(
                            Icons.play_circle_outline_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: compact
                    ? MediaQuery.textScalerOf(context).scale(13) * 3.2
                    : null,
                child: Text(
                  task.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.ink,
                    fontSize: compact ? 13 : 17,
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                videoDate(task.createdAt),
                style: TextStyle(color: p.muted, fontSize: 10, height: 1.5),
              ),
              const SizedBox(height: 8),
              VideoStatusBadge(task),
            ],
          ),
        ),
      ),
    );
  }
}
