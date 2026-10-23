import 'dart:io';
import 'dart:ui' as ui;

import 'package:agent_voice_app/core/api/video_reference.dart';
import 'package:agent_voice_app/core/audio/audio_bridge.dart';
import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:agent_voice_app/core/theme/editorial_widgets.dart';
import 'package:agent_voice_app/features/conversations/chat_records_page.dart';
import 'package:agent_voice_app/features/conversations/chat_record_widgets.dart';
import 'package:agent_voice_app/features/memories/memory_widgets.dart';
import 'package:agent_voice_app/features/profile/edit_profile_page.dart';
import 'package:agent_voice_app/features/settings/settings_sheet.dart';
import 'package:agent_voice_app/features/videos/video_create_page.dart';
import 'package:agent_voice_app/features/videos/video_detail_page.dart';
import 'package:agent_voice_app/features/videos/video_message_card.dart';
import 'package:agent_voice_app/features/videos/video_playback.dart';
import 'package:agent_voice_app/features/videos/video_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../support/fake_video_platform.dart';
import 'chat_records_page_test.dart' as records;
import 'editorial_layout_test.dart' show config, user;
import 'videos_page_test.dart' show FakeVideoApi, tap;
import 'voice_home_page_test.dart' show ChatPreviewController, mountChat;

class ProcessingPreview extends ChatPreviewController {
  @override
  AudioProcessingState get audioProcessingState => const AudioProcessingState(
    mode: AudioCaptureMode.standby,
    aecAvailable: true,
    aecEnabled: false,
    noiseSuppressionAvailable: true,
    noiseSuppressionEnabled: false,
  );
}

Widget themed(
  Widget page, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  key: UniqueKey(),
  theme: AppTheme.build(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: page,
);

void main() {
  const previewDirectory = String.fromEnvironment('UI_AUDIT_PREVIEW_DIR');
  const previewFont = String.fromEnvironment('UI_AUDIT_PREVIEW_FONT');
  const iconFont = String.fromEnvironment('UI_AUDIT_ICON_FONT');
  if (previewDirectory.isNotEmpty) {
    setUpAll(() async {
      for (final entry in {
        'AuditBody': previewFont,
        'StudioSerif': 'assets/fonts/StudioSerif-Regular.ttf',
        'MaterialIcons': iconFont,
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(
            File(entry.value)
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
      }
    });
  }
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('agent_voice/audio'),
          (_) async => null,
        );
  });
  testWidgets('shared controls have 48px interactive targets', (tester) async {
    await tester.pumpWidget(
      themed(
        Scaffold(
          body: Column(
            children: [
              TextButton(onPressed: () {}, child: const Text('重试')),
              FilledButton(onPressed: () {}, child: const Text('保存')),
              OutlinedButton(onPressed: () {}, child: const Text('取消')),
              IconButton(
                onPressed: () {},
                tooltip: '刷新',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      ),
    );
    for (final type in [TextButton, FilledButton, OutlinedButton, IconButton]) {
      final size = tester.getSize(find.byType(type));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('connection sheet keeps its content height on a tall screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SettingsSheet(
                  config: config,
                  user: null,
                  onLogout: () async {},
                ),
              ),
              child: const Text('打开设置'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SettingsSheet)).height, lessThan(800));
    expect(find.text('保存').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'video metadata uses one title fallback and a missing-cover placeholder',
    (tester) async {
      final api = FakeVideoApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        themed(VideoDetailPage(config: config, recordId: 7, api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('影片 #0007'), findsOneWidget);
      const video = VideoReference(
        recordId: 7,
        status: 'FAILED',
        storageStatus: 'NOT_READY',
      );
      await tester.pumpWidget(
        themed(
          Scaffold(
            body: ListView(
              children: const [VideoMessageCard(video: video, config: config)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('影片 #0007'), findsOneWidget);
      expect(find.text('暂无封面'), findsOneWidget);
      final title = tester.widget<Text>(find.text('影片 #0007'));
      expect(title.maxLines, 2);
      expect(title.style?.fontFamily, isNot('StudioSerif'));
    },
  );

  testWidgets(
    'cover preview validates only its own field and never creates a task',
    (tester) async {
      final api = FakeVideoApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        themed(VideoCreatePage(config: config, api: api)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('video-cover-url')));
      await tester.enterText(
        find.byKey(const Key('video-cover-url')),
        'https://cdn.example/cover.jpg',
      );
      await tap(tester, find.text('预览封面'));
      expect(find.byType(VideoCover), findsOneWidget);
      expect(find.text('写下你想看见的画面'), findsNothing);
      expect(api.keys, isEmpty);
      await tester.enterText(
        find.byKey(const Key('video-cover-url')),
        'file:///private/cover.jpg',
      );
      await tap(tester, find.text('预览封面'));
      expect(find.text('请输入有效的 HTTP/HTTPS 封面地址'), findsOneWidget);
      expect(find.byType(VideoCover), findsNothing);
    },
  );

  testWidgets('detail player does not fetch video before a user action', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final operations = <String>[];
    final platform = FakeVideoPlatform(operations);
    final previous = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    await tester.pumpWidget(
      themed(
        Scaffold(
          body: VideoPlayback(uri: Uri.parse('https://cdn.example/video.mp4')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(platform.sources, isEmpty);
    await tester.tap(find.byTooltip('播放影片'));
    await tester.pumpAndSettle();
    expect(platform.sources.single, 'https://cdn.example/video.mp4');
    expect(operations, contains('video-play'));
    expect(find.byType(Slider), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    for (var n = 0; n < 6 && !operations.contains('video-disposed'); n++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
    expect(operations, contains('video-disposed'));
  });

  testWidgets('nickname limit follows backend Unicode code points', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(const EditProfilePage(config: config, user: user)),
    );
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.enterText(field, 'e\u0301' * 33);
    await tester.pumpAndSettle();
    expect(find.text('昵称最多 64 个字符'), findsOneWidget);
    expect(find.text('66 / 64'), findsOneWidget);
  });

  testWidgets(
    'settings rejects malformed or credential-bearing server addresses inline',
    (tester) async {
      await tester.pumpWidget(
        themed(
          Scaffold(
            body: SettingsSheet(
              config: config,
              user: user,
              onLogout: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final address in ['http:', 'https://user:secret@example.com']) {
        await tester.enterText(find.byType(TextField), address);
        await tap(tester, find.text('保存'));
        expect(find.text('请输入有效的 http/https 后端地址'), findsOneWidget);
        expect(find.byType(SettingsSheet), findsOneWidget);
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('empty and error states remain readable: $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const key = ValueKey('state-preview');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(
            brightness,
            baseTheme: ThemeData(
              brightness: brightness,
              fontFamily: previewDirectory.isEmpty ? null : 'AuditBody',
            ),
          ),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: const [
                    EditorialHeading(
                      eyebrow: 'STATES / FEEDBACK',
                      title: '关于你的，都在这里。',
                    ),
                    SizedBox(height: 24),
                    VideoNotice('暂时无法连接视频服务，请检查网络后重试', error: true),
                    SizedBox(height: 16),
                    MemoryNotice(message: '操作结果暂时无法确认，请刷新核对后再操作。', error: true),
                    SizedBox(height: 16),
                    VideoCover(),
                    RecordStatus(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: '还没有聊天记录',
                      description: '返回首页聊一聊，或切换助手看看。',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final colors = Theme.of(tester.element(find.byType(VideoNotice)))
          .colorScheme;
      expect(
        tester.widget<Text>(find.text('暂时无法连接视频服务，请检查网络后重试')).style!.color,
        colors.onErrorContainer,
      );
      if (previewDirectory.isNotEmpty) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(key),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(previewDirectory).create(recursive: true);
          await File('$previewDirectory/states-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
    testWidgets(
      'all archive rows stay readable at 320px and 200%: $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = records.FakeRecordsApi();
        addTearDown(api.close);
        await tester.pumpWidget(
          themed(
            ChatRecordsPage(
              config: config,
              agents: records.agents,
              initialAgentId: 'chatbot',
              api: api,
            ),
            brightness: brightness,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        final scroll = find.byType(CustomScrollView);
        for (var n = 0; n < 6; n++) {
          await tester.drag(scroll, const Offset(0, -240));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.text('按 UTC 日期归档'), findsOneWidget);
      },
    );

    testWidgets(
      'voice suggestions fill the composer and audio badges wrap: $brightness',
      (tester) async {
        final controller = ProcessingPreview()..entries.clear();
        await mountChat(
          tester,
          controller,
          size: const Size(320, 700),
          textScale: 2,
          brightness: brightness,
        );
        await tester.scrollUntilVisible(
          find.text('给我一个灵感'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('给我一个灵感'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '给我一个灵感',
        );
        expect(controller.isConnected, isFalse);
        await tester.tap(find.byTooltip('对话偏好'));
        await tester.pumpAndSettle();
        expect(find.text('降噪不可用'), findsOneWidget);
        expect(find.text('对话时回声消除'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
