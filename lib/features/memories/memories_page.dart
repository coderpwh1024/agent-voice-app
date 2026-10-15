import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/memory_models.dart';
import '../../core/config/app_config.dart';
import '../conversations/chat_record_widgets.dart';
import 'memory_detail_page.dart';
import 'memory_feed.dart';
import 'memory_widgets.dart';

class MemoriesPage extends StatefulWidget {
  const MemoriesPage({super.key, required this.config, this.api});
  final AppConfig config;
  final AgentApiClient? api;

  @override
  State<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage> {
  late final AgentApiClient _api;
  late final MemoryFeed<MemoryRecord, String> _feed;
  bool _deleting = false;
  bool _needsReview = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AgentApiClient(widget.config);
    _feed = MemoryFeed(
      fetch: (cursor) => _api.memories(cursor: cursor),
      keyOf: (item) => item.id,
    );
    _feed.addListener(_changed);
    _feed.refresh();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _feed.removeListener(_changed);
    _feed.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _refresh({bool discardItems = false}) async {
    if (_deleting) return;
    final success = await _feed.refresh(discardItems: discardItems);
    if (mounted && success) {
      setState(() {
        _needsReview = false;
        _actionError = null;
      });
    }
  }

  Future<void> _open(MemoryRecord memory) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MemoryDetailPage(api: _api, memoryId: memory.id),
      ),
    );
    if (mounted && changed == true) await _refresh(discardItems: true);
  }

  Future<void> _deleteAll() async {
    if (_deleting || _feed.loading || _feed.loadingMore || _needsReview) return;
    if (!await confirmMemoryDeletion(context, all: true) || !mounted) return;
    setState(() {
      _deleting = true;
      _actionError = null;
    });
    try {
      final count = await _api.deleteMemories();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已清空 $count 条长期记忆')));
      await _feed.refresh(discardItems: true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _actionError = memoryErrorMessage(error, writing: true);
          _needsReview = memoryWriteUncertain(error);
        });
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    return PopScope(
      canPop: !_deleting,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          title: const Text('长期记忆'),
          backgroundColor: palette.background,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: '刷新记忆',
              onPressed: _deleting || _feed.loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: '记忆管理',
              enabled:
                  !_deleting &&
                  !_feed.loading &&
                  !_feed.loadingMore &&
                  !_needsReview &&
                  _feed.error == null &&
                  _feed.items.isNotEmpty,
              onSelected: (_) => _deleteAll(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'clear', child: Text('清空全部记忆')),
              ],
            ),
          ],
        ),
        body: RecordLayout(
          child: RefreshIndicator.adaptive(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  sliver: SliverList.list(
                    children: [
                      RecordHero(
                        eyebrow: 'A LITTLE MORE ABOUT YOU',
                        title: '被记住的小事。',
                        description: '你的偏好、习惯与重要的日常。\n查看和整理，让小美更懂现在的你。',
                        icon: Icons.psychology_outlined,
                        stats: [
                          if (!_feed.loading && _feed.error == null)
                            '已加载 ${_feed.items.length} 条',
                          'Mem0 · 小美',
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '长期记忆由聊天自动提炼。修改或删除记忆不会修改历史对话。',
                        style: TextStyle(fontSize: 13, height: 1.7),
                      ),
                      const SizedBox(height: 20),
                      if (_deleting) const MemoryLoading(),
                      if (_actionError != null) ...[
                        MemoryNotice(message: _actionError!, error: true),
                        const SizedBox(height: 16),
                      ],
                      if (_feed.loading) const MemoryLoading(),
                      if (!_feed.loading && _feed.error != null)
                        RecordStatus(
                          icon: Icons.cloud_off_outlined,
                          title: '记忆暂时无法打开',
                          description: memoryErrorMessage(_feed.error!),
                          onRetry: _refresh,
                        ),
                      if (!_feed.loading &&
                          _feed.error == null &&
                          _feed.items.isEmpty)
                        const RecordStatus(
                          icon: Icons.auto_awesome_outlined,
                          title: '故事，才刚刚开始',
                          description:
                              '目前还没有长期记忆。\n和 Mem0 · 小美聊聊你的日常，记忆会在这里慢慢积累。',
                        ),
                    ],
                  ),
                ),
                if (!_feed.loading)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.builder(
                      itemCount: _feed.items.length,
                      itemBuilder: (context, index) {
                        final memory = _feed.items[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: palette.surface,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                              side: BorderSide(color: palette.border),
                            ),
                            child: InkWell(
                              onTap: _deleting ? null : () => _open(memory),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.auto_awesome_outlined,
                                          color: palette.accent,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '关于你',
                                            style: TextStyle(
                                              color: palette.accent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 18,
                                          color: palette.muted,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      memory.memory,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.ink,
                                        fontSize: 16,
                                        height: 1.65,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      '更新于 ${memoryDateLabel(memory.updatedAt ?? memory.createdAt)}',
                                      style: TextStyle(
                                        color: palette.muted,
                                        fontSize: 11,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child:
                        !_feed.loading &&
                            _feed.error == null &&
                            _feed.items.isNotEmpty
                        ? MemoryPageFooter(
                            hasMore: _feed.nextCursor != null,
                            loading: _feed.loadingMore,
                            error: _feed.moreError,
                            onLoadMore: _deleting ? () {} : _feed.loadMore,
                          )
                        : const SizedBox(height: 24),
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
