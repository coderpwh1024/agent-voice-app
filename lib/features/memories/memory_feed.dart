import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../core/api/memory_models.dart';

class MemoryFeed<T, C> extends ChangeNotifier {
  MemoryFeed({required this.fetch, required this.keyOf});

  final Future<MemoryPage<T, C>> Function(C? cursor) fetch;
  final Object Function(T item) keyOf;
  List<T> _items = [];
  C? nextCursor;
  bool loading = false;
  bool loadingMore = false;
  Object? error;
  Object? moreError;
  int _generation = 0;
  bool _disposed = false;

  List<T> get items => UnmodifiableListView(_items);

  Future<bool> refresh({bool discardItems = false}) async {
    final generation = ++_generation;
    loading = true;
    loadingMore = false;
    error = null;
    moreError = null;
    if (discardItems) {
      _items = [];
      nextCursor = null;
    }
    notifyListeners();
    try {
      final page = await fetch(null);
      if (_disposed || generation != _generation) return false;
      _items = List.of(page.items);
      nextCursor = page.nextCursor;
      return true;
    } catch (failure) {
      if (!_disposed && generation == _generation) error = failure;
      return false;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = nextCursor;
    if (_disposed ||
        loading ||
        loadingMore ||
        cursor == null ||
        error != null) {
      return;
    }
    final generation = _generation;
    loadingMore = true;
    moreError = null;
    notifyListeners();
    try {
      final page = await fetch(cursor);
      if (_disposed || generation != _generation) return;
      if (page.nextCursor == cursor) {
        throw const FormatException('Memory cursor did not advance');
      }
      final merged = {for (final item in _items) keyOf(item): item};
      for (final item in page.items) {
        merged[keyOf(item)] = item;
      }
      _items = merged.values.toList();
      nextCursor = page.nextCursor;
    } catch (failure) {
      if (!_disposed && generation == _generation) moreError = failure;
    } finally {
      if (!_disposed && generation == _generation) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
