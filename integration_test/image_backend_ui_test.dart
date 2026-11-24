import 'dart:ui' as ui;

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:agent_voice_app/features/images/data/image_api.dart';
import 'package:agent_voice_app/features/images/data/image_models.dart';
import 'package:agent_voice_app/features/images/image_studio_page.dart';
import 'package:agent_voice_app/features/images/image_widgets.dart';
import 'package:agent_voice_app/features/voice_session/voice_home_page.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/backend_auth.dart';

class VoicePreview extends VoiceSessionController {
  VoicePreview({required super.config});

  @override
  bool get wakeWordEnabled => true;

  @override
  Future<void> disableWakeWord() async {}
}

class _GalleryPreviewApi extends ImageApi {
  _GalleryPreviewApi(super.config);

  bool unavailable = true;

  @override
  Future<ImageTaskPage> list({int page = 1}) async {
    if (unavailable) throw const ApiException(503, 'fixture');
    return const ImageTaskPage([], page: 1, totalPages: 0);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('USB reads a real image and opens independent creation routes', (
    tester,
  ) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final config = await backendTestConfig();
    final api = AgentApiClient(config);
    final images = ImageApi(config, client: api);
    final voice = VoicePreview(config: config);
    addTearDown(api.close);
    addTearDown(voice.dispose);
    final user = await api.currentUser();
    final page = await images.list();
    const targetId = int.fromEnvironment('IMAGE_TEST_ID');
    final task = page.items.firstWhere(
      (item) =>
          item.resultUri != null && (targetId == 0 || item.id == targetId),
    );
    final detail = await images.detail(task.id);
    expect(detail.resultUri, isNotNull);
    final loops = await images.loopHistory();
    expect(loops.items, isNotEmpty, reason: '测试账号需要有可见的 LOOP 历史');
    final history = loops.items.first;
    final loopDetail = await images.loopHistoryDetail(history.loop.rootId);
    expect(loopDetail.root.id, history.root.id);
    expect(loopDetail.loop.usedEdits, greaterThan(0));
    expect(loopDetail.loop.versions, isNotEmpty);
    final screenshotKey = GlobalKey();
    Future<void> screenshot(String name) async {
      await tester.pumpAndSettle();
      final render =
          screenshotKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final picture = await render.toImage(pixelRatio: 1.4);
      try {
        final bytes = (await picture.toByteData(
          format: ui.ImageByteFormat.png,
        ))!;
        final data = binding.reportData ??= <String, dynamic>{};
        final screenshots = data.putIfAbsent(
          'screenshots',
          () => <Map<String, Object>>[],
        ) as List<Map<String, Object>>;
        screenshots.add({
          'screenshotName': name,
          'bytes': bytes.buffer.asUint8List(),
        });
      } finally {
        picture.dispose();
      }
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: VoiceHomePage(
            controller: voice,
            user: user,
            onOpenProfile: (_) async {},
            onOpenSettings: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await screenshot('image-entry');

    final direct = find.byTooltip('图像工作室');
    if (direct.evaluate().isNotEmpty) {
      await tester.tap(direct);
    } else {
      await tester.tap(find.byTooltip('创作工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('图像工作室'));
    }
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(task.id)),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final galleryTile = find.byKey(ValueKey(task.id));
    await expectRenderedImage(tester, galleryTile);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await screenshot('image-gallery');
    await tester.scrollUntilVisible(
      galleryTile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(galleryTile);
    await tester.pumpAndSettle();
    expect(find.text('图像详情'), findsOneWidget);

    await expectRenderedImage(tester, find.byType(ImagePreview).first);
    await screenshot('image-detail');

    await tester.scrollUntilVisible(
      find.text('继续编辑'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('修改描述'), findsOneWidget);
    await expectRenderedImage(tester, find.byType(ImagePreview).first);
    await screenshot('image-edit');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('新建图像'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('新建图像'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('image-choose-asset')), findsOneWidget);
    await screenshot('image-create');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('我的作品'), findsOneWidget);
    expect(find.text('LOOP 历史'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    final loopRootTile = find.byKey(ValueKey(history.root.id));
    await tester.scrollUntilVisible(
      loopRootTile,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(loopRootTile);
    await tester.pumpAndSettle();
    final openLoop = find.text('LOOP 编辑');
    await tester.scrollUntilVisible(
      openLoop,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(openLoop);
    await tester.pumpAndSettle();
    expect(find.text('LOOP 详情'), findsOneWidget);
    expect(find.text(loopDetail.loop.status.label), findsOneWidget);
    final artwork = find.byType(ImageArtwork);
    final preview = loopDetail.previewImage;
    if (loopDetail.resultUriFor(preview) != null) {
      await expectRenderedImage(tester, artwork);
      expect(tester.widget<ImageArtwork>(artwork).image.id, preview.id);
    }
    await screenshot('image-loop-detail');

    final sourceId = preview.id == history.root.id
        ? null
        : preview.sourceImageId;
    if (sourceId != null) {
      final source = [
        history.root,
        ...loopDetail.loop.versions,
      ].where((version) => version.id == sourceId).firstOrNull;
      if (source?.resultUri != null) {
        final sourceLink = find.widgetWithText(TextButton, '编辑底图 #$sourceId');
        await tester.scrollUntilVisible(
          sourceLink,
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(sourceLink);
        await tester.pumpAndSettle();
        await expectRenderedImage(tester, artwork);
        expect(tester.widget<ImageArtwork>(artwork).image.id, sourceId);
        await screenshot('image-loop-edit-source');
      }
    }

    final original = find.widgetWithText(
      ChoiceChip,
      '原始图像 #${history.root.id}',
    );
    expect(original, findsOneWidget);
    await tester.tap(original);
    await tester.pumpAndSettle();
    if (loopDetail.resultUriFor(loopDetail.root) != null) {
      await expectRenderedImage(tester, artwork);
      expect(tester.widget<ImageArtwork>(artwork).image.id, history.root.id);
    }
    await screenshot('image-loop-original');
    if (preview.id != history.root.id) {
      await tester.tap(
        find.text(loopDetail.loop.acceptedId == preview.id ? '定稿预览' : '历史预览'),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ImageArtwork>(artwork).image.id, preview.id);
    }

    final timeline = find.text('版本记录');
    await tester.scrollUntilVisible(
      timeline,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await screenshot('image-loop-versions');
    final originalRow = find.text('初稿');
    await tester.scrollUntilVisible(
      originalRow,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(originalRow.last);
    await tester.pumpAndSettle();
    if (history.root.resultUri != null) {
      expect(
        tester.widget<ImageArtwork>(find.byType(ImageArtwork)).image.id,
        history.root.id,
      );
    }

    if (loopDetail.loop.canEdit && history.root.resultUri != null) {
      final edit = find.text('继续编辑');
      await tester.scrollUntilVisible(
        edit,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.text('LOOP'), findsOneWidget);
      expect(find.text('编辑底图 · #${history.root.id}'), findsOneWidget);
      await screenshot('image-loop-edit');
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    if (loopDetail.loop.canClose) {
      await tester.tap(find.byTooltip('LOOP 操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('结束 LOOP'));
      await screenshot('image-loop-confirmation');
      expect(find.text('结束这次 LOOP？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    }

    final previewApi = _GalleryPreviewApi(config);
    addTearDown(previewApi.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        builder: (context, child) => Center(
          child: SizedBox(
            width: 320,
            height: MediaQuery.sizeOf(context).height,
            child: RepaintBoundary(
              key: screenshotKey,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
            ),
          ),
        ),
        home: ImageStudioPage(config: config, api: previewApi),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LOOP 历史'), findsNothing);
    await screenshot('image-gallery-error-dark-large');
    expect(find.text('图像服务暂不可用，请稍后重试'), findsOneWidget);
    previewApi.unavailable = false;
    await tester.tap(find.text('重试'));
    await screenshot('image-gallery-empty-dark-large');
    expect(find.text('还没有图像作品'), findsOneWidget);

    binding.reportData = {
      ...?binding.reportData,
      'loop_total': loops.total,
      'loop_used_edits': loopDetail.loop.usedEdits,
      'loop_visible_versions': loopDetail.loop.versions.length,
      'loop_status': loopDetail.loop.status.value,
    };
    expect(tester.takeException(), isNull);
  });
}

Future<void> expectRenderedImage(WidgetTester tester, Finder parent) async {
  final imageFinder = find.descendant(of: parent, matching: find.byType(Image));
  expect(imageFinder, findsOneWidget);
  final provider = tester.widget<Image>(imageFinder).image;
  Object? loadError;
  await precacheImage(
    provider,
    tester.element(imageFinder),
    onError: (error, _) => loadError = error,
  );
  expect(loadError, isNull);
  await tester.pumpAndSettle();
  final rawImage = find.descendant(
    of: imageFinder,
    matching: find.byType(RawImage),
  );
  expect(tester.renderObject<RenderImage>(rawImage).image, isNotNull);
}
