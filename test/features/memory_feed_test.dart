import 'dart:async';

import 'package:agent_voice_app/core/api/memory_models.dart';
import 'package:agent_voice_app/features/memories/memory_feed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'refresh invalidates an in-flight next page and deduplicates results',
    () async {
      final pending = Completer<MemoryPage<String, int>>();
      var refreshCount = 0;
      final feed = MemoryFeed<String, int>(
        keyOf: (item) => item,
        fetch: (cursor) async {
          if (cursor != null) return pending.future;
          refreshCount++;
          return MemoryPage(
            items: [refreshCount == 1 ? 'old' : 'new'],
            nextCursor: 1,
          );
        },
      );
      addTearDown(feed.dispose);
      await feed.refresh();
      final more = feed.loadMore();
      await feed.refresh();
      pending.complete(const MemoryPage(items: ['stale'], nextCursor: 2));
      await more;
      expect(feed.items, ['new']);
      expect(feed.nextCursor, 1);
      expect(feed.loadingMore, isFalse);
    },
  );

  test(
    'next-page failures preserve items and cursor for an explicit retry',
    () async {
      var fail = true;
      final feed = MemoryFeed<String, int>(
        keyOf: (item) => item,
        fetch: (cursor) async {
          if (cursor == null) {
            return const MemoryPage(items: ['a'], nextCursor: 1);
          }
          if (fail) throw StateError('offline');
          return const MemoryPage(items: ['a', 'b']);
        },
      );
      addTearDown(feed.dispose);
      await feed.refresh();
      await feed.loadMore();
      expect(feed.items, ['a']);
      expect(feed.nextCursor, 1);
      expect(feed.moreError, isNotNull);
      fail = false;
      await feed.loadMore();
      expect(feed.items, ['a', 'b']);
      expect(feed.nextCursor, isNull);
      expect(feed.moreError, isNull);
    },
  );

  test('late completions after disposal are ignored', () async {
    final pending = Completer<MemoryPage<String, int>>();
    final feed = MemoryFeed<String, int>(
      keyOf: (item) => item,
      fetch: (_) => pending.future,
    );
    final refresh = feed.refresh();
    feed.dispose();
    pending.complete(const MemoryPage(items: ['late']));
    expect(await refresh, isFalse);
  });

  test('known deleted contents stay cleared when refresh fails', () async {
    var fail = false;
    final feed = MemoryFeed<String, int>(
      keyOf: (item) => item,
      fetch: (_) async {
        if (fail) throw StateError('offline');
        return const MemoryPage(items: ['deleted'], nextCursor: 1);
      },
    );
    addTearDown(feed.dispose);
    await feed.refresh();
    fail = true;
    await feed.refresh(discardItems: true);
    expect(feed.items, isEmpty);
    expect(feed.nextCursor, isNull);
    expect(feed.error, isNotNull);
  });
}
