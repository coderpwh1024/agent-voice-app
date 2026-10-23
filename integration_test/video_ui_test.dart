import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/videos/data/video_api.dart';
import 'package:agent_voice_app/features/videos/video_create_page.dart';
import 'package:agent_voice_app/features/videos/video_detail_page.dart';
import 'package:agent_voice_app/features/videos/video_studio_page.dart';
import 'package:agent_voice_app/features/videos/video_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

import 'support/backend_auth.dart';

Widget preview(Widget page, {bool dark = false}) => MaterialApp(
  key: ValueKey(dark),
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
  ),
  home: page,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('USB editorial studio: real gallery, creation and playback', (
    tester,
  ) async {
    final AppConfig config = await backendTestConfig();
    final api = VideoApi(config);
    addTearDown(api.close);
    final page = await api.list();
    expect(page.items, isNotEmpty);
    final task = page.items.firstWhere(
      (item) => item.playableUri != null && item.coverUri != null,
      orElse: () => page.items.first,
    );
    await tester.pumpWidget(preview(VideoStudioPage(config: config, api: api)));
    await tester.pump(const Duration(seconds: 3));
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    expect(find.byType(VideoWordmark), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await binding.takeScreenshot('studio-editorial');
    await tester.scrollUntilVisible(
      find.text(task.displayTitle).first,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 180));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('studio-grid');
    await tester.scrollUntilVisible(
      find.byTooltip('列表视图'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('studio-feed');
    await tester.pumpWidget(preview(VideoCreatePage(config: config, api: api)));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('studio-create');
    await tester.enterText(
      find.byKey(const Key('video-prompt')),
      '午后光线穿过窗边绿植，一杯咖啡升起热气，镜头缓慢推进。',
    );
    await tester.ensureVisible(find.byKey(const Key('video-title')));
    await tester.enterText(find.byKey(const Key('video-title')), '光落下的地方');
    await tester.ensureVisible(find.byKey(const Key('video-cover-url')));
    await tester.enterText(
      find.byKey(const Key('video-cover-url')),
      task.coverUrl ?? '',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('预览封面'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览封面'));
    await tester.pump(const Duration(seconds: 2));
    await tester.drag(find.byType(ListView), const Offset(0, 220));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('studio-cover');
    await tester.pumpWidget(
      preview(
        VideoDetailPage(
          config: config,
          recordId: task.id,
          initialTask: task,
          api: api,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    if (task.playableUri != null) {
      expect(find.byType(VideoPlayer), findsNothing);
      await binding.takeScreenshot('studio-detail');
      await tester.tap(find.byTooltip('播放影片').first);
      for (
        var n = 0;
        n < 60 && find.byType(VideoPlayer).evaluate().isEmpty;
        n++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.byType(VideoPlayer), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      final controller = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      expect(controller.value.position, greaterThan(Duration.zero));
      await binding.takeScreenshot('studio-playing');
      await controller.pause();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      preview(VideoStudioPage(config: config, api: api), dark: true),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('studio-dark');
    expect(tester.takeException(), isNull);
    binding.reportData ??= {};
    binding.reportData!.addAll({
      'read_only_gallery': true,
      'created_new_video': false,
      'grid_and_feed': true,
      'cover_preview': true,
      'existing_video_playback': task.playableUri != null,
      'light_and_dark': true,
      'base_url': config.baseUrl,
    });
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 5)));
}
