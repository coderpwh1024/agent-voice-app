import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/config/app_config.dart';

Future<void> main() async {
  final input =
      jsonDecode(await utf8.decoder.bind(stdin).join()) as Map<String, dynamic>;
  final config = AppConfig(
    baseUrl: input['base_url'] as String,
    accessToken: input['access_token'] as String,
    userId: input['user_id'] as String,
  );
  final api = AgentApiClient(config);
  final otherUser = AgentApiClient(
    config.copyWith(userId: '${config.userId}-other'),
  );
  try {
    final records = await api.chatRecords('chatbot');
    if (records.length != 1 || records.single.conversationCount != 1) {
      throw StateError(
        'The isolated fixture should have one day and one conversation',
      );
    }
    final detail = await api.chatRecordDetail(
      'chatbot',
      records.single.recordDate,
    );
    if (detail.conversations.length != 1 || detail.messageCount != 2) {
      throw StateError('The isolated daily detail should contain two messages');
    }
    final conversation = detail.conversations.single;
    if (conversation.threadId != input['thread_id'] ||
        conversation.messages.first.role != 'human' ||
        conversation.messages.last.role != 'ai' ||
        conversation.messages.last.content != input['expected_reply']) {
      throw StateError('The live history did not match the fixture');
    }
    var isolated = false;
    try {
      await otherUser.chatRecords('chatbot');
    } on ApiException catch (error) {
      isolated = error.statusCode == 403;
    }
    if (!isolated) throw StateError('Cross-user history should be forbidden');
    stdout.writeln(
      jsonEncode({
        'list': 'passed',
        'detail': 'passed',
        'user_isolation': 'passed',
        'days': records.length,
        'conversations': detail.conversations.length,
        'messages': detail.messageCount,
      }),
    );
  } finally {
    api.close();
    otherUser.close();
  }
}
