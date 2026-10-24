import 'package:agent_voice_app/features/videos/data/video_models.dart';
import 'package:agent_voice_app/features/videos/video_studio_page.dart';
import 'package:agent_voice_app/features/videos/video_create_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'videos_page_test.dart' show config, FakeVideoApi, wrap, tap;

Future<void> chooseModel(WidgetTester tester, String label) async {
  final picker = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        w.key.toString().contains('生成模型:'),
  );
  await Scrollable.ensureVisible(tester.element(picker), alignment: 0.4);
  await tester.pumpAndSettle();
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class FilterVideoApi extends FakeVideoApi {
  final models = <String?>[];
  @override
  Future<VideoTaskPage> list({
    int page = 1,
    String? status,
    String? storageStatus,
    String? model,
  }) {
    models.add(model);
    return super.list(
      page: page,
      status: status,
      storageStatus: storageStatus,
      model: model,
    );
  }
}

void main() {
  testWidgets(
    'invalid seed remains blocked after advanced settings are collapsed',
    (tester) async {
      final api = FakeVideoApi();
      addTearDown(api.close);
      await tester.pumpWidget(wrap(VideoCreatePage(config: config, api: api)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('video-prompt')), '海边日落');
      await tap(tester, find.text('更多设置'));
      await tester.ensureVisible(find.byKey(const Key('video-seed')));
      await tester.enterText(find.byKey(const Key('video-seed')), 'abc');
      await tap(tester, find.text('更多设置'));
      await tap(tester, find.byKey(const Key('video-submit')));
      expect(api.keys, isEmpty);
      expect(find.text('请输入 0–2147483647 的整数'), findsOneWidget);
    },
  );

  testWidgets(
    'model filter combines with status and pagination; view changes do not refetch',
    (tester) async {
      final api = FilterVideoApi();
      addTearDown(api.close);
      await tester.pumpWidget(wrap(VideoStudioPage(config: config, api: api)));
      await tester.pumpAndSettle();
      await tap(tester, find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.text('万相 3.0 · 标准版').last);
      await tester.pumpAndSettle();
      expect(api.models.last, 'wan3.0-video');
      expect(api.calls.last.$1, 1);
      await tap(tester, find.text('已完成'));
      expect(api.models.last, 'wan3.0-video');
      expect(api.calls.last, (1, 'SUCCEEDED', 'STORED'));
      await tap(tester, find.text('加载更多作品'));
      expect(api.models.last, 'wan3.0-video');
      expect(api.calls.last.$1, 2);
      final count = api.calls.length;
      await tester.scrollUntilVisible(
        find.byTooltip('列表视图'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, find.byTooltip('列表视图'));
      expect(api.calls.length, count);
      await tester.scrollUntilVisible(
        find.text('影片 #0002'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('影片 #0002'), findsOneWidget);
    },
  );

  testWidgets(
    'Wan image-only submission, smart duration and uncertain retry preserve every field',
    (tester) async {
      final api = FakeVideoApi();
      addTearDown(api.close);
      await tester.pumpWidget(wrap(VideoCreatePage(config: config, api: api)));
      await tester.pumpAndSettle();
      await chooseModel(tester, '万相 3.0 · 标准版');
      await tester.scrollUntilVisible(
        find.byKey(const Key('video-first-frame')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const Key('video-first-frame')),
        'https://cdn.example/first.png',
      );
      await tester.ensureVisible(find.byKey(const Key('video-last-frame')));
      await tester.enterText(
        find.byKey(const Key('video-last-frame')),
        'https://cdn.example/last.png',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tap(tester, find.byKey(const Key('video-smart-duration')));
      await tap(tester, find.text('更多设置'));
      await tap(tester, find.byKey(const Key('video-audio')));
      await tap(tester, find.byKey(const Key('video-prompt-extend')));
      await tester.scrollUntilVisible(
        find.byKey(const Key('video-seed')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byKey(const Key('video-seed')), '-1');
      FocusManager.instance.primaryFocus?.unfocus();
      await tap(tester, find.byKey(const Key('video-submit')));
      final draft = api.drafts.single;
      expect(draft.model, 'wan3.0-video');
      expect(draft.prompt, '');
      expect(draft.firstFrameUrl, 'https://cdn.example/first.png');
      expect(draft.lastFrameUrl, 'https://cdn.example/last.png');
      expect(draft.duration, -1);
      expect(draft.seed, -1);
      expect(draft.audio, false);
      expect(draft.promptExtend, false);
      final key = api.keys.single;
      await tester.pumpWidget(wrap(VideoCreatePage(config: config, api: api)));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('video-submit')));
      expect(api.drafts.last, same(draft));
      expect(api.keys.last, key);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching to HappyHorse omits hidden Wan fields and normalizes smart duration',
    (tester) async {
      final api = FakeVideoApi();
      addTearDown(api.close);
      await tester.pumpWidget(wrap(VideoCreatePage(config: config, api: api)));
      await tester.pumpAndSettle();
      await chooseModel(tester, '万相 3.0 · 高速版');
      await tap(tester, find.byKey(const Key('video-smart-duration')));
      await chooseModel(tester, 'HappyHorse 1.0');
      await tester.scrollUntilVisible(
        find.byKey(const Key('video-prompt')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byKey(const Key('video-prompt')), '海边日落');
      await tap(tester, find.byKey(const Key('video-submit')));
      expect(api.drafts.single.model, 'happyhorse-1.0-t2v');
      expect(api.drafts.single.duration, 5);
      expect(api.drafts.single.audio, isNull);
      expect(api.drafts.single.firstFrameUrl, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('Wan entire form is usable at 320px and 200% text dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeVideoApi();
      api.pendingSubmission = null;
      addTearDown(api.close);
      await tester.pumpWidget(
        wrap(
          VideoCreatePage(config: config, api: api),
          dark: dark,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await chooseModel(tester, '万相 3.0 · 标准版');
      for (var i = 0; i < 25; i++) {
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(
        find.byKey(const Key('video-submit')).hitTestable(),
        findsOneWidget,
      );
      expect(VideoDraft.ratiosFor('wan3.0-video'), contains('adaptive'));
    });
  }
}
