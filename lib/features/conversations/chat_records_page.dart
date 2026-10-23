import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/api/chat_record_models.dart';
import '../../core/config/app_config.dart';
import '../memories/memories_page.dart';
import 'chat_record_detail_page.dart';
import 'chat_record_widgets.dart';

class ChatRecordsPage extends StatefulWidget {
  const ChatRecordsPage({
    super.key,
    required this.config,
    required this.agents,
    required this.initialAgentId,
    this.api,
  });

  final AppConfig config;
  final List<AgentCapability> agents;
  final String initialAgentId;
  final AgentApiClient? api;

  @override
  State<ChatRecordsPage> createState() => _ChatRecordsPageState();
}

class _ChatRecordsPageState extends State<ChatRecordsPage> {
  late final AgentApiClient _api;
  late String _agentId;
  List<ChatRecordDay> _records = const [];
  bool _loading = true;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AgentApiClient(widget.config);
    _agentId = widget.initialAgentId;
    _load();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await _api.chatRecords(_agentId);
      if (!mounted || requestId != _requestId) return;
      setState(() => _records = records);
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = recordErrorMessage(error));
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  void _changeAgent(String? agentId) {
    if (agentId == null || agentId == _agentId) return;
    setState(() {
      _agentId = agentId;
      _records = const [];
    });
    _load();
  }

  Future<void> _openRecord(ChatRecordDay record) async {
    final thread = await Navigator.of(context).push<ThreadSummary>(
      MaterialPageRoute(
        builder: (_) =>
            ChatRecordDetailPage(api: _api, agentId: _agentId, record: record),
      ),
    );
    if (mounted && thread != null) Navigator.of(context).pop(thread);
  }

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    final agentIds = <String>{
      _agentId,
      ...widget.agents.map((agent) => agent.id),
    };
    final conversationCount = _records.fold(
      0,
      (count, day) => count + day.conversationCount,
    );
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('聊天记录'),
        actions: [
          IconButton(
            tooltip: '查看长期记忆',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => MemoriesPage(config: widget.config, api: _api),
              ),
            ),
            icon: const Icon(Icons.psychology_outlined),
          ),
          IconButton(
            tooltip: '刷新聊天记录',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RecordLayout(
        child: RefreshIndicator.adaptive(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                sliver: SliverList.list(
                  children: [
                    RecordHero(
                      eyebrow: 'THE CONVERSATION JOURNAL',
                      title: '把对话，留在这里。',
                      description: '灵感、日常和那些被认真倾听的时刻。\n回看最近 30 天，与你的助手聊过的每一天。',
                      icon: Icons.auto_stories_outlined,
                      stats: _loading || _error != null
                          ? const ['最近 30 天']
                          : [
                              '${_records.length} 个聊天日',
                              '$conversationCount 段对话',
                            ],
                    ),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '与你的助手',
                          style: TextStyle(
                            color: palette.ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey(_agentId),
                          initialValue: _agentId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            fillColor: palette.surface,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: palette.border),
                            ),
                          ),
                          items: agentIds
                              .map(
                                (id) => DropdownMenuItem(
                                  value: id,
                                  child: Text(
                                    recordAgentName(id),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _changeAgent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '最近的聊天',
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '按 UTC 日期归档',
                          style: TextStyle(color: palette.muted, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_loading) const RecordLoading(),
                    if (!_loading && _error != null)
                      RecordStatus(
                        icon: Icons.cloud_off_rounded,
                        title: '记录暂时没有到达',
                        description: _error!,
                        onRetry: _load,
                      ),
                    if (!_loading && _error == null && _records.isEmpty)
                      const RecordStatus(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: '故事，从下一句开始',
                        description: '这个助手最近 30 天还没有聊天记录。\n返回首页聊一聊，或切换助手看看。',
                      ),
                  ],
                ),
              ),
              if (!_loading && _error == null)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverList.builder(
                    itemCount: _records.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RecordDayCard(
                        record: _records[index],
                        onTap: () => _openRecord(_records[index]),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordDayCard extends StatelessWidget {
  const _RecordDayCard({required this.record, required this.onTap});
  final ChatRecordDay record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    return Material(
      color: palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: palette.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: palette.blush,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    Text(
                      '${record.date.month}月',
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      record.date.day.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${recordDateLabel(record.recordDate)} · ${recordWeekday(record.date)}',
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${record.conversationCount} 段对话 · 最近 ${recordTime(record.latestAt)}',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: palette.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
