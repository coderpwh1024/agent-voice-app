import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:agent_voice_app/features/videos/data/video_api.dart';
import 'package:agent_voice_app/features/videos/data/video_models.dart';
import 'package:agent_voice_app/features/videos/video_create_page.dart';
import 'package:agent_voice_app/features/videos/video_detail_page.dart';
import 'package:agent_voice_app/features/videos/video_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

import 'support/backend_auth.dart';
import 'video_ui_test.dart' as gallery;

// Stable keys make rerunning this explicit backend verification idempotent.
class WanVerificationApi extends VideoApi {
  WanVerificationApi(super.config);
  VideoDraft? submitted;
  VideoTask? created;
  static String keyFor(String model) =>
      'app-wan3-usb-20261024-v1-${model.replaceAll('.', '-')}';
  @override
  Future<VideoTask> create(VideoDraft draft, String key) async {
    submitted = draft;
    return created = await super.create(draft, keyFor(draft.model));
  }
}

Widget preview(Widget page, {bool dark = false, double scale = 1}) =>
    MaterialApp(
      key: ValueKey('$dark:$scale'),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: page,
    );

Future<void> reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      220,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.4);
  await tester.pumpAndSettle();
  // Native IME insets can finish changing after the first scroll.
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.4);
  await tester.pumpAndSettle();
}

Future<void> select(WidgetTester tester, String label, String option) async {
  final picker = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        w.key.toString().contains('$label:'),
  );
  await reveal(tester, picker);
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'USB Wan 3.0 two models, idempotency, archival, native playback and UI',
    (tester) async {
      debugPrint('WAN VERIFY: reading secure session');
      final config = await backendTestConfig().timeout(
        const Duration(seconds: 20),
      );
      debugPrint('WAN VERIFY: secure session available');
      final api = WanVerificationApi(config);
      addTearDown(api.close);
      binding.reportData ??= {};
      binding.reportData!['wan_base_url'] = config.baseUrl;
      await tester.pumpWidget(
        preview(VideoCreatePage(config: config, api: api)),
      );
      await tester.pumpAndSettle();
      debugPrint('WAN VERIFY: form mounted');
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      debugPrint('WAN VERIFY: screenshot surface ready');
      await select(tester, '生成模型', '万相 3.0 · 标准版');
      await binding.takeScreenshot('wan-create-standard');
      debugPrint('WAN VERIFY: standard model selected');
      // Field submission and parameter switching are covered by widget tests;
      // keep the paid API check independent of native keyboard timing.
      const draft = VideoDraft(
        prompt: '清晨阳光照在绿叶上，微风轻轻吹动叶片，镜头缓慢推进。',
        title: '万相联调 · 晨光与绿叶',
        model: 'wan3.0-video',
        duration: 2,
        resolution: '480P',
        audio: true,
        promptExtend: true,
      );
      final task = await api.create(draft, 'ignored');
      debugPrint('WAN VERIFY: create response #${task.id} ${task.status}');
      final repeated = await api.create(draft, 'ignored');
      expect(repeated.id, api.created!.id);
      await expectLater(
        api.create(
          const VideoDraft(prompt: '不同参数', model: 'wan3.0-video'),
          'ignored',
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
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
      await tester.pump(const Duration(seconds: 2));
      await binding.takeScreenshot('wan-detail-pending');
      await tester.pumpWidget(const SizedBox.shrink());

      Future<VideoTask> complete(VideoTask task) async {
        var latest = await api.detail(task.id);
        final deadline = DateTime.now().add(const Duration(minutes: 12));
        while (latest.shouldPoll && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(seconds: 10));
          latest = await api.detail(task.id);
          debugPrint(
            'WAN VERIFY: ${latest.model} #${latest.id} ${latest.status}/${latest.storageStatus}',
          );
        }
        binding.reportData!['wan_${task.model}'] = {
          'record_id': latest.id,
          'status': latest.status,
          'storage_status': latest.storageStatus,
          'error_code': latest.errorCode,
        };
        expect(latest.status, 'SUCCEEDED', reason: '上游万相应实际完成生成');
        expect(latest.storageStatus, 'STORED');
        expect(latest.coverUri, isNotNull);
        final listed = await api.list(model: latest.model);
        expect(
          listed.items.every((item) => item.model == latest.model),
          isTrue,
        );
        expect(listed.items.any((item) => item.id == latest.id), isTrue);
        await tester.pumpWidget(
          preview(
            VideoDetailPage(
              config: config,
              recordId: latest.id,
              initialTask: latest,
              api: api,
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(VideoPlayer), findsNothing);
        await binding.takeScreenshot('wan-${latest.model}-detail');
        await tester.tap(find.byTooltip('播放影片').first);
        for (
          var n = 0;
          n < 90 && find.byType(VideoPlayer).evaluate().isEmpty;
          n++
        ) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(find.byType(VideoPlayer), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        final player = tester
            .widget<VideoPlayer>(find.byType(VideoPlayer))
            .controller;
        for (
          var n = 0;
          n < 40 &&
              player.value.position == Duration.zero &&
              !player.value.hasError;
          n++
        ) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(player.value.position, greaterThan(Duration.zero));
        await binding.takeScreenshot('wan-${latest.model}-playing');
        await player.pause();
        await tester.pumpWidget(const SizedBox.shrink());
        return latest;
      }

      final standard = await complete(repeated);
      final primeDraft = VideoDraft(
        prompt: '',
        title: '万相联调 · 图片生视频',
        model: 'wan3.0-video-prime',
        firstFrameUrl: standard.coverUrl,
        lastFrameUrl: standard.coverUrl,
        duration: 2,
        resolution: '480P',
        ratio: 'adaptive',
        seed: -1,
        watermark: false,
        audio: false,
        promptExtend: false,
      );
      final prime = await api.create(primeDraft, 'ignored');
      expect(prime.firstFrameUrl, primeDraft.firstFrameUrl);
      expect(prime.lastFrameUrl, primeDraft.lastFrameUrl);
      expect((await api.create(primeDraft, 'ignored')).id, prime.id);
      await complete(prime);

      // Read-only UI sweep: no further model submissions.
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          preview(
            VideoCreatePage(config: config, api: api),
            dark: dark,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        await select(tester, '生成模型', '万相 3.0 · 高速版');
        await reveal(tester, find.byKey(const Key('video-first-frame')));
        await binding.takeScreenshot('wan-frames-large-dark-$dark');
        await reveal(tester, find.byKey(const Key('video-submit')));
        await tester.tap(find.byKey(const Key('video-submit')));
        await tester.pumpAndSettle();
        expect(find.byType(VideoNotice), findsOneWidget);
        await binding.takeScreenshot('wan-error-large-dark-$dark');
        expect(tester.takeException(), isNull);
      }
      binding.reportData!['wan_idempotency'] = true;
      binding.reportData!['wan_native_playback'] = true;
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
  gallery.main();
}
