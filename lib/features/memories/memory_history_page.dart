import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/memory_models.dart';
import '../conversations/chat_record_widgets.dart';
import 'memory_feed.dart';
import 'memory_widgets.dart';

class MemoryHistoryPage extends StatefulWidget {
  const MemoryHistoryPage({
    super.key,
    required this.api,
    required this.memoryId,
  });
  final AgentApiClient api;
  final String memoryId;

  @override
  State<MemoryHistoryPage> createState() => _MemoryHistoryPageState();
}

class _MemoryHistoryPageState extends State<MemoryHistoryPage> {
  late final MemoryFeed<MemoryHistoryEntry, int> _feed;

  @override
  void initState() {
    super.initState();
    _feed = MemoryFeed(
      fetch: (cursor) =>
          widget.api.memoryHistory(widget.memoryId, cursor: cursor),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('变更历史'),
        backgroundColor: palette.background,
        actions: [
          IconButton(
            tooltip: '刷新变更历史',
            onPressed: _feed.loading ? null : _feed.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RecordLayout(
        child: RefreshIndicator.adaptive(
          onRefresh: () async {
            await _feed.refresh();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                sliver: SliverList.list(
                  children: [
                    const RecordHero(
                      eyebrow: 'THE MEMORY TIMELINE',
                      title: '记忆，一点点生长。',
                      description: '从首次记住，到每一次更新与删除。\n按变更顺序查看，时间显示为手机本地时间。',
                      icon: Icons.timeline_rounded,
                    ),
                    const SizedBox(height: 24),
                    if (_feed.loading) const MemoryLoading(),
                    if (!_feed.loading && _feed.error != null)
                      RecordStatus(
                        icon: Icons.cloud_off_outlined,
                        title: '历史暂时无法打开',
                        description: memoryErrorMessage(_feed.error!),
                        onRetry: _feed.refresh,
                      ),
                    if (!_feed.loading &&
                        _feed.error == null &&
                        _feed.items.isEmpty)
                      const RecordStatus(
                        icon: Icons.history_rounded,
                        title: '还没有变更记录',
                        description: '这条记忆的变更历史暂时为空。',
                      ),
                  ],
                ),
              ),
              if (!_feed.loading)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverList.builder(
                    itemCount: _feed.items.length,
                    itemBuilder: (_, index) =>
                        _HistoryCard(entry: _feed.items[index]),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child:
                      !_feed.loading &&
                          _feed.error == null &&
                          _feed.items.isNotEmpty
                      ? MemoryPageFooter(
                          hasMore: _feed.nextCursor != null,
                          loading: _feed.loadingMore,
                          error: _feed.moreError,
                          onLoadMore: _feed.loadMore,
                        )
                      : const SizedBox(height: 24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});
  final MemoryHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    final (label, icon) = switch (entry.event) {
      'ADD' => ('首次记住', Icons.bookmark_add_outlined),
      'UPDATE' => ('更新记忆', Icons.edit_outlined),
      'DELETE' => ('删除记忆', Icons.delete_outline_rounded),
      _ => ('记忆变更', Icons.history_rounded),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: entry.event == 'DELETE'
                      ? palette.blush
                      : palette.lavender,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 18, color: palette.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      memoryDateLabel(entry.updatedAt ?? entry.createdAt),
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (entry.oldMemory != null) ...[
            const SizedBox(height: 18),
            Text('变更前', style: TextStyle(color: palette.muted, fontSize: 12)),
            const SizedBox(height: 7),
            SelectableText(
              entry.oldMemory!,
              style: TextStyle(color: palette.muted, height: 1.7),
            ),
          ],
          if (entry.newMemory != null) ...[
            const SizedBox(height: 18),
            Text(
              entry.event == 'ADD' ? '记住的内容' : '变更后',
              style: TextStyle(
                color: palette.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            SelectableText(
              entry.newMemory!,
              style: TextStyle(color: palette.ink, height: 1.7),
            ),
          ],
        ],
      ),
    );
  }
}
