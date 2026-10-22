import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/auth/auth_session_store.dart';
import 'package:agent_voice_app/core/config/app_config.dart';

Future<AppConfig> backendTestConfig() async {
  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  const bridge = String.fromEnvironment('VIDEO_TEST_AUTH_BRIDGE');
  if (bridge.isEmpty) {
    final session = await const AuthSessionStore().read();
    if (session == null) throw StateError('请先登录真机 App，或提供一次性本机测试身份桥');
    return session.config.copyWith(baseUrl: baseUrl);
  }
  final uri = Uri.parse(bridge);
  if (uri.host != '127.0.0.1' || uri.scheme != 'http') {
    throw StateError('测试身份桥必须使用本机 USB 回环地址');
  }
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode != 200) throw StateError('测试身份桥已失效');
    final data = jsonDecode(
      await utf8.decoder.bind(response).join(),
    ) as Map<String, dynamic>;
    return AppConfig(
      baseUrl: baseUrl,
      accessToken: data['access_token'] as String,
      userId: data['user_id'] as String,
    );
  } finally {
    client.close(force: true);
  }
}
