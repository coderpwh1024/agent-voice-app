import 'dart:io';
import 'dart:ui' as ui;

import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/voice_session/voice_home_page.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const previewDirectory = String.fromEnvironment('CHAT_PREVIEW_DIR');
const previewKey = ValueKey('chat-preview');

class ChatPreviewController extends VoiceSessionController {
  ChatPreviewController()
    : super(
        config: const AppConfig(
          baseUrl: 'http://127.0.0.1:8000',
          accessToken: 'test-token',
          userId: '42',
        ),
      );

  @override
  VoiceCapabilities get capabilities => VoiceCapabilities.fromJson({
    'enabled': true,
    'protocol_version': 1,
    'voices': ['Cherry', 'Serena'],
    'agents': [
      {'id': 'chatbot', 'speech_mode': 'streaming', 'cancel_execution': true},
    ],
  });

  bool connected = false;
  String? responseId;
  VoiceConnectionState? previewState;

  @override
  bool get isConnected => connected;

  @override
  String? get currentResponseId => responseId;

  @override
  VoiceConnectionState get state => connected
      ? previewState ?? VoiceConnectionState.listening
      : VoiceConnectionState.disconnected;

  final entries = List.generate(
    60,
    (index) => ConversationEntry(
      role: index.isEven ? 'human' : 'assistant',
      text: index.isEven
          ? '第 $index 条消息：想把今天的小事分享给你。'
          : '第 $index 条回复：慢慢说，我在听。生活里的小小发现，也值得被认真记住。',
    ),
  );

  @override
  List<ConversationEntry> get messages => List.unmodifiable(entries);

  void redraw() => notifyListeners();

  void append(String text) {
    entries.add(ConversationEntry(role: 'assistant', text: text));
    notifyListeners();
  }

  void stream(String text) {
    entries[entries.length - 1] = entries.last.copyWith(text: text);
    notifyListeners();
  }
}

Future<void> mountChat(
  WidgetTester tester,
  ChatPreviewController controller, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorSchemeSeed: const Color(0xffd87568),
        brightness: brightness,
        fontFamily: previewDirectory.isEmpty ? null : 'ChatPreview',
        appBarTheme: AppBarTheme(
          backgroundColor: brightness == Brightness.dark
              ? const Color(0xff171412)
              : const Color(0xfffbf8f4),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          filled: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(key: previewKey, child: child!),
      ),
      home: VoiceHomePage(
        controller: controller,
        user: const AuthUser(id: 42, nickname: '小雨', email: ''),
        onOpenProfile: (_) async {},
        onOpenSettings: (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('agent_voice/audio'),
          (_) async => null,
        );
  });
  if (previewDirectory.isNotEmpty) {
    setUpAll(() async {
      final loader = FontLoader('ChatPreview')
        ..addFont(
          File(const String.fromEnvironment('CHAT_PREVIEW_FONT'))
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(const String.fromEnvironment('CHAT_PREVIEW_ICON_FONT'))
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      await icons.load();
    });
    for (final brightness in Brightness.values) {
      testWidgets('render conversation preview in $brightness', (tester) async {
        final controller = ChatPreviewController();
        controller.entries.replaceRange(0, controller.entries.length, [
          const ConversationEntry(role: 'human', text: '今天下班时，看到了一片很好看的晚霞。'),
          const ConversationEntry(
            role: 'assistant',
            text: '像是忙碌一天后，生活悄悄送来的礼物。\n\n是温柔的粉色，还是像橘子汽水一样的颜色？',
          ),
          const ConversationEntry(role: 'human', text: '是粉紫色的，还想周末去海边走走。'),
          const ConversationEntry(
            role: 'assistant',
            text: '听起来很棒。吹吹海风，看看日落，给自己一点慢下来的时间。\n\n要不要一起想想，周末可以怎么安排？',
          ),
          const ConversationEntry(role: 'human', text: '好呀，想要轻松一点的安排。'),
          const ConversationEntry(
            role: 'assistant',
            text: '那就睡到自然醒，带上喜欢的歌，下午出发。沿着海岸慢慢走，找一家小店喝杯咖啡，再等一场日落。',
          ),
        ]);
        await mountChat(tester, controller, brightness: brightness);
        Future<void> capture(String name) async {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(previewKey),
            );
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(previewDirectory).create(recursive: true);
            await File('$previewDirectory/$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('chat-${brightness.name}');
        await tester.tap(find.byTooltip('对话偏好'));
        await tester.pumpAndSettle();
        await capture('preferences-${brightness.name}');
        await tester.tap(find.byTooltip('关闭对话偏好'));
        await tester.pumpAndSettle();
        controller.entries.clear();
        controller.redraw();
        await tester.pumpAndSettle();
        await capture('welcome-${brightness.name}');
      });
    }
  }
  testWidgets(
    'status updates and incoming replies preserve a reader position',
    (tester) async {
      final controller = ChatPreviewController();
      await mountChat(tester, controller);
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 450));
      await tester.pumpAndSettle();
      final readingOffset = scroll.offset;
      controller.redraw();
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(readingOffset, 1));
      controller.append('刚收到的新回复');
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(readingOffset, 1));
      expect(find.text('1 条新消息'), findsOneWidget);
      controller.stream('刚收到的新回复，还在继续生成。' * 15);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(readingOffset, 1));
      await tester.tap(find.text('1 条新消息'));
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(1));
      expect(find.text('1 条新消息'), findsNothing);
    },
  );

  testWidgets(
    'follows streamed replies at the bottom and offers a one tap return to the start',
    (tester) async {
      final controller = ChatPreviewController();
      await mountChat(tester, controller);
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      expect(scroll.position.extentAfter, lessThan(1));
      controller.append('从这一刻开始，' * 25);
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(1));
      controller.stream('从这一刻开始，我们慢慢聊。' * 50);
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(1));
      await tester.tap(find.text('回到顶部'));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(find.text('最新消息'), findsOneWidget);
      expect(find.byTooltip('对话偏好').hitTestable(), findsOneWidget);
      expect(find.text('现在开始说话').hitTestable(), findsOneWidget);
      controller.redraw();
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      await tester.tap(find.byTooltip('对话偏好'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭对话偏好'));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
    },
  );

  testWidgets('composer exposes actions only when they can be used', (
    tester,
  ) async {
    final controller = ChatPreviewController()..connected = true;
    await mountChat(tester, controller);
    expect(find.byTooltip('我要插话'), findsNothing);
    final sendButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '发送文字',
    );
    expect(tester.widget<IconButton>(sendButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '  今天很好  ');
    await tester.pump();
    expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(tester.widget<IconButton>(sendButton).onPressed, isNull);

    controller.responseId = 'reply-1';
    controller.previewState = VoiceConnectionState.thinking;
    controller.redraw();
    await tester.pump();
    expect(find.byTooltip('我要插话'), findsOneWidget);
    expect(find.byTooltip('发送文字'), findsOneWidget);

    controller.previewState = VoiceConnectionState.speaking;
    controller.redraw();
    await tester.pump();
    expect(find.byTooltip('我要插话'), findsOneWidget);
    expect(find.byTooltip('立即停止回答'), findsOneWidget);
    expect(find.byTooltip('发送文字'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('interrupt controls fit 320px at 200% in $brightness', (
      tester,
    ) async {
      final controller = ChatPreviewController()
        ..connected = true
        ..responseId = 'reply-1'
        ..previewState = VoiceConnectionState.speaking;
      await mountChat(
        tester,
        controller,
        size: const Size(320, 640),
        textScale: 2,
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      for (final tooltip in ['我要插话', '立即停止回答']) {
        final button = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == tooltip,
        );
        expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets(
      'fits a narrow screen, 200 percent text, keyboard and preferences in $brightness',
      (tester) async {
        final controller = ChatPreviewController()..connected = true;
        await mountChat(
          tester,
          controller,
          size: const Size(320, 640),
          textScale: 2,
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('结束对话').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('对话偏好'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final fields = tester.widgetList<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        );
        expect(fields.every((field) => field.onChanged == null), isTrue);
        await tester.tap(find.byTooltip('关闭对话偏好'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '写下一点今天的小事');
        await tester.pumpAndSettle();
        expect(find.text('结束对话').hitTestable(), findsOneWidget);
        expect(find.byType(TextField).hitTestable(), findsOneWidget);
      },
    );
  }
}
