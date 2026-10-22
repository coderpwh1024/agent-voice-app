import 'dart:async';

import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/api/chat_record_models.dart';
import 'package:agent_voice_app/features/conversations/chat_record_detail_page.dart';
import 'package:agent_voice_app/core/api/video_reference.dart';
import 'package:agent_voice_app/features/videos/video_message_card.dart';
import 'package:agent_voice_app/features/videos/video_playback.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../core/video_reference_test.dart' show videoSummary;
import '../support/fake_video_platform.dart';
import 'chat_records_page_test.dart' as records;
import 'voice_home_page_test.dart' show ChatPreviewController, mountChat;

class MediaChatController extends ChatPreviewController {
  MediaChatController(this.operations) {
    connected = true;
    entries.clear();
    entries.add(
      ConversationEntry(
        role: 'ai',
        text: '视频已完成，可以看了。',
        video: VideoReference.tryParse(videoSummary()),
      ),
    );
  }
  final List<String> operations;
  @override
  VoiceSession? get session => connected
      ? VoiceSession(
          sessionId: 'old-session',
          threadId: 'original-thread',
          agentId: 'chatbot',
          voice: 'Cherry',
          expiresAt: DateTime.utc(2099),
        )
      : null;
  @override
  Future<void> disableWakeWord() async {
    operations.add('wake-stopped');
  }

  @override
  Future<void> disconnect() async {
    operations.add('voice-stopped');
    connected = false;
    notifyListeners();
  }

  @override
  Future<void> connect({
    required String agentId,
    required String voice,
    String? threadId,
  }) async {
    operations.add('voice-resumed:$agentId:$voice:$threadId');
    connected = true;
    notifyListeners();
  }
}

class VideoRecordsApi extends records.FakeRecordsApi {
  @override
  Future<ChatRecordDetail> chatRecordDetail(
    String agentId,
    String recordDate,
  ) async => ChatRecordDetail(
    recordDate: recordDate,
    conversations: [
      DailyChatConversation(
        threadId: 'original-thread',
        agentId: agentId,
        updatedAt: records.day.latestAt,
        messages: [
          ChatItem.fromJson({
            'type': 'ai',
            'content': '查到了这段视频。',
            'response_metadata': {'video': videoSummary()},
          }),
        ],
      ),
    ],
  );
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('agent_voice/audio'),
          (_) async => null,
        );
  });
  testWidgets(
    'video waits for voice to stop and releases native player before resuming the same thread',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final operations = <String>[];
      final original = VideoPlayerPlatform.instance;
      final platform = FakeVideoPlatform(operations)
        ..disposeGate = Completer<void>();
      VideoPlayerPlatform.instance = platform;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      final controller = MediaChatController(operations);
      await mountChat(tester, controller);
      expect(platform.sources, isEmpty);
      await tester.ensureVisible(find.text('播放视频'));
      await tester.tap(find.text('播放视频'));
      await tester.pumpAndSettle();
      expect(
        platform.sources.single,
        'https://cdn.example/videos/happyhorse/clip.mp4',
      );
      expect(
        operations.indexOf('voice-stopped'),
        lessThan(operations.indexOf('video-play')),
      );
      expect(controller.isConnected, isFalse);
      await tester.tap(find.byTooltip('返回对话'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(
        find.byTooltip('返回对话'),
        findsNothing,
        reason: 'The watch route must be removed before native disposal',
      );
      expect(
        find.byType(VideoPlayback, skipOffstage: false),
        findsNothing,
        reason: 'Player state must be disposed after the route transition',
      );
      expect(operations, contains('video-dispose-start'));
      expect(operations.where((e) => e.startsWith('voice-resumed')), isEmpty);
      platform.disposeGate!.complete();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(operations.last, 'voice-resumed:chatbot:Cherry:original-thread');
      expect(
        operations.indexOf('video-disposed'),
        lessThan(operations.indexOf(operations.last)),
      );
      expect(controller.isConnected, isTrue);
      expect(find.text('播放视频'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed native release does not restart microphone capture', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final operations = <String>[];
    final original = VideoPlayerPlatform.instance;
    final platform = FakeVideoPlatform(operations)
      ..disposeGate = Completer<void>();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = original);
    final controller = MediaChatController(operations);
    await mountChat(tester, controller);
    await tester.ensureVisible(find.text('播放视频'));
    await tester.tap(find.text('播放视频'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回对话'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    platform.disposeGate!.completeError(StateError('native release failed'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(controller.isConnected, isFalse);
    expect(operations.where((e) => e.startsWith('voice-resumed')), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('archived chat replies show the same playable video card', (
    tester,
  ) async {
    final api = VideoRecordsApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      records.app(
        ChatRecordDetailPage(api: api, agentId: 'chatbot', record: records.day),
      ),
    );
    await tester.pumpAndSettle();
    await records.scrollTo(tester, find.text('播放视频'));
    expect(find.byType(VideoMessageCard), findsOneWidget);
    expect(find.text('查到了这段视频。'), findsOneWidget);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'status cards support small screens and large text dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = ChatPreviewController();
        addTearDown(controller.dispose);
        final platform = FakeVideoPlatform([]);
        final original = VideoPlayerPlatform.instance;
        VideoPlayerPlatform.instance = platform;
        addTearDown(() => VideoPlayerPlatform.instance = original);
        for (final data in [
          videoSummary(),
          videoSummary(status: 'RUNNING', storage: 'NOT_READY', url: null),
          videoSummary(storage: 'FAILED'),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: ListView(
                  children: [
                    VideoMessageCard(
                      video: VideoReference.tryParse(data)!,
                      config: controller.config,
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.text('播放视频'),
            VideoReference.tryParse(data)!.playableUri != null
                ? findsOneWidget
                : findsNothing,
          );
        }
        expect(platform.sources, isEmpty);
      },
    );
  }
}
