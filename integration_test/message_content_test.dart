import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/api/chat_record_models.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/core/content/message_content_view.dart';
import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:agent_voice_app/features/conversations/chat_record_detail_page.dart';
import 'package:agent_voice_app/features/voice_session/voice_home_page.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const resourceBase = 'http://127.0.0.1:8766';
const fixtureConfig = AppConfig(
  baseUrl: resourceBase,
  accessToken: 'fixture-token-must-not-leak',
  userId: '42',
);

class MessagePreviewController extends VoiceSessionController {
  MessagePreviewController() : super(config: fixtureConfig);
  List<ConversationEntry> entries = [];
  @override
  List<ConversationEntry> get messages => entries;
  @override
  bool get isConnected => true;
  @override
  VoiceConnectionState get state => VoiceConnectionState.listening;
  @override
  VoiceCapabilities get capabilities => VoiceCapabilities.fromJson({
    'enabled': true,
    'protocol_version': 1,
    'voices': ['Cherry'],
    'agents': [
      {'id': 'chatbot', 'speech_mode': 'streaming', 'cancel_execution': true},
    ],
  });
  @override
  Future<void> disableWakeWord() async {}
}

class MessageRecordsApi extends AgentApiClient {
  MessageRecordsApi(this.content) : super(fixtureConfig);
  final String content;
  @override
  Future<ChatRecordDetail> chatRecordDetail(
    String agentId,
    String date,
  ) async => ChatRecordDetail(
    recordDate: date,
    conversations: [
      DailyChatConversation(
        threadId: 'fixture-thread',
        agentId: agentId,
        updatedAt: DateTime.utc(2026, 10, 25, 4),
        title: '把日常的小小发现，慢慢分享',
        messages: [ChatItem(role: 'ai', content: content)],
      ),
    ],
  );
}

Future<Map<String, dynamic>> resourceStatus() async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(
      Uri.parse('$resourceBase/status'),
    )).close();
    return jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('USB rich voice content: links, images, GIF, errors and history', (
    tester,
  ) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final controller = MessagePreviewController();
    addTearDown(controller.dispose);
    var converted = false;
    Future<void> mount(
      String text, {
      bool dark = false,
      double scale = 1,
      bool streaming = false,
    }) async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.entries = [
        ConversationEntry(role: 'ai', text: text, isStreaming: streaming),
      ];
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(dark ? Brightness.dark : Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: VoiceHomePage(
            controller: controller,
            user: const AuthUser(id: 42, nickname: '小雨', email: ''),
            onOpenProfile: (_) async {},
            onOpenSettings: (_) async {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> shot(String name) async {
      expect(tester.takeException(), isNull, reason: name);
      await binding.takeScreenshot(name);
    }

    Future<void> reveal(Finder finder) async {
      await Scrollable.ensureVisible(
        tester.element(finder.first),
        alignment: .3,
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    final photo = '$resourceBase/static/photo.png?source=voice';
    final gif = '$resourceBase/static/smile.gif';
    await mount(
      '这份指南可以直接打开。\n\n[打开使用指南]($resourceBase/guide?source=voice)\n\n附件也可以通过链接查看：\n$resourceBase/manual.pdf\n\n把小小的开心分享给你 😊 :smile:',
    );
    await shot('voice-links-light');
    await mount('一张让人慢下来的画面。\n\n![山间日光]($photo)');
    for (var n = 0; n < 60 && find.byType(Image).evaluate().isEmpty; n++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(Image), findsOneWidget);
    await reveal(find.byType(Image));
    await shot('voice-photo-light');
    await tester.tap(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await shot('voice-photo-expanded');
    await tester.tap(find.text('复制链接'));
    await tester.pump(const Duration(milliseconds: 200));
    expect((await Clipboard.getData('text/plain'))!.text, photo);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));

    await mount('送你一个小小的笑脸 😊\n\n$gif', dark: true);
    for (var n = 0; n < 60 && find.byType(Image).evaluate().isEmpty; n++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    final stream = image.image.resolve(const ImageConfiguration());
    var frames = 0;
    final listener = ImageStreamListener((_, _) => frames++);
    stream.addListener(listener);
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 1000));
    stream.removeListener(listener);
    expect(frames, greaterThan(1));
    await shot('voice-sticker-dark');

    await mount(
      '图片还在返回，先读正文。\n\n![待完成]($resourceBase/static/asset?pending=1)',
      streaming: true,
    );
    expect(find.byType(MessageImageTile), findsNothing);
    await shot('voice-streaming');
    for (final dark in [false, true]) {
      await mount(
        '这是图片地址失效时的样子，正文和链接都会保留。\n\n![图片]($resourceBase/missing.png)',
        dark: dark,
        scale: 2,
      );
      for (var n = 0; n < 60 && find.text('重新加载').evaluate().isEmpty; n++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('重新加载'), findsOneWidget);
      await reveal(find.text('重新加载'));
      await tester.tap(find.text('重新加载'));
      await tester.pump(const Duration(seconds: 1));
      await shot('voice-error-large-$dark');
    }

    final api = MessageRecordsApi(
      '历史消息也保留相同的图片和链接。\n\n![静态资源](/static/asset)\n\n[使用指南]($resourceBase/guide)',
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: ChatRecordDetailPage(
          api: api,
          agentId: 'chatbot',
          record: ChatRecordDay(
            recordDate: '2026-10-25',
            latestAt: DateTime.utc(2026, 10, 25),
            conversationCount: 1,
          ),
        ),
      ),
    );
    for (var n = 0; n < 60 && find.byType(Image).evaluate().isEmpty; n++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(Image), findsOneWidget);
    await reveal(find.byType(Image));
    await shot('history-static-resource');
    await mount('[打开使用指南]($resourceBase/guide?source=voice)');
    final link = find.text('打开使用指南', findRichText: true).first;
    await reveal(link);
    debugPrint('RICH_CONTENT_OPENING_LINK');
    await tester.tapAt(tester.getTopLeft(link) + const Offset(30, 10));
    await tester.pump(const Duration(seconds: 3));
    for (
      var n = 0;
      n < 8 && !(await resourceStatus())['paths'].toString().contains('/guide');
      n++
    ) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    final browserLoaded = (await resourceStatus())['paths'].toString().contains(
      '/guide',
    );
    await tester.pump(const Duration(seconds: 1));

    final status = await resourceStatus();
    expect(status['authorization_seen'], isFalse);
    expect(status['paths'].toString(), isNot(contains('pending=1')));
    binding.reportData = {
      ...?binding.reportData,
      'resource_base_url': resourceBase,
      'voice_network_session_created': false,
      'controlled_message_preview': true,
      'real_http_image_load': true,
      'external_browser_loaded_link': browserLoaded,
      'animated_gif_frames': frames,
      'image_viewer_and_copy': true,
      'relative_static_and_extensionless_image': true,
      'history_compatibility': true,
      'streaming_deferred': true,
      'large_text_light_and_dark': true,
      'media_authorization_sent': false,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 7)));
}
