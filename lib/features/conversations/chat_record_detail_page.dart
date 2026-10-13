import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/api/chat_record_models.dart';
import 'chat_record_widgets.dart';

class ChatRecordDetailPage extends StatefulWidget {
  const ChatRecordDetailPage({
    super.key,
    required this.api,
    required this.agentId,
    required this.record,
  });

  final AgentApiClient api;
  final String agentId;
  final ChatRecordDay record;

  @override
  State<ChatRecordDetailPage> createState() => _ChatRecordDetailPageState();
}

class _ChatRecordDetailPageState extends State<ChatRecordDetailPage> {
  ChatRecordDetail? _detail;
  List<(DailyChatConversation, int)> _rows = const [];
  bool _loading = true;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.api.chatRecordDetail(
        widget.agentId,
        widget.record.recordDate,
      );
      if (!mounted || requestId != _requestId) return;
      final rows = <(DailyChatConversation, int)>[];
      for (final conversation in detail.conversations) {
        rows.add((conversation, -1));
        for (var index = 0; index < conversation.messages.length; index++) {
          rows.add((conversation, index));
        }
        rows.add((conversation, -2));
      }
      setState(() {
        _detail = detail;
        _rows = rows;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = recordErrorMessage(error));
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Widget _buildRow(BuildContext context, int index) {
    final palette = RecordPalette(context);
    final (conversation, messageIndex) = _rows[index];
    if (messageIndex == -1) {
      return _ConversationHeader(conversation: conversation);
    }
    if (messageIndex == -2) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (conversation.messages.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '这段对话当天还没有保存消息。',
                  style: TextStyle(color: palette.muted),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(conversation.thread),
              icon: const Icon(Icons.arrow_forward_rounded, size: 17),
              label: const Text('继续这段对话'),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.accent,
                side: BorderSide(color: palette.border),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return _MessageBubble(message: conversation.messages[messageIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    final date = widget.record.date;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('聊天详情'),
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '刷新聊天详情',
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
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                sliver: SliverList.list(
                  children: [
                    RecordHero(
                      eyebrow:
                          '${date.year} / ${date.month.toString().padLeft(2, '0')} / ${date.day.toString().padLeft(2, '0')}',
                      title: '${recordDateLabel(widget.record.recordDate)}的对话',
                      description:
                          '${recordWeekday(date)} · ${recordAgentName(widget.agentId)}\n只展示这一天新增的消息，按 UTC 日期归档。',
                      icon: Icons.forum_outlined,
                      stats: _loading || _error != null || _detail == null
                          ? const []
                          : [
                              '${_detail!.conversations.length} 段对话',
                              '${_detail!.messageCount} 条消息',
                            ],
                    ),
                    const SizedBox(height: 24),
                    if (_loading) const RecordLoading(),
                    if (!_loading && _error != null)
                      RecordStatus(
                        icon: Icons.cloud_off_rounded,
                        title: '暂时无法打开记录',
                        description: _error!,
                        onRetry: _load,
                      ),
                    if (!_loading && _error == null && _rows.isEmpty)
                      const RecordStatus(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: '这一天，还是空白',
                        description: '当天没有可展示的对话。\n返回列表，看看其他日期的记录。',
                      ),
                  ],
                ),
              ),
              if (!_loading && _error == null)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList.builder(
                    itemCount: _rows.length,
                    itemBuilder: _buildRow,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({required this.conversation});
  final DailyChatConversation conversation;

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    return Container(
      padding: const EdgeInsets.only(top: 6, bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: palette.lavender,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 20,
              color: palette.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conversation.displayTitle,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${recordAgentName(conversation.agentId)} · 最近 ${recordTime(conversation.updatedAt)} UTC',
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatItem message;

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    final human = message.role == 'human';
    final auxiliary = message.role == 'tool' || message.role == 'custom';
    final label = switch (message.role) {
      'human' => '你',
      'ai' => '助手',
      'tool' => '工具记录',
      _ => '会话记录',
    };
    final content = message.content.trim().isEmpty
        ? message.toolNames.isNotEmpty
              ? '调用工具：${message.toolNames.join('、')}'
              : '这条消息没有文本内容'
        : message.content;
    if (auxiliary) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: ValueKey(message),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(Icons.code_rounded, size: 18, color: palette.muted),
            title: Text(
              label,
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                content,
                style: TextStyle(color: palette.ink, fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: human ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.9),
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: human ? palette.blush : palette.surface,
            border: Border.all(
              color: human ? Colors.transparent : palette.border,
            ),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(human ? 20 : 5),
              bottomRight: Radius.circular(human ? 5 : 20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                content,
                style: TextStyle(color: palette.ink, fontSize: 15, height: 1.7),
              ),
              if (message.content.trim().isNotEmpty &&
                  message.toolNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '工具：${message.toolNames.join('、')}',
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
