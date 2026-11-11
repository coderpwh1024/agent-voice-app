import 'dart:async';
import 'dart:io';

import 'package:agent_voice_app/core/api/voice_protocol.dart';
import 'package:agent_voice_app/core/memory/local_memory.dart';
import 'package:agent_voice_app/core/memory/local_memory_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late LocalMemoryStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('device-memory-test-');
    store = LocalMemoryStore(directory: () async => directory);
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  Map<String, dynamic> result(
    Map<String, Object?> request, {
    bool confirmation = false,
    String action = 'add',
    String? target,
  }) => {
    'source_id': request['source_id'],
    'revision': (request['context'] as Map)['revision'],
    'epoch': (request['context'] as Map)['epoch'],
    'status': 'proposed',
    'proposals': [
      {
        'action': action,
        'category': 'profile',
        'text': action == 'delete' ? '' : '偏好简短回答',
        'evidence': '简短',
        'requires_confirmation': confirmation,
        'target_id': target,
      },
    ],
  };

  test(
    'Markdown body survives restart, manual body edit and Unicode budget',
    () async {
      await store.save('请叫我小林，回答简短。', 'profile');
      await store.save('旅行短片采用暖色。', 'project');
      final file = File('${directory.path}/MEMORY.md');
      final markdown = await file.readAsString();
      expect(markdown, contains('# 本机记忆'));
      expect(markdown, contains('旅行短片采用暖色。'));
      await file.writeAsString(markdown.replaceAll('旅行短片采用暖色。', '旅行短片采用冷色。'));
      final restored = LocalMemoryStore(directory: () async => directory);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.entries.last.text, '旅行短片采用冷色。');
      final unrelated = await restored.context('解释数据库');
      expect((unrelated['memories'] as List).length, 1);
      expect((unrelated['memories'] as List).first['category'], 'profile');
      final related = await restored.context('那个旅行短片');
      expect((related['memories'] as List).length, 2);
      for (var index = 0; index < 6; index++) {
        await restored.save('😀' * 900, 'profile');
      }
      final bounded = (await restored.context('你好'))['memories'] as List;
      expect(
        bounded.fold<int>(
          0,
          (sum, entry) => sum + (entry['text'] as String).runes.length,
        ),
        lessThanOrEqualTo(3000),
      );
    },
  );

  test(
    'persisted outbox retries after restart and deduplicates source replay',
    () async {
      final source = newEventId();
      await store.enqueue(sourceId: source, text: '请回答简短');
      await store.process((_) async => throw const SocketException('offline'));
      expect(store.queued, 1);
      final restored = LocalMemoryStore(directory: () async => directory);
      addTearDown(restored.dispose);
      var calls = 0;
      await restored.process((request) async {
        calls++;
        return result(request);
      });
      expect(restored.entries.single.text, '偏好简短回答');
      expect(restored.entries.single.sourceText, '简短');
      expect(DateTime.tryParse(restored.entries.single.sourceTime!), isNotNull);
      await restored.enqueue(sourceId: source, text: '请回答简短');
      await restored.process((request) async {
        calls++;
        return result(request);
      });
      expect(calls, 1);
      expect(restored.queued, 0);
    },
  );

  test(
    'mismatched extraction pauses retry without losing the durable job',
    () async {
      await store.enqueue(sourceId: newEventId(), text: '请回答简短');
      var calls = 0;
      await store.process((request) async {
        calls++;
        return {...result(request), 'source_id': newEventId()};
      });
      expect(calls, 1);
      expect(store.entries, isEmpty);
      expect(store.queued, 1);
      expect(store.error, isNotNull);
      await store.process((request) async => result(request));
      expect(store.entries.single.text, '偏好简短回答');
      expect(store.queued, 0);
    },
  );

  test(
    'forget cancels an in-flight result without resurrecting an entry',
    () async {
      await store.save('旧偏好', 'profile');
      await store.enqueue(sourceId: newEventId(), text: '请回答简短');
      final started = Completer<void>();
      final completed = Completer<Map<String, dynamic>>();
      final processing = store.process((request) {
        started.complete();
        return completed.future;
      });
      await started.future;
      await store.delete(store.entries.single);
      completed.complete({
        'source_id': 'stale',
        'revision': 0,
        'epoch': 0,
        'proposals': [],
      });
      await processing;
      expect(store.entries, isEmpty);
      expect(store.queued, 0);
      expect(
        DeviceMemoryDocument.decode(
          await File('${directory.path}/MEMORY.md').readAsString(),
        ).entries,
        isEmpty,
      );
    },
  );

  test(
    'edit conflicts and stale reviewed mutations cannot overwrite newer text',
    () async {
      await store.save('旧偏好', 'profile');
      final original = store.entries.single;
      await store.enqueue(sourceId: newEventId(), text: '改成简短');
      await store.process(
        (request) async =>
            result(request, action: 'update', target: original.id),
      );
      expect(store.entries.single.text, '旧偏好');
      expect(store.pending.single['action'], 'update');
      final pendingId = store.pending.single['id'] as String;
      await store.save('手动纠正', 'profile', previous: original);
      await expectLater(store.review(pendingId, true), throwsStateError);
      await expectLater(
        store.save('旧编辑器保存', 'profile', previous: original),
        throwsStateError,
      );
      expect(store.entries.single.text, '手动纠正');
    },
  );

  test(
    'confirmed mutation changes file, ignored candidate does not change facts',
    () async {
      await store.save('旧偏好', 'profile');
      await store.enqueue(sourceId: newEventId(), text: '请删除简短的偏好');
      await store.process(
        (request) async => result(
          request,
          confirmation: true,
          action: 'delete',
          target: store.entries.single.id,
        ),
      );
      expect(store.entries, hasLength(1));
      await store.review(store.pending.single['id'] as String, true);
      expect(store.entries, isEmpty);
      await store.enqueue(sourceId: newEventId(), text: '回答简短');
      await store.process(
        (request) async => result(request, confirmation: true),
      );
      await store.review(store.pending.single['id'] as String, false);
      expect(store.entries, isEmpty);
      expect(store.pending, isEmpty);
    },
  );

  test(
    'switches stop capture and suppress context; backup import is validated',
    () async {
      await store.save('简短回答', 'profile');
      final backup = await store.exportMarkdown();
      final epoch = (await store.context('你好'))['epoch'] as int;
      await store.configure(automatic: false, useMemory: false);
      await store.enqueue(sourceId: newEventId(), text: '不要再整理');
      expect(store.queued, 0);
      expect((await store.context('你好'))['memories'], isEmpty);
      expect((await store.context('你好'))['epoch'], greaterThan(epoch));
      await store.clear();
      await store.importMarkdown(backup);
      expect(store.entries.single.text, '简短回答');
      await expectLater(store.importMarkdown('损坏的文件'), throwsFormatException);
      expect(store.entries.single.text, '简短回答');
      await store.configure(mode: 'mem0');
      final restored = LocalMemoryStore(directory: () async => directory);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.mode, 'mem0');
    },
  );

  test(
    'corrupt existing file never silently becomes an empty writable vault',
    () async {
      final file = File('${directory.path}/MEMORY.md');
      await file.writeAsString('damaged');
      await expectLater(store.load(), throwsFormatException);
      await expectLater(store.save('新值', 'profile'), throwsFormatException);
      expect(await file.readAsString(), 'damaged');
    },
  );

  test(
    'private inputs stay out of outbox and cancelled sources cannot replay',
    () async {
      for (final text in ['这条不要记：我喜欢咖啡', '我的密码是 secret-test-only']) {
        await store.enqueue(sourceId: newEventId(), text: text);
      }
      expect(store.queued, 0);
      final source = newEventId();
      await store.enqueue(sourceId: source, text: '简短回答');
      await store.clear();
      await store.enqueue(sourceId: source, text: '简短回答');
      expect(store.queued, 0);
    },
  );
}
