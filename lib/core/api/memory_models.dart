class MemoryPage<T, C> {
  const MemoryPage({required this.items, this.nextCursor});

  final List<T> items;
  final C? nextCursor;
}

class MemoryRecord {
  const MemoryRecord({
    required this.id,
    required this.memory,
    required this.userId,
    required this.agentId,
    this.createdAt,
    this.updatedAt,
    this.metadata = const {},
  });

  factory MemoryRecord.fromJson(Map<String, dynamic> json) => MemoryRecord(
    id: json['id'] as String,
    memory: json['memory'] as String,
    userId: json['user_id'] as String,
    agentId: json['agent_id'] as String,
    createdAt: json['created_at'] as String?,
    updatedAt: json['updated_at'] as String?,
    metadata: Map.unmodifiable(json['metadata'] as Map<String, dynamic>? ?? {}),
  );

  final String id;
  final String memory;
  final String userId;
  final String agentId;
  final String? createdAt;
  final String? updatedAt;
  final Map<String, dynamic> metadata;
}

class MemoryHistoryEntry {
  const MemoryHistoryEntry({
    required this.id,
    required this.memoryId,
    required this.event,
    this.oldMemory,
    this.newMemory,
    this.createdAt,
    this.updatedAt,
  });

  factory MemoryHistoryEntry.fromJson(Map<String, dynamic> json) =>
      MemoryHistoryEntry(
        id: json['id'] as int,
        memoryId: json['memory_id'] as String,
        event: json['event'] as String,
        oldMemory: json['old_memory'] as String?,
        newMemory: json['new_memory'] as String?,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  final int id;
  final String memoryId;
  final String event;
  final String? oldMemory;
  final String? newMemory;
  final String? createdAt;
  final String? updatedAt;
}
