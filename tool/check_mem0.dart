import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/api/voice_protocol.dart';
import 'package:agent_voice_app/core/api/voice_socket.dart';
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
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  VoiceSocket? socket;
  StreamSubscription<VoiceSocketMessage>? subscription;
  String? sessionId;

  Future<Map<String, dynamic>> post(
    String agentId,
    String path,
    Map<String, Object?> body,
  ) async {
    final request = await http.postUrl(api.uri('/$agentId/$path'));
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${config.accessToken}',
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final decoded = jsonDecode(
      await utf8.decoder.bind(response).join(),
    ) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ApiException(
        response.statusCode,
        decoded['message']?.toString() ?? 'Live request failed',
      );
    }
    return decoded['data'] as Map<String, dynamic>;
  }

  void validateMemory(ChatItem message) {
    final enabled = input['memory_enabled'] == true;
    if (enabled &&
        message.memoryStatus != MemoryStatus.saved &&
        message.memoryStatus != MemoryStatus.savedSearchFailed) {
      throw StateError('The enabled memory write did not complete');
    }
    if (!enabled && message.memoryStatus != MemoryStatus.disabled) {
      throw StateError('The disabled memory status was not preserved');
    }
  }

  try {
    final capabilities = await api.capabilities();
    final selected = capabilities.selectAgent(null);
    if (selected?.id != 'mem0-chatbot' ||
        selected?.speechMode != 'streaming' ||
        selected?.cancelExecution != true) {
      throw StateError(
        'The deployed default does not advertise the Mem0 streaming agent',
      );
    }
    final agentId = selected!.id;
    final textThread = input['text_thread_id'] as String;
    final textResult = ChatItem.fromJson(
      await post(agentId, 'invoke', {
        'thread_id': textThread,
        'user_id': config.userId,
        'message': '客户端兼容性检查，请只回答“收到”。',
      }).timeout(const Duration(seconds: 90)),
    );
    if (textResult.content.trim().isEmpty) {
      throw StateError('Text response was empty');
    }
    validateMemory(textResult);
    final textHistory = await api.history(agentId, textThread);
    validateMemory(textHistory.lastWhere((item) => item.role == 'ai'));
    var protected = false;
    try {
      await api.history('chatbot', textThread);
    } on ApiException catch (error) {
      protected = error.statusCode == 403;
    }
    if (!protected) {
      throw StateError(
        'A Mem0 thread should not be accepted by the legacy agent',
      );
    }

    final session = await api.createVoiceSession(
      agentId: agentId,
      voice: capabilities.defaultVoice!,
      threadId: input['voice_thread_id'] as String,
    );
    sessionId = session.sessionId;
    if (session.agentId != agentId) {
      throw StateError('Voice session uses a different agent');
    }
    socket = await VoiceSocket.connect(
      api.websocketUri(sessionId),
      headers: api.websocketHeaders(),
    );
    final ready = Completer<void>();
    final done = Completer<Map<String, dynamic>>();
    var audioFrames = 0;
    var textLength = 0;
    subscription = socket.messages.listen((message) {
      if (message is VoiceSocketAudioMessage) {
        final frame = decodeOutputAudioFrame(message.bytes);
        if (frame.pcm.isNotEmpty) audioFrames++;
      } else if (message is VoiceSocketEventMessage) {
        final event = message.event;
        if (event['type'] == 'session.ready' && !ready.isCompleted) {
          ready.complete();
        }
        if (event['type'] == 'text.delta') {
          textLength += (event['text'] as String? ?? '').length;
        }
        if (event['type'] == 'response.done' && !done.isCompleted) {
          done.complete(event);
        }
        if (event['type'] == 'error') {
          final error = StateError('Voice server error: ${event['code']}');
          if (!ready.isCompleted) ready.completeError(error);
          if (!done.isCompleted) done.completeError(error);
        }
      }
    });
    socket.sendJson(
      clientEvent('session.configure', {
        'protocol_version': voiceProtocolVersion,
        'input_format': 'pcm16_16000_mono',
        'output_format': 'pcm16_24000_mono',
      }),
    );
    await ready.future.timeout(const Duration(seconds: 15));
    socket.sendJson(clientEvent('input.text', {'text': '语音接口兼容性检查，请只回答“你好”。'}));
    final completion = await done.future.timeout(const Duration(seconds: 120));
    if (completion['execution_status'] != 'completed' ||
        completion['audio_status'] != 'completed' ||
        audioFrames == 0 ||
        textLength == 0) {
      throw StateError('The voice response or PCM audio did not complete');
    }
    socket.sendJson(clientEvent('session.close'));
    await socket.close();
    socket = null;
    final voiceHistory = await api.history(agentId, session.threadId);
    validateMemory(voiceHistory.lastWhere((item) => item.role == 'ai'));
    final threads = await api.threads(agentId);
    if (!threads.any((item) => item.threadId == textThread) ||
        !threads.any((item) => item.threadId == session.threadId)) {
      throw StateError('Text or voice thread missing from history');
    }
    final records = await api.chatRecords(agentId);
    final detail = await api.chatRecordDetail(
      agentId,
      records.first.recordDate,
    );
    if (detail.conversations.length != 2) {
      throw StateError(
        'Daily records should contain both live test conversations',
      );
    }
    for (final conversation in detail.conversations) {
      validateMemory(
        conversation.messages.lastWhere((item) => item.role == 'ai'),
      );
    }
    stdout.writeln(
      jsonEncode({
        'capabilities': 'passed',
        'default_agent': agentId,
        'text_invoke': 'passed',
        'voice_websocket': 'passed',
        'pcm_audio_frames': audioFrames,
        'threads': 'passed',
        'daily_records': 'passed',
        'agent_isolation': 'passed',
        'memory_status': textResult.memoryStatus?.name,
      }),
    );
  } finally {
    await subscription?.cancel();
    await socket?.close();
    if (sessionId != null) await api.closeVoiceSession(sessionId);
    api.close();
    http.close(force: true);
  }
}
