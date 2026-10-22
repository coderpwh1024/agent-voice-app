import 'dart:io';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/features/videos/data/video_api.dart';
import 'package:agent_voice_app/features/videos/data/video_models.dart';
import 'package:agent_voice_app/features/videos/video_create_page.dart';
import 'package:agent_voice_app/features/videos/video_detail_page.dart';
import 'package:agent_voice_app/features/videos/video_studio_page.dart';
import 'package:agent_voice_app/features/videos/video_playback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

import 'support/backend_auth.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('USB phone: authenticated video API and existing features', (
    tester,
  ) async {
    const bridge = String.fromEnvironment('VIDEO_TEST_AUTH_BRIDGE');
    final config = await backendTestConfig();
    final client = AgentApiClient(config);
    final api = VideoApi(config, client: client);
    addTearDown(client.close);
    if (bridge.isEmpty) {
      final user = await client.currentUser();
      expect(user.id.toString(), config.userId);
    }
    final capabilities = await client.capabilities();
    expect(capabilities.agents, isNotEmpty);
    await client.chatRecords(
      capabilities.defaultAgentId ?? capabilities.agents.first.id,
    );
    await client.memories(limit: 1);
    final before = await api.list();
    expect(before.total, greaterThanOrEqualTo(0));

    Widget wrap(Widget page) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffaa496b)),
      ),
      home: page,
    );
    await tester.pumpWidget(wrap(VideoStudioPage(config: config, api: api)));
    await tester.pump(const Duration(seconds: 2));
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('video-studio');
    await tester.pumpWidget(wrap(VideoCreatePage(config: config, api: api)));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('video-create');
    await tester.enterText(
      find.byKey(const Key('video-prompt')),
      '夕阳下的湖岸，湖水轻轻泛起涟漪。',
    );
    await tester.ensureVisible(find.byKey(const Key('video-title')));
    await tester.enterText(find.byKey(const Key('video-title')), '湖畔来信 · 日落之前');
    await tester.ensureVisible(find.byKey(const Key('video-cover-url')));
    await tester.enterText(
      find.byKey(const Key('video-cover-url')),
      'https://www.bing.com/th?id=OHR.NaejangsanNP_ZH-CN6538893004_1920x1080.jpg',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('预览封面'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览封面'));
    await tester.pump(const Duration(seconds: 3));
    await binding.takeScreenshot('video-create-metadata');
    await tester.pumpWidget(const SizedBox.shrink());
    const draft = VideoDraft(
      prompt: '夕阳下的湖岸，湖水轻轻泛起涟漪，镜头缓慢横移，暖色胶片质感，宁静而浪漫。',
      title: '湖畔来信 · 日落之前',
      coverUrl: 'https://www.bing.com/th?id=OHR.NaejangsanNP_ZH-CN6538893004_1920x1080.jpg',
      resolution: '480P',
      duration: 3,
    );
    final task = await api.create(draft, 'app-video-metadata-usb-20261022-01');
    final repeated = await api.create(
      draft,
      'app-video-metadata-usb-20261022-01',
    );
    expect(task.title, draft.title);
    expect(task.coverUrl, draft.coverUrl);
    expect(repeated.title, draft.title);
    expect(repeated.coverUrl, draft.coverUrl);
    expect(repeated.id, task.id, reason: '相同幂等键必须返回同一任务');
    final after = await api.list();
    expect(after.items.any((item) => item.id == task.id), isTrue);
    final listed = after.items.singleWhere((item) => item.id == task.id);
    expect(listed.title, draft.title);
    expect(listed.coverUrl, draft.coverUrl);
    await expectLater(
      api.create(
        const VideoDraft(prompt: 'changed metadata', title: '更改标题'),
        'app-video-metadata-usb-20261022-01',
      ),
      throwsA(
        isA<ApiException>().having((error) => error.statusCode, 'status', 409),
      ),
    );
    var latest = await api.detail(task.id);
    expect(latest.title, draft.title);
    expect(latest.coverUrl, draft.coverUrl);
    await tester.pumpWidget(wrap(VideoStudioPage(config: config, api: api)));
    await tester.pump(const Duration(seconds: 2));
    await tester.scrollUntilVisible(
      find.text(draft.title!),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 240));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('video-collection-metadata');
    await tester.pumpWidget(const SizedBox.shrink());
    var deadline = DateTime.now().add(const Duration(minutes: 8));
    while (latest.shouldPoll && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 10));
      latest = await api.detail(task.id);
    }
    binding.reportData ??= {};
    binding.reportData!.addAll({
      'record_id': latest.id,
      'metadata_create_list_detail': true,
      'metadata_idempotency_conflict': true,
      'status': latest.status,
      'storage_status': latest.storageStatus,
      'existing_profile': bridge.isEmpty,
      'isolated_test_identity': bridge.isNotEmpty,
      'existing_capabilities': true,
      'existing_chat_records': true,
      'existing_memories': true,
    });
    await tester.pumpWidget(
      wrap(
        VideoDetailPage(
          config: config,
          recordId: latest.id,
          initialTask: latest,
          api: api,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    if (latest.playableUri != null) {
      for (
        var attempt = 0;
        attempt < 60 && find.byType(VideoPlayer).evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.byType(VideoPlayer), findsOneWidget);
      await tester.tap(find.byTooltip('播放影片').first);
      await tester.pump(const Duration(seconds: 2));
      final player = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      expect(player.value.position, greaterThan(Duration.zero));
      await player.pause();
      await tester.pump();
      binding.reportData!['native_playback'] = true;
    }
    expect(find.text(draft.title!), findsWidgets);
    expect(
      tester
          .widget<VideoPlayback>(find.byType(VideoPlayback))
          .coverUri
          .toString(),
      draft.coverUrl,
    );
    await binding.takeScreenshot('video-detail');
    expect(tester.takeException(), isNull);
    if (latest.playableUri != null) {
      final http = HttpClient();
      try {
        final response = await (await http.getUrl(latest.playableUri!)).close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      } finally {
        http.close(force: true);
      }
    }
    expect(latest.status, 'SUCCEEDED', reason: '实际模型生成失败，请检查后端模型服务');
    expect(latest.storageStatus, 'STORED', reason: '生成完成后应转存成功');
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 12)));
}
