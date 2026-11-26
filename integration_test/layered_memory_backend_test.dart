import 'dart:async';
import 'dart:io';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/api/voice_protocol.dart';
import 'package:agent_voice_app/core/api/voice_socket.dart';
import 'package:agent_voice_app/core/memory/local_memory_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/backend_auth.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('USB assistant reads each long-term memory layer', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final api = AgentApiClient(await backendTestConfig());
    addTearDown(api.close);
    final capabilities = await api.capabilities();
    expect(capabilities.localMemory, isTrue);
    expect(capabilities.localMemoryVersion, 2);

    final directory = await Directory.systemTemp.createTemp(
      'layered-memory-usb-',
    );
    addTearDown(() => directory.delete(recursive: true));
    var store = LocalMemoryStore(directory: () async => directory);
    addTearDown(store.dispose);
    final factWrite = Stopwatch()..start();
    await store.enqueue(sourceId: newEventId(), text: '请记住，以后请称呼我为青竹七号。');
    await store.process(api.extractLocalMemories, version: 2);
    if (store.pending.isNotEmpty) {
      await store.review(store.pending.single['id'] as String, true);
    }
    expect(store.entries.single.factKey, 'preferred_name');
    expect(store.entries.single.text, contains('青竹七号'));
    debugPrint(
      'LAYERED_MEMORY semantic_commit_ms=${factWrite.elapsedMilliseconds}',
    );
    await store.recordImageSelection(sourceId: newEventId(), imageId: 6137);
    final extraction = Stopwatch()..start();
    await store.enqueue(sourceId: newEventId(), text: '请记住，以后生成图片前先给我看方案。');
    await store.process(api.extractLocalMemories, version: 2);
    expect(store.pending.single['category'], 'procedure');
    await store.review(store.pending.single['id'] as String, true);
    debugPrint(
      'LAYERED_MEMORY procedure_commit_ms=${extraction.elapsedMilliseconds}',
    );
    store = LocalMemoryStore(directory: () async => directory);
    addTearDown(store.dispose);
    await store.load();

    final session = VoiceSession.fromJson(
      await api.requestJson(
        'POST',
        '/voice/sessions',
        body: {
          'agent_id': capabilities.defaultAgentId,
          'voice': capabilities.defaultVoice,
          'language': 'zh',
          'activation': 'tap',
          'turn_detection': 'manual',
          'input_mode': 'text',
          'memory_mode': 'local',
        },
      ),
    );
    addTearDown(() => api.closeVoiceSession(session.sessionId));
    final socket = await VoiceSocket.connect(
      api.websocketUri(session.sessionId),
      headers: api.websocketHeaders(),
    );
    addTearDown(socket.close);
    final ready = Completer<void>();
    var done = Completer<Map<String, dynamic>>();
    var output = StringBuffer();
    var imageSubmitted = false;
    final subscription = socket.messages
        .asyncMap((message) async {
          if (message is! VoiceSocketEventMessage) return;
          final event = message.event;
          switch (event['type']) {
            case 'session.ready':
              ready.complete();
            case 'memory.context.request':
              final context = await store.context(
                event['text'] as String,
                version: 2,
              );
              socket.sendJson(
                clientEvent('memory.context', {
                  'response_id': event['response_id'],
                  'context': context,
                }),
              );
            case 'text.delta':
              output.write(event['text']);
            case 'agent.custom':
              final data = event['data'];
              if (data is Map && data['type'] == 'image.task') {
                imageSubmitted = true;
              }
            case 'response.done':
              done.complete(event);
          }
        })
        .listen(
          null,
          onError: (Object error, StackTrace stack) {
            if (!ready.isCompleted) {
              ready.completeError(error, stack);
            } else if (!done.isCompleted) {
              done.completeError(error, stack);
            }
          },
        );
    addTearDown(subscription.cancel);
    socket.sendJson(
      clientEvent('session.configure', {
        'protocol_version': 1,
        'input_format': 'pcm16_16000_mono',
        'output_format': 'pcm16_24000_mono',
      }),
    );
    await ready.future.timeout(const Duration(seconds: 15));

    Future<String> ask(String name, String prompt) async {
      output = StringBuffer();
      done = Completer<Map<String, dynamic>>();
      final watch = Stopwatch()..start();
      socket.sendJson(clientEvent('input.text', {'text': prompt}));
      final event = await done.future.timeout(const Duration(seconds: 60));
      expect(event['execution_status'], 'completed');
      debugPrint(
        'LAYERED_MEMORY $name usb_total_ms=${watch.elapsedMilliseconds} server=${event['latency_ms']}',
      );
      return output.toString();
    }

    await store.configure(useMemory: false);
    expect(await ask('baseline', '请只回答收到。'), contains('收到'));
    await store.configure(useMemory: true);
    expect(await ask('semantic', '根据记忆，我希望你怎么称呼我？只回答称呼。'), contains('青竹七号'));
    expect(await ask('episodic', '回忆一下上次定稿采用的是几号图片，只报编号。'), contains('6137'));
    expect(await ask('procedural', '生成一张画着纸艺小船的图片。'), contains('画面方案'));
    expect(imageSubmitted, isFalse);
    debugPrint('LAYERED_MEMORY all_assertions_passed');
  });
}
