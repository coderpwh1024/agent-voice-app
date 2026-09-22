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

class VoiceCapabilities {
  const VoiceCapabilities({
    required this.enabled,
    required this.protocolVersion,
    required this.voices,
    required this.agents,
  });

  factory VoiceCapabilities.fromJson(Map<String, dynamic> json) =>
      VoiceCapabilities(
        enabled: json['enabled'] as bool? ?? false,
        protocolVersion: json['protocol_version'] as int? ?? 0,
        voices: (json['voices'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
        agents: (json['agents'] as List<dynamic>? ?? const [])
            .map(
              (item) => AgentCapability.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
      );

  final bool enabled;
  final int protocolVersion;
  final List<String> voices;
  final List<AgentCapability> agents;
}

class VoiceSession {
  const VoiceSession({
    required this.sessionId,
    required this.threadId,
    required this.agentId,
    required this.voice,
    required this.expiresAt,
  });

  factory VoiceSession.fromJson(Map<String, dynamic> json) => VoiceSession(
    sessionId: json['session_id'] as String,
    threadId: json['thread_id'] as String,
    agentId: json['agent_id'] as String,
    voice: json['voice'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
  );

  final String sessionId;
  final String threadId;
  final String agentId;
  final String voice;
  final DateTime expiresAt;
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
