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
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text(
          '视频工作室',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '按编号查询',
            onPressed: _lookup,
            icon: const Icon(Icons.manage_search_rounded),
          ),
          IconButton(
            tooltip: '刷新作品',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
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
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: VideoEyebrow('XIAOMEI / MOTION STUDIO'),
                          ),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: VideoPalette.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '文字成片',
                            style: TextStyle(color: p.muted, fontSize: 10),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '把灵感，拍成日常。',
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 29,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '那些想象中的片刻，现在可以被看见。',
                        style: TextStyle(
                          color: p.muted,
                          fontSize: 13,
                          height: 1.7,
                        ),
                      ),
                      const SizedBox(height: 24),
                      VideoLandscape(
                        height: 250,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: VideoEyebrow(
                                      'MAKE SOMETHING BEAUTIFUL',
                                      color: Colors.white70,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.white38),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.movie_filter_outlined,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 26),
                              const Text(
                                '从一句话，\n到一段小电影。',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  height: 1.25,
                                  letterSpacing: -.8,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _create,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xfffff8f2),
                                  foregroundColor: const Color(0xff493448),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 19,
                                    vertical: 12,
                                  ),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 19),
                                label: const Text('开始创作'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '原创灵感插画 · 非生成效果预览',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: p.muted, fontSize: 9),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const VideoEyebrow('YOUR FILM COLLECTION'),
                                const SizedBox(height: 7),
                                Text(
                                  '我的作品',
                                  style: TextStyle(
                                    color: p.ink,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_hasLoaded && !_loading)
                            Text(
                              '$_total 部',
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < _filters.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(_filters[i]),
                                  selected: _filter == i,
                                  selectedColor: p.blush,
                                  showCheckmark: false,
                                  onSelected: (_) {
                                    if (_filter == i) return;
                                    setState(() {
                                      _filter = i;
                                      _items = [];
                                      _hasLoaded = false;
                                    });
                                    _load();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (_error != null) ...[
                        VideoNotice(
                          _error!,
                          onRetry: () => _load(more: _failedMore),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (!_loading && _error == null && _items.isEmpty)
                        VideoPanel(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: p.blush,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.movie_creation_outlined,
                                  color: VideoPalette.accent,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _filter == 0 ? '第一部作品，留给你的灵感。' : '这里还没有影片',
                                style: TextStyle(
                                  color: p.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _filter == 0
                                    ? '写下一个画面，让故事从这里开始。'
                                    : '换个筛选，或开始一段新的创作。',
                                style: TextStyle(color: p.muted, fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: _create,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('创作一部影片'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  sliver: SliverList.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (_, index) => _FilmCard(
                      task: _items[index],
                      onTap: () => _detail(_items[index]),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 36),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
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
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.expand_more_rounded),
                            label: Text(_loadingMore ? '正在加载…' : '加载更多作品'),
                          ),
                        const SizedBox(height: 14),
                        Text(
                          'MADE OF LITTLE MOMENTS',
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 9,
                            letterSpacing: 2.5,
                          ),
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
    );
  }
}

class _FilmCard extends StatelessWidget {
  const _FilmCard({required this.task, required this.onTap});
  final VideoTask task;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = VideoPalette(context);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 82,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: task.id.isEven
                        ? [const Color(0xffdfc3be), const Color(0xff8d728e)]
                        : [const Color(0xffc4c7d8), const Color(0xff747d99)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  task.playableUri != null
                      ? Icons.play_circle_outline_rounded
                      : Icons.movie_outlined,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '影片 #${task.id.toString().padLeft(4, '0')}',
                      style: TextStyle(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      videoDate(task.createdAt),
                      style: TextStyle(color: p.muted, fontSize: 10),
                    ),
                    const SizedBox(height: 8),
                    VideoStatusBadge(task),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: p.muted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
