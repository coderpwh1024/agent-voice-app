import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:agent_voice_app/features/auth/auth_page.dart';
import 'package:agent_voice_app/features/profile/edit_profile_page.dart';
import 'package:agent_voice_app/features/settings/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const config = AppConfig(
  baseUrl: 'http://127.0.0.1:8000',
  accessToken: 'test',
  userId: '42',
);
const user = AuthUser(
  id: 42,
  nickname: '小雨',
  email: 'a.long.account.name@example.com',
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'account forms remain usable at 320px with 200% text: $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Future<void> mount(Widget page) async {
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: AppTheme.build(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: page,
            ),
          );
          await tester.pumpAndSettle();
        }

        await mount(
          AuthPage(baseUrl: config.baseUrl, onAuthenticated: (_, _) async {}),
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('sendCodeButton')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const ValueKey('sendCodeButton')));
        await tester.pumpAndSettle();
        expect(find.text('请输入有效的邮箱地址'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await mount(const EditProfilePage(config: config, user: user));
        await tester.scrollUntilVisible(
          find.text('保存更改'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('保存更改'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await mount(
          Scaffold(
            body: SettingsSheet(
              config: config,
              user: user,
              onLogout: () async {},
            ),
          ),
        );
        await tester.scrollUntilVisible(
          find.text('保存'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('保存'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
