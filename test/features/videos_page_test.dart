import '../support/video_image_helpers.dart';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/videos/data/video_api.dart';
import 'package:agent_voice_app/features/videos/data/video_models.dart';
import 'package:agent_voice_app/features/videos/video_create_page.dart';
import 'package:agent_voice_app/features/videos/video_detail_page.dart';
import 'package:agent_voice_app/features/videos/video_edit_page.dart';
import 'package:agent_voice_app/features/videos/video_studio_page.dart';
import 'package:agent_voice_app/features/videos/video_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const config = AppConfig(
  baseUrl: 'http://127.0.0.1:8000',
  accessToken: 'test',
  userId: '7',
);
VideoTask task(int id, {String? title, String? coverUrl}) => VideoTask(
  title: title,
  coverUrl: coverUrl,
  id: id,
  status: 'FAILED',
  storageStatus: 'NOT_READY',
  createdAt: DateTime.utc(2026, 10, 22),
  updatedAt: DateTime.utc(2026, 10, 22),
);

class FakeVideoApi extends VideoApi {
  FakeVideoApi() : super(config);
  final calls = <(int, String?, String?)>[];
  final keys = <String>[];
  final drafts = <VideoDraft>[];
  Object? failure;
  Object createFailure = const ApiException(504, 'timeout');
  bool failMore = false;
  String? title, coverUrl;
  VideoTask? detailTask;
  final updates = <VideoMetadataUpdate>[];
  int deletes = 0;
  @override
  Future<VideoTaskPage> list({
    int page = 1,
    String? status,
    String? storageStatus,
    String? model,
  }) async {
    calls.add((page, status, storageStatus));
    if (failure != null) throw failure!;
    if (failMore && page > 1) throw const ApiException(0, 'offline');
    return VideoTaskPage(
      items: [task(page, title: title, coverUrl: coverUrl)],
      total: 2,
      page: page,
      totalPages: 2,
    );
  }

  @override
  Future<VideoTask> detail(int id) async =>
      detailTask ?? task(id, title: title, coverUrl: coverUrl);
  @override
  Future<VideoTask> updateMetadata(int id, VideoMetadataUpdate update) async {
    updates.add(update);
    return task(
      id,
      title: update.title ?? title,
      coverUrl: update.coverUrl ?? coverUrl,
    );
  }

  @override
  Future<void> delete(int id) async {
    deletes++;
  }

  @override
  Future<VideoTask> create(VideoDraft draft, String key) async {
    keys.add(key);
    drafts.add(draft);
    throw createFailure;
  }
}

Widget wrap(Widget home, {bool dark = false, double scale = 1}) => MaterialApp(
  key: UniqueKey(),
  theme: ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: home,
);
Future<void> tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.4);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('studio icon actions stay tappable and open the expected page', (
    tester,
  ) async {
    final api = FakeVideoApi();
    addTearDown(api.close);
    await tester.pumpWidget(wrap(VideoStudioPage(config: config, api: api)));
    await tester.pumpAndSettle();
    for (final tooltip in ['按编号查询', '新建影片']) {
      final button = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      );
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.byTooltip('按编号查询'));
    await tester.pumpAndSettle();
    expect(find.text('查找影片'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建影片'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoCreatePage), findsOneWidget);
    expect(find.text('生成我的影片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'filters and pagination preserve existing cards when loading more fails',
    (tester) async {
      final api = FakeVideoApi();
      addTearDown(api.close);
      await tester.pumpWidget(wrap(VideoStudioPage(config: config, api: api)));
      await tester.pumpAndSettle();
      await tap(tester, find.text('加载更多作品'));
      expect(api.calls.last.$1, 2);
      expect(find.text('影片 #0001'), findsOneWidget);
      expect(find.text('影片 #0002'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tap(tester, find.text('已完成'));
      expect(api.calls.last, (1, 'SUCCEEDED', 'STORED'));
      api.failMore = true;
      await tap(tester, find.text('加载更多作品'));
      expect(find.text('影片 #0001'), findsOneWidget);
      expect(find.textContaining('offline'), findsOneWidget);
    },
  );
  testWidgets(
    'gallery view switches without refetching or losing loaded works',
    (tester) async {
      final api = FakeVideoApi();
      addTearDown(api.close);
      await tester.pumpWidget(wrap(VideoStudioPage(config: config, api: api)));
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('列表视图'));
      expect(api.calls.length, 1);
      expect(
        tester
            .widgetList<VideoCover>(find.byType(VideoCover))
            .every((cover) => cover.aspectRatio == 16 / 9),
        isTrue,
      );
      await tap(tester, find.byTooltip('网格视图'));
      expect(api.calls.length, 1);
      expect(find.byType(VideoWordmark), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'uncertain create locks parameters and reuses original idempotency key',
    (tester) async {
      final api = FakeVideoApi();
      addTearDown(api.close);
      await tester.pumpWidget(wrap(VideoCreatePage(config: config, api: api)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('video-prompt')), '海边日落');
      await tester.ensureVisible(find.byKey(const Key('video-title')));
      await tester.enterText(find.byKey(const Key('video-title')), '我的日落');
      await openVideoImageAddress(tester, 'video-cover-url');
      await tester.enterText(
        find.byKey(const Key('video-cover-url')),
        'https://cdn.example/sunset.jpg',
      );
      await tap(tester, find.byKey(const Key('video-submit')));
      expect(api.keys.length, 1);
      expect(api.drafts.single.title, '我的日落');
      expect(api.drafts.single.coverUrl, 'https://cdn.example/sunset.jpg');
      expect(find.textContaining('同一次提交'), findsOneWidget);
      await tap(tester, find.byKey(const Key('video-submit')));
      expect(api.keys.length, 2);
      expect(api.keys[0], api.keys[1]);
      expect(api.drafts[0], same(api.drafts[1]));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('video-prompt')))
            .enabled,
        isFalse,
      );
    },
  );
  testWidgets('empty prompt cannot submit', (tester) async {
    final api = FakeVideoApi();
    addTearDown(api.close);
    await tester.pumpWidget(wrap(VideoCreatePage(config: config, api: api)));
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('video-submit')));
    expect(api.keys, isEmpty);
  });
  testWidgets(
    'reopening creation within the studio resumes the uncertain submission',
    (tester) async {
      final api = FakeVideoApi();
      addTearDown(api.close);
      await tester.pumpWidget(wrap(VideoCreatePage(config: config, api: api)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('video-prompt')), '海边日落');
      await tap(tester, find.byKey(const Key('video-submit')));
      final originalKey = api.keys.single;
      await tester.pumpWidget(wrap(VideoCreatePage(config: config, api: api)));
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(
        find.byKey(const Key('video-prompt')),
      );
      expect(field.controller!.text, '海边日落');
      expect(field.enabled, isFalse);
      await tap(tester, find.byKey(const Key('video-submit')));
      expect(api.keys.last, originalKey);
    },
  );
  testWidgets('definitive server rejection allows correcting the form', (
    tester,
  ) async {
    final api = FakeVideoApi()
      ..createFailure = const ApiException(422, 'invalid');
    addTearDown(api.close);
    await tester.pumpWidget(wrap(VideoCreatePage(config: config, api: api)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('video-prompt')), '海边日落');
    await tap(tester, find.byKey(const Key('video-submit')));
    expect(api.pendingSubmission, isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('video-prompt')))
          .enabled,
      isTrue,
    );
  });
  testWidgets(
    'metadata titles and unavailable covers render without losing the task',
    (tester) async {
      final api = FakeVideoApi()
        ..title = '湖畔来信'
        ..coverUrl = 'https://cdn.example/missing.jpg';
      addTearDown(api.close);
      await tester.pumpWidget(wrap(VideoStudioPage(config: config, api: api)));
      await tester.pumpAndSettle();
      await tap(tester, find.text('湖畔来信'));
      expect(find.text('湖畔来信'), findsWidgets);
      expect(find.text('封面暂不可用'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('invalid cover input prevents creating a task', (tester) async {
    final api = FakeVideoApi();
    addTearDown(api.close);
    await tester.pumpWidget(wrap(VideoCreatePage(config: config, api: api)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('video-prompt')), '海边日落');
    await openVideoImageAddress(tester, 'video-cover-url');
    await tester.enterText(
      find.byKey(const Key('video-cover-url')),
      'file:///private/photo.jpg',
    );
    await tap(tester, find.byKey(const Key('video-submit')));
    expect(api.keys, isEmpty);
    expect(find.text('请输入有效的 HTTP/HTTPS 封面地址'), findsOneWidget);
  });
  testWidgets('detail deletion requires confirmation and explains permanence', (
    tester,
  ) async {
    final api = FakeVideoApi()..title = '湖畔来信';
    addTearDown(api.close);
    await tester.pumpWidget(
      wrap(VideoDetailPage(config: config, recordId: 1, api: api)),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('video-delete-open')));
    expect(find.text('删除这部影片？'), findsOneWidget);
    expect(find.textContaining('无法在 App 中找回'), findsOneWidget);
    await tester.tap(find.text('保留影片'));
    await tester.pumpAndSettle();
    expect(api.deletes, 0);
    await tap(tester, find.byKey(const Key('video-delete-open')));
    await tester.tap(find.byKey(const Key('video-delete-confirm')));
    await tester.pumpAndSettle();
    expect(api.deletes, 1);
  });

  testWidgets('edit page limits title to 35 and saves only changed metadata', (
    tester,
  ) async {
    final api = FakeVideoApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      wrap(
        VideoEditPage(
          config: config,
          task: task(1, title: '旧标题'),
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('才能更换封面', skipOffstage: false), findsOneWidget);
    await tester.enterText(find.byKey(const Key('video-edit-title')), '新' * 36);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('video-edit-title')))
          .controller!
          .text
          .runes
          .length,
      35,
    );
    await tap(tester, find.byKey(const Key('video-edit-save')));
    expect(api.updates.single.toJson(), {'title': '新' * 35});
  });

  testWidgets('long legacy title does not block a cover-only edit', (
    tester,
  ) async {
    final api = FakeVideoApi();
    addTearDown(api.close);
    final old = VideoTask(
      id: 7,
      status: 'SUCCEEDED',
      storageStatus: 'STORED',
      title: '旧' * 69,
      createdAt: DateTime.utc(2026, 10, 22),
      updatedAt: DateTime.utc(2026, 10, 22),
    );
    await tester.pumpWidget(
      wrap(VideoEditPage(config: config, task: old, api: api)),
    );
    await tester.pumpAndSettle();
    expect(find.text('原标题 69 字'), findsOneWidget);
    await openVideoImageAddress(tester, 'video-edit-cover');
    await tester.enterText(
      find.byKey(const Key('video-edit-cover')),
      'https://cdn.example/new.jpg',
    );
    await tap(tester, find.byKey(const Key('video-edit-save')));
    expect(api.updates.single.toJson(), {
      'cover_url': 'https://cdn.example/new.jpg',
    });
  });

  for (final dark in [false, true]) {
    testWidgets('small screen and large text dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeVideoApi()..title = '一段很长的影片标题' * 20;
      addTearDown(api.close);
      for (final page in [
        VideoStudioPage(config: config, api: api),
        VideoCreatePage(config: config, api: api),
        VideoDetailPage(config: config, recordId: 1, api: api),
        VideoEditPage(
          config: config,
          task: task(1, title: '旧标题'),
          api: api,
        ),
      ]) {
        await tester.pumpWidget(wrap(page, dark: dark, scale: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(
        wrap(
          VideoDetailPage(config: config, recordId: 1, api: api),
          dark: dark,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('video-delete-open')));
      expect(find.text('删除这部影片？'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
