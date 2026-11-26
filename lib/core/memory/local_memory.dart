import 'dart:convert';

const memoryCategories = [
  'profile',
  'person',
  'project',
  'episode',
  'procedure',
];
const memoryCategoryLabels = {
  'profile': '关于你',
  'person': '人物',
  'project': '项目',
  'episode': '事情',
  'procedure': '常用流程',
};
const imageReviewFirst = 'image_review_first';
const imageReviewFirstText = '生成图片前先给我看画面方案，明确要求直接生成时再提交。';
const _factKeys = {
  'preferred_name',
  'response_style',
  'home_city',
  'preference',
  'status',
  'decision',
};
const _memoryTopics = {'image', 'video', 'email', 'project', 'other'};
final memoryIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

class DeviceMemoryEntry {
  const DeviceMemoryEntry({
    required this.id,
    required this.text,
    required this.category,
    required this.updatedAt,
    this.sourceId,
    this.sourceText,
    this.threadId,
    this.sourceTime,
    this.factKey,
    this.subject,
    this.topic,
    this.eventAt,
    this.procedureKey,
    this.version = 1,
  });

  final String id, text, category, updatedAt;
  final String? sourceId, sourceText, threadId;
  final String? sourceTime;
  final String? factKey, subject, topic, eventAt, procedureKey;
  final int version;

  DateTime? get eventTime =>
      DateTime.tryParse(eventAt ?? sourceTime ?? updatedAt);

  (String, String, String)? get factIdentity => factKey == null
      ? null
      : (category, subject?.trim().toLowerCase() ?? '', factKey!);

  Map<String, Object?> get metadata => {
    'id': id,
    'category': category,
    'updated_at': updatedAt,
    'version': version,
    if (sourceId != null) 'source_id': sourceId,
    if (sourceText != null) 'source_text': sourceText,
    if (threadId != null) 'thread_id': threadId,
    if (sourceTime != null) 'source_time': sourceTime,
    if (factKey != null) 'fact_key': factKey,
    if (subject != null) 'subject': subject,
    if (topic != null) 'topic': topic,
    if (eventAt != null) 'event_at': eventAt,
    if (procedureKey != null) 'procedure_key': procedureKey,
  };

  Map<String, Object?> get reference => {
    'id': id,
    'category': category,
    'text': text,
    if (procedureKey != null) 'procedure_key': procedureKey,
  };

  factory DeviceMemoryEntry.fromMetadata(
    Map<String, dynamic> json,
    String text,
  ) {
    final id = json['id'] as String;
    final category = json['category'] as String;
    final factKey = json['fact_key'] as String?;
    final subject = (json['subject'] as String?)?.trim();
    final topic = json['topic'] as String?;
    final eventAt = json['event_at'] as String?;
    final procedureKey = json['procedure_key'] as String?;
    if (!memoryIdPattern.hasMatch(id) ||
        !memoryCategories.contains(category) ||
        (category == 'procedure'
            ? procedureKey != imageReviewFirst
            : procedureKey != null) ||
        (factKey != null &&
            (!_factKeys.contains(factKey) ||
                category == 'procedure' ||
                category == 'episode' ||
                (category != 'profile' &&
                    (subject == null || subject.isEmpty)))) ||
        (subject != null && (subject.isEmpty || subject.runes.length > 60)) ||
        (topic != null && !_memoryTopics.contains(topic)) ||
        (eventAt != null &&
            (category != 'episode' || DateTime.tryParse(eventAt) == null)) ||
        text.trim().isEmpty ||
        (json['version'] as int? ?? 1) < 1 ||
        text.runes.length > 1000 ||
        text.contains(RegExp(r'^## memory:', multiLine: true))) {
      throw const FormatException('记忆格式无效');
    }
    return DeviceMemoryEntry(
      id: id,
      text: text.trim(),
      category: category,
      updatedAt: json['updated_at'] as String,
      sourceId: json['source_id'] as String?,
      sourceText: json['source_text'] as String?,
      threadId: json['thread_id'] as String?,
      sourceTime: json['source_time'] as String?,
      factKey: factKey,
      subject: subject,
      topic: topic,
      eventAt: eventAt,
      procedureKey: procedureKey,
      version: json['version'] as int? ?? 1,
    );
  }
}

class DeviceMemoryDocument {
  DeviceMemoryDocument({
    this.revision = 0,
    this.epoch = 0,
    this.automatic = true,
    this.useMemory = true,
    List<DeviceMemoryEntry>? entries,
    List<Map<String, dynamic>>? jobs,
    List<Map<String, dynamic>>? pending,
    List<String>? completed,
  }) : entries = entries ?? [],
       jobs = jobs ?? [],
       pending = pending ?? [],
       completed = completed ?? [];

  int revision, epoch;
  bool automatic, useMemory;
  final List<DeviceMemoryEntry> entries;
  final List<Map<String, dynamic>> jobs, pending;
  final List<String> completed;

  String encode({bool backup = false}) {
    final header = {
      'format': 1,
      'revision': revision,
      'epoch': epoch,
      'automatic': automatic,
      'use_memory': useMemory,
      'mode': 'local',
      'entries': entries.map((entry) => entry.metadata).toList(),
      if (!backup) 'jobs': jobs,
      if (!backup) 'pending': pending,
      if (!backup) 'completed': completed,
    };
    final body = entries
        .map((entry) => '## memory:${entry.id}\n\n${entry.text}\n')
        .join('\n');
    return '---\n${jsonEncode(header)}\n---\n\n# 本机记忆\n\n$body';
  }

  factory DeviceMemoryDocument.decode(String markdown) {
    if (utf8.encode(markdown).length > 4 * 1024 * 1024) {
      throw const FormatException('记忆文件超过 4 MiB');
    }
    final normalized = markdown.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      throw const FormatException('缺少记忆文件头');
    }
    final end = normalized.indexOf('\n---\n', 4);
    if (end < 0) throw const FormatException('记忆文件头不完整');
    final header =
        jsonDecode(normalized.substring(4, end)) as Map<String, dynamic>;
    if (header['format'] != 1) {
      throw const FormatException('不支持的记忆文件版本');
    }
    final body = normalized.substring(end + 5);
    final markers = RegExp(
      r'^## memory:([0-9a-f-]+)\s*$',
      multiLine: true,
    ).allMatches(body).toList();
    final texts = <String, String>{};
    for (var index = 0; index < markers.length; index++) {
      final marker = markers[index];
      final id = marker.group(1)!;
      if (texts.containsKey(id)) throw const FormatException('记忆编号重复');
      texts[id] = body
          .substring(
            marker.end,
            index + 1 < markers.length ? markers[index + 1].start : body.length,
          )
          .trim();
    }
    final entries = (header['entries'] as List).map((item) {
      final metadata = Map<String, dynamic>.from(item as Map);
      final text = texts.remove(metadata['id']);
      if (text == null) throw const FormatException('记忆正文缺失');
      return DeviceMemoryEntry.fromMetadata(metadata, text);
    }).toList();
    if (texts.isNotEmpty || entries.length > 2000) {
      throw const FormatException('记忆目录与正文不一致或数量过多');
    }
    final revision = header['revision'] as int? ?? 0;
    final epoch = header['epoch'] as int? ?? 0;
    // Older files may contain the retired server mode.
    final mode = header['mode'] ?? 'local';
    if (revision < 0 || epoch < 0 || !['local', 'mem0'].contains(mode)) {
      throw const FormatException('记忆版本或模式无效');
    }
    return DeviceMemoryDocument(
      revision: revision,
      epoch: epoch,
      automatic: header['automatic'] as bool? ?? true,
      useMemory: header['use_memory'] as bool? ?? true,
      entries: entries,
      jobs: (header['jobs'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      pending: (header['pending'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      completed: (header['completed'] as List? ?? []).cast<String>().toList(),
    );
  }
}
