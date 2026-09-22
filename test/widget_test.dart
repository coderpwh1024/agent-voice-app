import 'package:agent_voice_app/app.dart';
import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/auth/auth_session_store.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

class EmptySessionStore extends AuthSessionStore {
  const EmptySessionStore();

  @override
  Future<StoredAuthSession?> read() async => null;
}

class AuthenticatedSessionStore extends AuthSessionStore {
  const AuthenticatedSessionStore();

  @override
  Future<StoredAuthSession?> read() async => const StoredAuthSession(
    config: AppConfig(
      baseUrl: 'http://127.0.0.1:1',
      accessToken: 'test-token',
      userId: '42',
    ),
    user: AuthUser(id: 42, nickname: 'tester', email: 'tester@example.com'),
  );
}

void main() {
  testWidgets('renders the email login and registration entry', (tester) async {
    await tester.pumpWidget(
      const AgentVoiceApp(sessionStore: EmptySessionStore()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Agent Voice'), findsOneWidget);
    expect(find.text('欢迎回来'), findsOneWidget);
    expect(find.text('获取登录验证码'), findsOneWidget);

    await tester.tap(find.text('注册'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('创建你的账号'), findsOneWidget);
    expect(find.text('获取验证码并注册'), findsOneWidget);
  });

  testWidgets('renders the authenticated voice home without layout errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const AgentVoiceApp(sessionStore: AuthenticatedSessionStore()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('开始语音'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('个人主页'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('个人主页'), findsOneWidget);
    expect(find.text('编辑个人资料'), findsOneWidget);
    expect(find.text('tester@example.com'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('编辑个人资料'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('保存更改'), findsOneWidget);
    expect(find.text('公开资料'), findsOneWidget);
    expect(find.text('更换头像'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
