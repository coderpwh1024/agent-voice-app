import 'dart:io';

import 'package:agent_voice_app/core/content/message_content_view.dart';
import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';

import '../support/message_content_fixture.dart';
import 'voice_home_page_test.dart' show ChatPreviewController, mountChat;

import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';

class FixtureHttp extends HttpOverrides {}

class RecordingLauncher extends UrlLauncherPlatform {
  @override
  LinkDelegate? get linkDelegate => null;
  final opened = <String>[];
  bool succeeds = true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    expect(options.mode, PreferredLaunchMode.externalApplication);
    return succeeds;
  }
}

Future<void> mount(
  WidgetTester tester,
  String text, {
  bool streaming = false,
  bool dark = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: MessageContentView(
                text: text,
                baseUrl: 'http://127.0.0.1:8000',
                isStreaming: streaming,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late RecordingLauncher launcher;
  String clipboard = '';
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        });
    launcher = RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
  });
  testWidgets(
    'HTTP links launch externally, reject unsafe targets and offer copy if launch fails',
    (tester) async {
      await mount(
        tester,
        '参考 [资料](https://example.com/文档?a=x%2Fy) 和 https://example.com/manual.pdf。',
      );
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      markdown.onTapLink!('资料', 'https://example.com/文档?a=x%2Fy', '');
      await tester.pump();
      expect(launcher.opened.single, contains('example.com/'));
      markdown.onTapLink!('unsafe', 'javascript:alert(1)', '');
      await tester.pump();
      expect(launcher.opened.length, 1);
      launcher.succeeds = false;
      markdown.onTapLink!('file', 'https://example.com/file.pdf', '');
      await tester.pumpAndSettle();
      expect(find.text('暂时无法打开链接，可以复制后查看'), findsOneWidget);
      await tester.tap(find.text('复制链接'));
      await tester.pump();
      expect(
        (await Clipboard.getData('text/plain'))!.text,
        'https://example.com/file.pdf',
      );
    },
  );
  testWidgets(
    'streamed replies preserve text and defer image requests until done',
    (tester) async {
      await mount(
        tester,
        '看这个 😊 :smile:\nhttps://example.com/smile.gif?token=ab',
        streaming: true,
      );
      expect(find.byType(MessageImageTile), findsNothing);
      expect(find.text('回复完成后显示图片'), findsOneWidget);
      await mount(
        tester,
        '看这个 😊 :smile:\nhttps://example.com/smile.gif?token=abcd',
      );
      expect(find.byType(MessageImageTile), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byTooltip('复制图片链接'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'loads, enlarges and copies a real image, with a retryable failure',
    (tester) async {
      final overrides = FixtureHttp();
      await HttpOverrides.runWithHttpOverrides(() async {
        var requests = 0;
        var authorizationLeaked = false;
        final server = (await tester.runAsync(() async {
          final value = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          value.listen((r) async {
            requests++;
            authorizationLeaked |= r.headers.value('authorization') != null;
            if (r.uri.path == '/missing.png') {
              r.response.statusCode = 404;
            } else {
              r.response.add(messagePhoto());
            }
            await r.response.close();
          });
          return value;
        }))!;
        addTearDown(() => server.close(force: true));
        final url = 'http://127.0.0.1:${server.port}/photo.png';
        await tester.runAsync(() async {
          await mount(tester, '![山间日光]($url)');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsOneWidget);
        await tester.tap(find.byType(Image));
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(find.text('图片预览'), findsOneWidget);
        await tester.tap(find.text('复制链接'));
        await tester.pump();
        expect((await Clipboard.getData('text/plain'))!.text, url);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await mount(tester, 'http://127.0.0.1:${server.port}/missing.png');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(find.text('图片暂不可用，仍可打开链接查看'), findsOneWidget);
        final before = requests;
        await tester.runAsync(() async {
          await tester.tap(find.text('重新加载'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(requests, before + 1);
        expect(authorizationLeaked, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, overrides);
    },
  );
  for (final dark in [false, true]) {
    testWidgets('long URLs, lists and errors fit 320px at 200% dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(
        tester,
        '简单一点 😊\n\n- [使用说明](https://example.com/manual.pdf)\n- https://example.com/${'long-path-' * 35}\n\n![开心](https://example.com/missing.gif)',
        dark: dark,
        scale: 2,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('复制图片链接'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      final copy = tester.getSize(find.byTooltip('复制图片链接'));
      expect(copy.width, greaterThanOrEqualTo(48));
      expect(copy.height, greaterThanOrEqualTo(48));
    });
  }
  testWidgets(
    'voice messages use the same content view without disturbing scrolling',
    (tester) async {
      final voice = ChatPreviewController();
      voice.entries.add(
        const ConversationEntry(
          role: 'ai',
          text: '资料：https://example.com/read.pdf\n😊 :smile:',
        ),
      );
      await mountChat(tester, voice);
      expect(find.byType(MessageContentView), findsWidgets);
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      expect(scroll.position.extentAfter, lessThan(1));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      voice.append('另一份资料：https://example.com/next');
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(offset, 1));
    },
  );
}
