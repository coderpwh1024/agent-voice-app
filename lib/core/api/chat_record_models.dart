import 'api_models.dart';

class ChatRecordDay {
  const ChatRecordDay({
    required this.recordDate,
    required this.latestAt,
    required this.conversationCount,
  });

  factory ChatRecordDay.fromJson(Map<String, dynamic> json) => ChatRecordDay(
    recordDate: json['record_date'] as String,
    latestAt: DateTime.parse(json['latest_at'] as String),
    conversationCount: (json['conversation_count'] as num).toInt(),
  );

  final String recordDate;
  final DateTime latestAt;
  final int conversationCount;

  DateTime get date => DateTime.parse('${recordDate}T00:00:00Z');
}

class DailyChatConversation {
  const DailyChatConversation({
    required this.threadId,
    required this.agentId,
    required this.updatedAt,
    required this.messages,
    this.title,
  });

  factory DailyChatConversation.fromJson(Map<String, dynamic> json) =>
      DailyChatConversation(
        threadId: json['thread_id'] as String,
        agentId: json['agent_id'] as String,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        title: json['title'] as String?,
        messages: (json['messages'] as List<dynamic>? ?? const [])
            .map((item) => ChatItem.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );

  final String threadId;
  final String agentId;
  final DateTime updatedAt;
  final String? title;
  final List<ChatItem> messages;

  String get displayTitle =>
      title?.trim().isNotEmpty == true ? title!.trim() : '未命名对话';

  ThreadSummary get thread => ThreadSummary(
    threadId: threadId,
    agentId: agentId,
    title: title,
    updatedAt: updatedAt,
  );
}

class ChatRecordDetail {
  const ChatRecordDetail({
    required this.recordDate,
    required this.conversations,
  });

  factory ChatRecordDetail.fromJson(Map<String, dynamic> json) =>
      ChatRecordDetail(
        recordDate: json['record_date'] as String,
        conversations: (json['conversations'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  DailyChatConversation.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
      );

  final String recordDate;
  final List<DailyChatConversation> conversations;

  int get messageCount => conversations.fold(
    0,
    (count, conversation) => count + conversation.messages.length,
  );
}
