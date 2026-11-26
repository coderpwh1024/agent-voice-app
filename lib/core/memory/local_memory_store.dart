import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/voice_protocol.dart';
import '../config/app_config.dart';
import 'local_memory.dart';

typedef MemoryExtractor = Future<Map<String, dynamic>> Function(
  Map<String, Object?> body,
);

class LocalMemoryStore extends ChangeNotifier {
  LocalMemoryStore({required this.directory});

  static const _channel = MethodChannel('agent_voice/local_memory');
  static final _accounts = <String, LocalMemoryStore>{};
  static final _historyQuery = RegExp(
    r'上次|上回|之前|最近|当时|那次|last time|previous|recent',
    caseSensitive: false,
  );
  static final _imageCreate = RegExp(
    r'生成|画|做|创建|制作|创作|绘制|create|generate|draw',
    caseSensitive: false,
  );
  static final _topics = {
    'image': RegExp(
      r'图片|图像|照片|配图|海报|插画|壁纸|封面|张图|幅图|号图|画[一个张幅]|绘制|出图|定稿|\b(?:images?|photos?)\b',
      caseSensitive: false,
    ),
    'video': RegExp(r'视频|短片|影片|电影'),
    'email': RegExp(r'邮件|电邮|投递|发信'),
    'project': RegExp(r'项目|会议|决定|方案|讨论'),
  };

  static LocalMemoryStore forConfig(AppConfig config) {
    if (config.userId.trim().isEmpty) throw StateError('请先登录');
    final uri = Uri.parse(config.baseUrl)
        .replace(userInfo: '', query: '', fragment: '');
    final scope = base64Url
        .encode(
          utf8.encode(
            '${uri.toString().replaceAll(RegExp(r'/+$'), '')}\n${config.userId}',
          ),
        )
        .replaceAll('=', '');
    return _accounts.putIfAbsent(
      scope,
      () => LocalMemoryStore(
        directory: () async {
          final root = await _channel.invokeMethod<String>('directory');
          if (root == null || root.isEmpty) throw StateError('本机记忆目录不可用');
          return Directory('$root/$scope');
        },
      ),
    );
  }

  final Future<Directory> Function() directory;
  DeviceMemoryDocument _document = DeviceMemoryDocument();
  Future<void> _tail = Future.value();
  bool _loaded = false, _processing = false;
  String? error;

  List<DeviceMemoryEntry> get entries => List.unmodifiable(_document.entries);
  List<Map<String, dynamic>> get pending =>
      List.unmodifiable(_document.pending);
  int get queued => _document.jobs.length;
  bool get automatic => _document.automatic;
  bool get useMemory => _document.useMemory;
  int get revision => _document.revision;
  bool get isLoaded => _loaded;

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _load() async {
    if (_loaded) return;
    final file = File('${(await directory()).path}/MEMORY.md');
    if (await file.exists()) {
      _document = DeviceMemoryDocument.decode(await file.readAsString());
    }
    _loaded = true;
  }

  Future<void> load() => _serial(() async {
    await _load();
    notifyListeners();
  });

  Future<void> _persist() async {
    final folder = await directory();
    await folder.create(recursive: true);
    final markdown = _document.encode();
    DeviceMemoryDocument.decode(markdown);
    final temporary = File('${folder.path}/MEMORY.md.next');
    await temporary.writeAsString(markdown, flush: true);
    await temporary.rename('${folder.path}/MEMORY.md');
    error = null;
    notifyListeners();
  }

  Future<void> _change(void Function() change) async {
    final previous = _document.encode();
    try {
      change();
      _document.revision++;
      await _persist();
    } catch (_) {
      _document = DeviceMemoryDocument.decode(previous);
      rethrow;
    }
  }

  Future<Map<String, Object?>> context(
    String query, {
    int version = 1,
  }) => _serial(() async {
    final watch = Stopwatch()..start();
    await _load();
    if (!_document.useMemory) return _context(const [], version);
    final historical = _historyQuery.hasMatch(query);
    final tokens = _tokens(query.replaceAll(_historyQuery, ' '));
    final topics = _topics.entries
        .where((item) => item.value.hasMatch(query))
        .map((item) => item.key)
        .toSet();
    final normalizedQuery = query.toLowerCase();
    final ranked = <(DeviceMemoryEntry, int)>[];
    for (final entry in _document.entries) {
      if (entry.category == 'profile' || entry.category == 'procedure') {
        continue;
      }
      final text = entry.text.toLowerCase();
      final lexical = tokens.where(text.contains).length;
      final subject = entry.subject;
      final subjectHit =
          subject != null && normalizedQuery.contains(subject.toLowerCase());
      final topicHit = historical && topics.contains(entry.topic);
      if (lexical > 0 || subjectHit || topicHit) {
        ranked.add((
          entry,
          (subjectHit ? 100 : 0) + (topicHit ? 12 : 0) + lexical,
        ));
      }
    }
    ranked.sort((a, b) {
      if (historical &&
          (a.$1.category == 'episode') != (b.$1.category == 'episode')) {
        return a.$1.category == 'episode' ? -1 : 1;
      }
      final relevance = b.$2.compareTo(a.$2);
      if (relevance != 0) return relevance;
      final aTime = a.$1.eventTime;
      final bTime = b.$1.eventTime;
      if (a.$1.category == 'episode' &&
          b.$1.category == 'episode' &&
          aTime != null &&
          bTime != null) {
        return bTime.compareTo(aTime);
      }
      return b.$1.updatedAt.compareTo(a.$1.updatedAt);
    });
    final selected = <DeviceMemoryEntry>[];
    var remaining = 3000;
    var profileBudget = 1500;
    final profiles =
        _document.entries.where((entry) => entry.category == 'profile').toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final entry in profiles) {
      final length = entry.text.runes.length;
      if (length > profileBudget || selected.length == 4) continue;
      selected.add(entry);
      profileBudget -= length;
      remaining -= length;
    }
    if (version >= 2 &&
        topics.contains('image') &&
        _imageCreate.hasMatch(query)) {
      final procedure = _document.entries
          .where((entry) => entry.procedureKey == imageReviewFirst)
          .firstOrNull;
      if (procedure != null && procedure.text.runes.length <= remaining) {
        selected.add(procedure);
        remaining -= procedure.text.runes.length;
      }
    }
    for (final (entry, _) in ranked) {
      if (entry.text.runes.length > remaining) continue;
      selected.add(entry);
      remaining -= entry.text.runes.length;
      if (selected.length == 8) break;
    }
    debugPrint(
      '[LocalMemory] recall semantic=${selected.where((e) => e.category != 'episode' && e.category != 'procedure').length} '
      'episodic=${selected.where((e) => e.category == 'episode').length} '
      'procedural=${selected.where((e) => e.category == 'procedure').length} '
      'duration_ms=${watch.elapsedMicroseconds / 1000}',
    );
    return _context(selected, version);
  });

  Map<String, Object?> _context(
    List<DeviceMemoryEntry> selected,
    int version,
  ) => {
    'revision': _document.revision,
    'epoch': _document.epoch,
    'total_count': _document.useMemory
        ? _document.entries
              .where((entry) => version >= 2 || entry.category != 'procedure')
              .length
        : 0,
    'memories': [
      for (final entry in selected)
        {
          ...entry.reference,
          if (version >= 2 &&
              entry.category == 'episode' &&
              entry.eventAt != null)
            'event_at': entry.eventAt,
        },
    ],
  };

  Set<String> _tokens(String text) {
    final tokens = RegExp(r'[a-z0-9_]+|[\u4e00-\u9fff]+')
        .allMatches(text.toLowerCase())
        .map((match) => match.group(0)!)
        .toList();
    return {
      ...tokens,
      for (final token in tokens.where(
        (token) => RegExp(r'[\u4e00-\u9fff]').hasMatch(token),
      ))
        for (var index = 0; index + 1 < token.length; index++)
          token.substring(index, index + 2),
    };
  }

  Future<void> configure({bool? automatic, bool? useMemory}) =>
      _serial(() async {
        await _load();
        await _change(() {
          if (automatic != null) _document.automatic = automatic;
          if (useMemory != null && useMemory != _document.useMemory) {
            _invalidate();
            _document.useMemory = useMemory;
          }
          if (automatic == false) {
            _invalidate();
          }
        });
      });

  Future<void> save(
    String text,
    String category, {
    DeviceMemoryEntry? previous,
  }) => _serial(() async {
    await _load();
    if (previous != null) _assertCurrent(previous.id, previous.version);
    final sameCategory = previous?.category == category ? previous : null;
    final existing = category == 'procedure'
        ? _document.entries
              .where((entry) => entry.procedureKey == imageReviewFirst)
              .firstOrNull
        : null;
    if (existing != null && existing.id != previous?.id) return;
    final entry = DeviceMemoryEntry.fromMetadata({
      'id': previous?.id ?? newEventId(),
      'category': category,
      if (sameCategory != null) ...sameCategory.metadata,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'version': (previous?.version ?? 0) + 1,
      if (category == 'procedure') 'procedure_key': imageReviewFirst,
    }, category == 'procedure' ? imageReviewFirstText : text);
    await _change(() {
      _invalidate();
      _document.entries.removeWhere((item) => item.id == entry.id);
      _document.entries.add(entry);
    });
  });

  void _assertCurrent(String id, int version) {
    if (!_document.entries.any(
      (entry) => entry.id == id && entry.version == version,
    )) {
      throw StateError('记忆已发生变化，请刷新后重新确认');
    }
  }

  void _invalidate() {
    _document.epoch++;
    for (final job in _document.jobs) {
      final source = job['source_id'] as String;
      if (!_document.completed.contains(source)) {
        _document.completed.add(source);
      }
    }
    _document.pending.clear();
    _document.jobs.clear();
  }

  Future<void> delete(DeviceMemoryEntry entry) => _serial(() async {
    await _load();
    _assertCurrent(entry.id, entry.version);
    await _change(() {
      _invalidate();
      _document.entries.removeWhere((item) => item.id == entry.id);
    });
  });

  Future<void> clear() => _serial(() async {
    await _load();
    await _change(() {
      _invalidate();
      _document.entries.clear();
    });
  });

  Future<void> enqueue({
    required String sourceId,
    required String text,
    String? threadId,
  }) => _serial(() async {
    await _load();
    if (!_document.automatic ||
        text.trim().isEmpty ||
        text.runes.length > 6000) {
      return;
    }
    if (RegExp(
      r"(?:这句|这条|这段|本轮|这次|这些).{0,8}(?:别记|不要记|不保存)|临时(?:聊|使用)|don't remember|do not remember|Bearer\s+\S+|sk-[a-zA-Z0-9_-]{12,}|(?:密码|验证码|密钥|令牌|password|api[_ -]?key)\s*[:：=是为]\s*\S+",
      caseSensitive: false,
    ).hasMatch(text)) {
      return;
    }
    if (_document.completed.contains(sourceId) ||
        _document.jobs.any((job) => job['source_id'] == sourceId)) {
      return;
    }
    if (!memoryIdPattern.hasMatch(sourceId)) {
      throw const FormatException('来源编号无效');
    }
    if (_document.jobs.length >= 100) throw StateError('待整理记忆过多，请先处理或关闭自动整理');
    await _change(
      () => _document.jobs.add({
        'source_id': sourceId,
        'text': text,
        'thread_id': threadId,
        'epoch': _document.epoch,
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      }),
    );
  });

  Future<void> recordImageSelection({
    required String sourceId,
    required int imageId,
    String? threadId,
    String? eventAt,
  }) => _serial(() async {
    await _load();
    if (!_document.automatic ||
        !memoryIdPattern.hasMatch(sourceId) ||
        imageId <= 0 ||
        _document.entries.any((entry) => entry.sourceId == sourceId) ||
        _document.completed.contains(sourceId)) {
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final entry = DeviceMemoryEntry.fromMetadata({
      'id': newEventId(),
      'category': 'episode',
      'topic': 'image',
      'source_id': sourceId,
      'thread_id': ?threadId,
      'source_time': now,
      'event_at':
          DateTime.tryParse(eventAt ?? '')?.toUtc().toIso8601String() ?? now,
      'updated_at': now,
    }, '已采用 $imageId 号图片并结束该次编辑。');
    await _change(() {
      _document.entries.add(entry);
      _document.completed.add(sourceId);
    });
    debugPrint(
      '[LocalMemory] recorded verified image selection revision=${_document.revision}',
    );
  });

  Future<void> process(MemoryExtractor extract, {int version = 1}) async {
    if (_processing) return;
    _processing = true;
    try {
      while (true) {
        final job = await _serial(() async {
          await _load();
          if (!_document.automatic || _document.jobs.isEmpty) {
            return null;
          }
          return Map<String, dynamic>.from(_document.jobs.first);
        });
        if (job == null) return;
        final references = await context(
          job['text'] as String,
          version: version,
        );
        final result = await extract({
          'source_id': job['source_id'],
          'text': job['text'],
          if (job['occurred_at'] != null) 'occurred_at': job['occurred_at'],
          if (job['utc_offset_minutes'] != null)
            'utc_offset_minutes': job['utc_offset_minutes'],
          'context': references,
          if (version >= 2) 'version': 2,
        });
        await _serial(() async {
          final id = job['source_id'];
          if (!_document.jobs.any((item) => item['source_id'] == id) ||
              _document.epoch != job['epoch']) {
            return;
          }
          if (result['epoch'] != job['epoch'] ||
              result['source_id'] != id ||
              result['revision'] != references['revision']) {
            throw const FormatException('记忆整理结果与来源版本不匹配');
          }
          final proposals = (result['proposals'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          await _change(() {
            for (final proposal in proposals) {
              final evidence = proposal['evidence'] as String;
              if (!(job['text'] as String).contains(evidence)) {
                throw const FormatException('记忆候选缺少来源证据');
              }
              final pending = <String, dynamic>{
                ...proposal,
                'id': newEventId(),
                'source_id': id,
                'source_text': evidence,
                'thread_id': job['thread_id'],
                'source_time': job['occurred_at'],
                'epoch': _document.epoch,
                'base_revision': _document.revision,
              };
              final factKey = proposal['fact_key'];
              final procedureKey = proposal['procedure_key'];
              if (procedureKey != null &&
                  _document.entries.any(
                    (entry) => entry.procedureKey == procedureKey,
                  )) {
                continue;
              }
              if (factKey is String && proposal['action'] == 'add') {
                final subject =
                    (proposal['subject'] as String?)?.trim().toLowerCase() ??
                    '';
                final previous = _document.entries
                    .where(
                      (entry) =>
                          entry.factIdentity ==
                          (proposal['category'], subject, factKey),
                    )
                    .firstOrNull;
                if (previous != null) {
                  if (previous.text == proposal['text']) continue;
                  pending['action'] = 'update';
                  pending['target_id'] = previous.id;
                  pending['requires_confirmation'] = true;
                }
              }
              final target = _document.entries
                  .where((entry) => entry.id == pending['target_id'])
                  .firstOrNull;
              pending['target_version'] = target?.version;
              if (pending['action'] == 'add' &&
                  procedureKey == null &&
                  proposal['requires_confirmation'] == false) {
                _apply(pending);
              } else {
                _document.pending.add(pending);
              }
            }
            _document.jobs.removeWhere((item) => item['source_id'] == id);
            _document.completed.add(id as String);
          });
          debugPrint(
            '[LocalMemory] extraction_applied proposals=${proposals.length} revision=${_document.revision}',
          );
        });
      }
    } catch (failure) {
      error = failure is ApiException
          ? failure.message
          : '本机记忆整理未完成，请在记忆页重试或核对文件';
      notifyListeners();
    } finally {
      _processing = false;
    }
  }

  void _apply(Map<String, dynamic> proposal) {
    final action = proposal['action'];
    final target = proposal['target_id'];
    if (action == 'clear') {
      _document.entries.clear();
      return;
    }
    if (action == 'delete') {
      if (!_document.entries.any((entry) => entry.id == target)) {
        throw StateError('目标记忆已不存在');
      }
      _document.entries.removeWhere((entry) => entry.id == target);
      return;
    }
    if (!['add', 'update'].contains(action)) {
      throw const FormatException('无效的记忆操作');
    }
    final text = (proposal['text'] as String).trim();
    if (_document.entries.any(
      (entry) =>
          entry.text == text &&
          entry.category == proposal['category'] &&
          entry.subject == proposal['subject'] &&
          (entry.category != 'episode' ||
              (entry.eventAt ?? entry.sourceTime) ==
                  (proposal['event_at'] ?? proposal['source_time'])),
    )) {
      return;
    }
    final previous = _document.entries
        .where((entry) => entry.id == target)
        .firstOrNull;
    if (action == 'update' && previous == null) throw StateError('目标记忆已不存在');
    final entry = DeviceMemoryEntry.fromMetadata({
      'id': previous?.id ?? proposal['id'],
      'category': proposal['category'],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'version': (previous?.version ?? 0) + 1,
      'source_id': proposal['source_id'],
      'source_text': proposal['source_text'],
      'thread_id': proposal['thread_id'],
      'source_time': proposal['source_time'],
      'fact_key': proposal['fact_key'] ?? previous?.factKey,
      'subject': proposal['subject'] ?? previous?.subject,
      'topic': proposal['topic'] ?? previous?.topic,
      'event_at': proposal['event_at'] ?? previous?.eventAt,
      'procedure_key': proposal['procedure_key'] ?? previous?.procedureKey,
    }, text);
    if (entry.factIdentity != null &&
        _document.entries.any(
          (item) =>
              item.id != entry.id && item.factIdentity == entry.factIdentity,
        )) {
      throw StateError('同一事实已保存，请在记忆详情里更新');
    }
    _document.entries.removeWhere((item) => item.id == entry.id);
    _document.entries.add(entry);
  }

  Future<void> review(String id, bool approved) => _serial(() async {
    await _load();
    final proposal = _document.pending
        .where((item) => item['id'] == id)
        .firstOrNull;
    if (proposal == null) throw StateError('候选已处理，请刷新后查看');
    if (approved) {
      final target = _document.entries
          .where((entry) => entry.id == proposal['target_id'])
          .firstOrNull;
      final requiresCurrentRevision =
          proposal['action'] == 'clear' ||
          !proposal.containsKey('target_version');
      final stale = requiresCurrentRevision
          ? proposal['base_revision'] != _document.revision - 1
          : proposal['target_id'] != null &&
                (target == null ||
                    target.version != proposal['target_version']);
      if (proposal['epoch'] != _document.epoch || stale) {
        throw StateError('候选生成后记忆已变化，请重新整理或手动修改');
      }
    }
    await _change(() {
      if (approved) _apply(proposal);
      if (approved && proposal['action'] != 'add') {
        _invalidate();
      } else {
        _document.pending.removeWhere((item) => item['id'] == id);
      }
    });
    debugPrint(
      '[LocalMemory] proposal_reviewed approved=$approved revision=${_document.revision}',
    );
  });

  Future<String> exportMarkdown() => _serial(() async {
    await _load();
    return _document.encode(backup: true);
  });

  Future<void> importMarkdown(String markdown) => _serial(() async {
    await _load();
    final imported = DeviceMemoryDocument.decode(markdown);
    await _change(() {
      _invalidate();
      _document.entries
        ..clear()
        ..addAll(imported.entries);
    });
  });
}
