class EmailCodeAccepted {
  const EmailCodeAccepted({required this.expiresInSeconds});

  factory EmailCodeAccepted.fromJson(Map<String, dynamic> json) =>
      EmailCodeAccepted(
        expiresInSeconds: json['expires_in_seconds'] as int? ?? 180,
      );

  final int expiresInSeconds;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.nickname,
    required this.email,
    this.imageUrl,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: (json['id'] as num).toInt(),
    nickname: json['nickname'] as String? ?? '',
    email: json['email'] as String? ?? '',
    imageUrl: json['image_url'] as String?,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'nickname': nickname,
    'email': email,
    'image_url': imageUrl,
  };

  final int id;
  final String nickname;
  final String email;
  final String? imageUrl;
}

class EmailAuthResult {
  const EmailAuthResult({
    required this.accessToken,
    required this.tokenType,
    required this.expiresAt,
    required this.isNewUser,
    required this.user,
  });

  factory EmailAuthResult.fromJson(Map<String, dynamic> json) =>
      EmailAuthResult(
        accessToken: json['access_token'] as String,
        tokenType: json['token_type'] as String? ?? 'bearer',
        expiresAt: json['expires_at'] as int,
        isNewUser: json['is_new_user'] as bool? ?? false,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );

  final String accessToken;
  final String tokenType;
  final int expiresAt;
  final bool isNewUser;
  final AuthUser user;
}

class AgentCapability {
  const AgentCapability({
    required this.id,
    required this.description,
    required this.speechMode,
    required this.cancelExecution,
  });

  factory AgentCapability.fromJson(Map<String, dynamic> json) =>
      AgentCapability(
        id: json['id'] as String,
        description: json['description'] as String? ?? '',
        speechMode: json['speech_mode'] as String? ?? 'final_message',
        cancelExecution: json['cancel_execution'] as bool? ?? false,
      );

  final String id;
  final String description;
  final String speechMode;
  final bool cancelExecution;
}

class VoiceOption {
  const VoiceOption({
    required this.id,
    required this.name,
    this.description = '',
  });

  factory VoiceOption.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    return VoiceOption(
      id: id,
      name: name.isEmpty ? id : name,
      description: json['description']?.toString().trim() ?? '',
    );
  }

  factory VoiceOption.legacy(String id) => VoiceOption(id: id, name: id);

  final String id;
  final String name;
  final String description;

  String get displayName => name == id ? id : '$name · $id';
}

class VoiceCapabilities {
  const VoiceCapabilities({
    required this.enabled,
    required this.protocolVersion,
    required this.voiceOptions,
    required this.defaultVoice,
    required this.agents,
    required this.wakeWord,
    required this.clientVad,
    required this.audioMetricsSeconds,
  });

  factory VoiceCapabilities.fromJson(Map<String, dynamic> json) {
    final legacyVoiceIds = (json['voices'] as List<dynamic>? ?? const [])
        .map((item) => item.toString().trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final metadataById = <String, VoiceOption>{};
    for (final item in json['voice_options'] as List<dynamic>? ?? const []) {
      if (item is! Map) {
        continue;
      }
      final option = VoiceOption.fromJson(Map<String, dynamic>.from(item));
      if (option.id.isNotEmpty) {
        metadataById.putIfAbsent(option.id, () => option);
      }
    }
    final voiceIds = legacyVoiceIds.isNotEmpty
        ? legacyVoiceIds
        : metadataById.keys.toList(growable: false);
    final seenVoiceIds = <String>{};
    final voiceOptions = voiceIds
        .where(seenVoiceIds.add)
        .map((id) => metadataById[id] ?? VoiceOption.legacy(id))
        .toList(growable: false);
    final configuredDefault = json['default_voice']?.toString().trim();
    final defaultVoice =
        voiceOptions.any((option) => option.id == configuredDefault)
        ? configuredDefault
        : voiceOptions.firstOrNull?.id;

    return VoiceCapabilities(
      enabled: json['enabled'] as bool? ?? false,
      protocolVersion: json['protocol_version'] as int? ?? 0,
      voiceOptions: voiceOptions,
      defaultVoice: defaultVoice,
      agents: (json['agents'] as List<dynamic>? ?? const [])
          .map((item) => AgentCapability.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      wakeWord: WakeWordCapability.fromJson(
        Map<String, dynamic>.from(json['wake_word'] as Map? ?? const {}),
      ),
      clientVad: ClientVadCapability.fromJson(
        Map<String, dynamic>.from(json['client_vad'] as Map? ?? const {}),
      ),
      audioMetricsSeconds: json['audio_metrics_seconds'] as int? ?? 5,
    );
  }

  final bool enabled;
  final int protocolVersion;
  final List<VoiceOption> voiceOptions;
  final String? defaultVoice;
  final List<AgentCapability> agents;
  final WakeWordCapability wakeWord;
  final ClientVadCapability clientVad;
  final int audioMetricsSeconds;

  List<String> get voices =>
      voiceOptions.map((option) => option.id).toList(growable: false);

  VoiceOption? voiceOption(String? id) =>
      voiceOptions.where((option) => option.id == id).firstOrNull;
}

class WakeWordCapability {
  const WakeWordCapability({
    required this.enabled,
    required this.keyword,
    required this.confirmWithAsr,
    required this.preRollMs,
    required this.score,
    required this.threshold,
  });

  factory WakeWordCapability.fromJson(Map<String, dynamic> json) =>
      WakeWordCapability(
        enabled: json['enabled'] as bool? ?? false,
        keyword: json['keyword']?.toString() ?? '小美',
        confirmWithAsr: json['confirm_with_asr'] as bool? ?? true,
        preRollMs: json['pre_roll_ms'] as int? ?? 1200,
        score: (json['kws_score'] as num?)?.toDouble() ?? 1,
        threshold: (json['kws_threshold'] as num?)?.toDouble() ?? 0.5,
      );

  final bool enabled;
  final String keyword;
  final bool confirmWithAsr;
  final int preRollMs;
  final double score;
  final double threshold;
}

class ClientVadCapability {
  const ClientVadCapability({
    required this.enabled,
    required this.rmsDbfs,
    required this.speechFrames,
  });

  factory ClientVadCapability.fromJson(Map<String, dynamic> json) =>
      ClientVadCapability(
        enabled: json['enabled'] as bool? ?? true,
        rmsDbfs: (json['rms_dbfs'] as num?)?.toDouble() ?? -42,
        speechFrames: json['speech_frames'] as int? ?? 3,
      );

  final bool enabled;
  final double rmsDbfs;
  final int speechFrames;
}

class VoiceSession {
  const VoiceSession({
    required this.sessionId,
    required this.threadId,
    required this.agentId,
    required this.voice,
    required this.expiresAt,
    this.activation = 'tap',
    this.wakeStatus = 'not_required',
  });

  factory VoiceSession.fromJson(Map<String, dynamic> json) => VoiceSession(
    sessionId: json['session_id'] as String,
    threadId: json['thread_id'] as String,
    agentId: json['agent_id'] as String,
    voice: json['voice'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
    activation: json['activation'] as String? ?? 'tap',
    wakeStatus: json['wake_status'] as String? ?? 'not_required',
  );

  final String sessionId;
  final String threadId;
  final String agentId;
  final String voice;
  final DateTime expiresAt;
  final String activation;
  final String wakeStatus;
}

class ChatItem {
  const ChatItem({required this.role, required this.content, this.runId});

  factory ChatItem.fromJson(Map<String, dynamic> json) => ChatItem(
    role: json['type'] as String? ?? 'custom',
    content: json['content'] as String? ?? '',
    runId: json['run_id'] as String?,
  );

  final String role;
  final String content;
  final String? runId;
}

class ThreadSummary {
  const ThreadSummary({
    required this.threadId,
    required this.agentId,
    required this.title,
    required this.updatedAt,
  });

  factory ThreadSummary.fromJson(Map<String, dynamic> json) => ThreadSummary(
    threadId: json['thread_id'] as String,
    agentId: json['agent_id'] as String,
    title: json['title'] as String?,
    updatedAt: json['updated_at'] == null
        ? null
        : DateTime.tryParse(json['updated_at'] as String),
  );

  final String threadId;
  final String agentId;
  final String? title;
  final DateTime? updatedAt;
}
