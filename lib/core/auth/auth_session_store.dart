import 'dart:convert';

import 'package:flutter/services.dart';

import '../api/api_models.dart';
import '../config/app_config.dart';

class StoredAuthSession {
  const StoredAuthSession({required this.config, required this.user});

  final AppConfig config;
  final AuthUser user;
}

class AuthSessionStore {
  const AuthSessionStore();

  static const _channel = MethodChannel('agent_voice/secure_session');

  Future<StoredAuthSession?> read() async {
    try {
      final value = await _channel.invokeMethod<String>('read');
      if (value == null || value.isEmpty) {
        return null;
      }
      final json = jsonDecode(value) as Map<String, dynamic>;
      final expiresAt = json['expires_at'] as int;
      if (expiresAt <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
        await clear();
        return null;
      }
      return StoredAuthSession(
        config: AppConfig(
          baseUrl: json['base_url'] as String,
          accessToken: json['access_token'] as String,
          userId: (json['user'] as Map<String, dynamic>)['id'].toString(),
        ),
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required AppConfig config,
    required EmailAuthResult result,
  }) async {
    await _channel.invokeMethod<void>(
      'write',
      jsonEncode(<String, Object?>{
        'base_url': config.baseUrl,
        'access_token': result.accessToken,
        'expires_at': result.expiresAt,
        'user': result.user.toJson(),
      }),
    );
  }

  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('delete');
    } on MissingPluginException {
      // Unit tests and unsupported desktop targets do not register the bridge.
    }
  }

  Future<void> updateBaseUrl(String baseUrl) async {
    final value = await _channel.invokeMethod<String>('read');
    if (value == null || value.isEmpty) {
      return;
    }
    final json = jsonDecode(value) as Map<String, dynamic>;
    json['base_url'] = baseUrl;
    await _channel.invokeMethod<void>('write', jsonEncode(json));
  }

  Future<void> updateUser(AuthUser user) async {
    final value = await _channel.invokeMethod<String>('read');
    if (value == null || value.isEmpty) {
      return;
    }
    final json = jsonDecode(value) as Map<String, dynamic>;
    json['user'] = user.toJson();
    await _channel.invokeMethod<void>('write', jsonEncode(json));
  }
}
