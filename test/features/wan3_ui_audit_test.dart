import 'dart:io';
import 'dart:ui' as ui;

import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:agent_voice_app/features/videos/data/video_models.dart';
import 'package:agent_voice_app/features/videos/video_create_page.dart';
import 'package:agent_voice_app/features/videos/video_detail_page.dart';
import 'package:agent_voice_app/features/videos/video_studio_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'videos_page_test.dart' show config, FakeVideoApi, tap;
import 'wan3_video_page_test.dart' show chooseModel;
import 'video_image_upload_test.dart'
    show RecordingFiles, FixturePicker, pickImage;

import 'package:agent_voice_app/core/api/api_client.dart';

class AuditApi extends FakeVideoApi {
  bool empty = false;
  @override
  Future<VideoTaskPage> list({
    int page = 1,
    String? status,
    String? storageStatus,
    String? model,
  }) async {
    if (empty) {
      return const VideoTaskPage(items: [], total: 0, page: 1, totalPages: 0);
    }
    return super.list(
      page: page,
      status: status,
      storageStatus: storageStatus,
      model: model,
    );
  }

  @override
  Future<VideoTask> detail(int id) async => VideoTask(
    id: id,
    model: 'wan3.0-video-prime',
    status: 'FAILED',
    storageStatus: 'NOT_READY',
    title: '晨光穿过绿叶，镜头缓缓前行。这是一段用于检查长标题完整展示的画面。',
    firstFrameUrl: 'https://cdn.example/${'long-image-path/' * 8}first.png',
    lastFrameUrl: 'https://cdn.example/last.png',
    errorCode: 'GENERATION_FAILED',
    createdAt: DateTime.utc(2026, 10, 24),
    updatedAt: DateTime.utc(2026, 10, 24),
  );
}

void main() {
  const directory = String.fromEnvironment('WAN_UI_AUDIT_DIR');
  const bodyFont = String.fromEnvironment('UI_AUDIT_PREVIEW_FONT');
  const iconFont = String.fromEnvironment('UI_AUDIT_ICON_FONT');
  testWidgets(
    'video UI visual audit with real fonts, two themes and scaled forms',
    (tester) async {
      await tester.runAsync(() async {
        for (final entry in {
          'AuditBody': bodyFont,
          'Ahem': bodyFont,
          'Roboto': bodyFont,
          'Arial': bodyFont,
          'StudioSerif': 'assets/fonts/StudioSerif-Regular.ttf',
          'MaterialIcons': iconFont,
        }.entries) {
          final loader = FontLoader(entry.key)
            ..addFont(
              File(entry.value)
                  .readAsBytes()
                  .then((b) => ByteData.sublistView(b)),
            );
          await loader.load();
        }
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = AuditApi();
      final files = RecordingFiles();
      addTearDown(files.close);
      addTearDown(api.close);
      const boundaryKey = Key('wan-audit');
      Future<void> mount(
        Widget page, {
        bool dark = false,
        double scale = 1,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(
              dark ? Brightness.dark : Brightness.light,
              baseTheme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
                fontFamily: 'AuditBody',
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(key: boundaryKey, child: page),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> shot(String name) async {
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundaryKey),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      for (final dark in [false, true]) {
        await mount(
          VideoStudioPage(config: config, api: api),
          dark: dark,
        );
        await shot('studio-$dark');
        await tester.scrollUntilVisible(
          find.text('影片 #0001'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await shot('collection-$dark');
        await mount(
          VideoCreatePage(
            config: config,
            api: api,
            fileApi: files,
            imagePicker: FixturePicker(),
          ),
          dark: dark,
        );
        await chooseModel(tester, '万相 3.0 · 标准版');
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, 1000),
        );
        await tester.pumpAndSettle();
        await shot('create-$dark');
        await Scrollable.ensureVisible(
          tester.element(find.byKey(const Key('video-first-frame-pick'))),
          alignment: .2,
        );
        await tester.pumpAndSettle();
        await shot('frames-$dark');
        files.failure = dark ? const ApiException(503, 'offline') : null;
        await pickImage(tester, 'video-first-frame');
        await Scrollable.ensureVisible(
          tester.element(find.byKey(const Key('video-first-frame-pick'))),
          alignment: .4,
        );
        await tester.pumpAndSettle();
        await shot('upload-state-$dark');

        await tap(tester, find.text('更多设置'));
        await shot('settings-$dark');
        await mount(
          VideoDetailPage(config: config, recordId: 42, api: api),
          dark: dark,
        );
        await shot('detail-$dark');
        await tester.scrollUntilVisible(
          find.text('生成素材'),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await shot('detail-inputs-$dark');
        api.empty = true;
        await mount(
          VideoStudioPage(config: config, api: api),
          dark: dark,
        );
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pumpAndSettle();
        await shot('empty-$dark');
        api.empty = false;
        tester.view.physicalSize = const Size(320, 700);
        await mount(
          VideoCreatePage(
            config: config,
            api: api,
            fileApi: files,
            imagePicker: FixturePicker(),
          ),
          dark: dark,
          scale: 2,
        );
        await chooseModel(tester, '万相 3.0 · 高速版');
        await shot('large-model-$dark');
        await Scrollable.ensureVisible(
          tester.element(find.byKey(const Key('video-first-frame-pick'))),
          alignment: .15,
        );
        await tester.pumpAndSettle();
        await shot('large-frames-$dark');
        await tap(tester, find.byKey(const Key('video-submit')));
        await shot('large-error-$dark');
        tester.view.physicalSize = const Size(390, 844);
      }
    },
    skip: directory.isEmpty,
  );
}
