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
    'clear-all candidates cannot erase memories recorded after extraction',
    () async {
      await store.save('已有偏好', 'profile');
      await store.enqueue(sourceId: newEventId(), text: '清空简短偏好');
      await store.process(
        (request) async => result(request, confirmation: true, action: 'clear'),
        version: 2,
      );
      final pendingId = store.pending.single['id'] as String;
      await store.recordImageSelection(sourceId: newEventId(), imageId: 12);

      await expectLater(store.review(pendingId, true), throwsStateError);
      expect(store.entries, hasLength(2));
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
    },
  );

  test(
    'previous server-mode files retain entries and resume local memory',
    () async {
      await store.save('简短回答', 'profile');
      final file = File('${directory.path}/MEMORY.md');
      final previous = (await file.readAsString()).replaceFirst(
        '"mode":"local"',
        '"mode":"mem0"',
      );
      await file.writeAsString(previous);
      final restored = LocalMemoryStore(directory: () async => directory);
      addTearDown(restored.dispose);
      await restored.load();
      expect(await file.readAsString(), previous);
      expect(restored.entries.single.text, '简短回答');
      await restored.enqueue(sourceId: newEventId(), text: '平时喜欢喝咖啡');
      expect(restored.queued, 1);
      expect(await file.readAsString(), contains('"mode":"local"'));
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

  test(
    'stable fact correction replaces the value after confirmation',
    () async {
      for (final text in ['简短', '详细']) {
        await store.enqueue(sourceId: newEventId(), text: text);
        await store.process((request) async {
          expect(request['version'], 2);
          return {
            ...result(request),
            'proposals': [
              {
                'action': 'add',
                'category': 'profile',
                'fact_key': 'response_style',
                'text': text,
                'evidence': text,
                'requires_confirmation': false,
              },
            ],
          };
        }, version: 2);
      }
      final previous = store.entries.single;
      expect(previous.text, '简短');
      expect(store.pending.single['target_id'], previous.id);
      await store.recordImageSelection(sourceId: newEventId(), imageId: 12);
      await store.review(store.pending.single['id'] as String, true);
      final updated = store.entries.singleWhere(
        (entry) => entry.category == 'profile',
      );
      expect(updated.id, previous.id);
      expect(updated.text, '详细');
    },
  );

  test(
    'episodes are chronological and procedures are opt-in and scoped',
    () async {
      final newer = newEventId();
      await store.recordImageSelection(
        sourceId: newer,
        imageId: 11,
        eventAt: '2026-11-25T10:00:00Z',
      );
      await store.recordImageSelection(sourceId: newer, imageId: 11);
      await store.recordImageSelection(
        sourceId: newEventId(),
        imageId: 10,
        eventAt: '2026-11-22T10:00:00Z',
      );
      final events =
          (await store.context('上次图片是哪张', version: 2))['memories'] as List;
      expect(events.map((event) => event['text']), [
        '已采用 11 号图片并结束该次编辑。',
        '已采用 10 号图片并结束该次编辑。',
      ]);
      expect(events.first['event_at'], startsWith('2026-11-25'));

      await store.save('', 'procedure');
      await store.save('', 'procedure');
      expect(
        store.entries.where((event) => event.procedureKey == imageReviewFirst),
        hasLength(1),
      );
      for (final query in [
        '生成一张小船图片',
        '画一张猫',
        '生成一张照片',
        '创建海报',
        'Generate a photo of a cat',
      ]) {
        final wire =
            (await store.context(query, version: 2))['memories'] as List;
        expect(
          wire.map((entry) => entry['procedure_key']),
          contains(imageReviewFirst),
          reason: query,
        );
      }
      final legacy = (await store.context('生成一张小船图片'))['memories'] as List;
      expect(legacy.any((event) => event['category'] == 'procedure'), isFalse);
      final unrelated =
          (await store.context('你好', version: 2))['memories'] as List;
      expect(unrelated, isEmpty);
    },
  );
}
