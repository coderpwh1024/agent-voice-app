import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/api/file_api.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:agent_voice_app/features/videos/data/video_api.dart';
import 'package:agent_voice_app/features/videos/data/video_image.dart';
import 'package:agent_voice_app/features/videos/data/video_models.dart';
import 'package:agent_voice_app/features/videos/video_create_page.dart';
import 'package:agent_voice_app/features/videos/video_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

import '../test/support/video_image_fixture.dart';
import 'support/backend_auth.dart';
import 'video_ui_test.dart' as gallery;

class UploadFixturePicker extends VideoImagePicker {
  int selected = 0;
  @override
  Future<PickedVideoImage?> pick() async =>
      PickedVideoImage(videoTestBmp(), 'video-upload-${++selected}.bmp');
}

// Store only public test file IDs, never credentials. Reruns reuse confirmed files.
class VerificationFiles extends FileApi {
  VerificationFiles(super.config, this.manifest);
  final receipts = <UploadedFileMetadata>[];
  final File manifest;
  int newUploads = 0;
  @override
  Future<UploadedFileMetadata> upload({
    required Uint8List bytes,
    required String name,
    required String contentType,
  }) async {
    final ids = await manifest.exists()
        ? Map<String, dynamic>.from(jsonDecode(await manifest.readAsString()))
        : <String, dynamic>{};
    final saved = ids[name];
    debugPrint('UPLOAD VERIFY: upload request $name cached=${saved is int}');
    final result = saved is int
        ? await get(saved)
        : await super.upload(
            bytes: bytes,
            name: name,
            contentType: contentType,
          );
    if (saved == null) newUploads++;
    ids[name] = result.id;
    await manifest.writeAsString(jsonEncode(ids));
    debugPrint('UPLOAD VERIFY: file ${result.id} confirmed');
    receipts.add(result);
    return result;
  }
}

class VerificationVideos extends VideoApi {
  VerificationVideos(super.config);
  VideoDraft? submitted;
  VideoTask? created;
  int calls = 0;
  Object? createError;
  @override
  Future<VideoTask> create(VideoDraft draft, String key) async {
    calls++;
    submitted = draft;
    try {
      return created = await super.create(
        draft,
        'app-video-upload-usb-20261024-v1',
      );
    } catch (e) {
      createError = e;
      rethrow;
    }
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: .3);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: .3);
  await tester.pumpAndSettle();
}

Future<void> select(WidgetTester tester, String label, String value) async {
  final finder = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        w.key.toString().contains('$label:'),
  );
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'USB: upload images, query receipts, submit their URLs and inspect UI',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      debugPrint('UPLOAD VERIFY: reading session');
      final AppConfig config = await backendTestConfig();
      final support = await const MethodChannel('agent_voice/audio')
          .invokeMethod<String>('applicationSupportDirectory');
      if (support == null) throw StateError('无法读取测试清单目录');
      final manifest = File(
        '$support/video-upload-verification-v1-${Uri.encodeComponent(config.userId)}.json',
      );
      const seed = String.fromEnvironment('VIDEO_UPLOAD_FILE_IDS');
      if (!await manifest.exists() && seed.isNotEmpty) {
        final ids = seed.split(',').map(int.parse).toList();
        expect(ids.length, 2);
        await manifest.writeAsString(
          jsonEncode({
            'video-upload-1.bmp': ids[0],
            'video-upload-2.bmp': ids[1],
          }),
        );
      }
      final files = VerificationFiles(config, manifest);
      final videos = VerificationVideos(config);
      final picker = UploadFixturePicker();
      addTearDown(files.close);
      addTearDown(videos.close);
      Widget wrap(Widget page, {bool dark = false, double scale = 1}) =>
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: page,
          );
      await tester.pumpWidget(
        wrap(
          VideoCreatePage(
            config: config,
            api: videos,
            fileApi: files,
            imagePicker: picker,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await select(tester, '生成模型', '万相 3.0 · 标准版');
      await binding.takeScreenshot('upload-create');
      debugPrint('UPLOAD VERIFY: selected Wan');
      await select(tester, '清晰度', '480P');
      await reveal(tester, find.byType(Slider));
      await tester.tapAt(
        tester.getTopLeft(find.byType(Slider)) +
            Offset(20, tester.getSize(find.byType(Slider)).height / 2),
      );
      await tester.pumpAndSettle();
      for (final key in ['video-first-frame', 'video-last-frame']) {
        await reveal(tester, find.byKey(Key('$key-pick')));
        await binding.takeScreenshot('$key-before-pick');
        await tester.tap(find.byKey(Key('$key-pick')));
        await tester.pump(const Duration(milliseconds: 200));
        debugPrint('UPLOAD VERIFY: picker opened ${picker.selected}');
        final expected = key == 'video-first-frame' ? 1 : 2;
        expect(picker.selected, expected, reason: '选择图片按钮必须实际触发');
        for (var n = 0; n < 360 && files.receipts.length < expected; n++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        await binding.takeScreenshot('$key-after-pick');
        debugPrint('UPLOAD VERIFY: confirmed files ${files.receipts.length}');
        expect(files.receipts.length, expected, reason: '实际图片上传必须完成');
        await tester.pumpAndSettle();
        expect(videos.calls, 0, reason: '上传不能隐式创建生成任务');
        await binding.takeScreenshot('$key-uploaded');
        final metadata = await files.get(files.receipts.last.id);
        expect(metadata.url, files.receipts.last.url);
        final http = HttpClient();
        try {
          final r = await (await http.getUrl(Uri.parse(metadata.url))).close();
          expect(r.statusCode, 200);
          await r.drain<void>();
        } finally {
          http.close(force: true);
        }
      }
      await reveal(tester, find.byKey(const Key('video-submit')));
      await tester.tap(find.byKey(const Key('video-submit')));
      for (
        var n = 0;
        n < 360 && videos.created == null && videos.createError == null;
        n++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(videos.createError, isNull);
      expect(videos.created, isNotNull);
      expect(videos.submitted!.firstFrameUrl, files.receipts[0].url);
      expect(videos.submitted!.lastFrameUrl, files.receipts[1].url);
      expect(videos.submitted!.prompt, isEmpty);
      expect(videos.submitted!.duration, 2);
      expect(videos.submitted!.resolution, '480P');
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(VideoDetailPage), findsOneWidget);
      await binding.takeScreenshot('upload-submitted-detail');
      await tester.pumpWidget(const SizedBox.shrink());
      var latest = await videos.detail(videos.created!.id);
      for (var n = 0; n < 60 && latest.shouldPoll; n++) {
        await Future<void>.delayed(const Duration(seconds: 10));
        latest = await videos.detail(latest.id);
      }
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'base_url': config.baseUrl,
        'real_file_upload_and_lookup': true,
        'public_image_fetch': true,
        'file_ids': files.receipts.map((x) => x.id).toList(),
        'new_file_uploads': files.newUploads,
        'uploaded_urls_submitted': true,
        'record_id': latest.id,
        'generation_status': latest.status,
        'storage_status': latest.storageStatus,
        'error_code': latest.errorCode,
        'wan_generated': latest.playableUri != null,
      });

      expect(latest.playableUri, isNotNull, reason: '万相生成与转存必须成功');
      if (latest.playableUri != null) {
        await tester.pumpWidget(
          wrap(
            VideoDetailPage(
              config: config,
              recordId: latest.id,
              initialTask: latest,
              api: videos,
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.byTooltip('播放影片').first);
        for (
          var i = 0;
          i < 90 && find.byType(VideoPlayer).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(find.byType(VideoPlayer), findsOneWidget);
        final player = tester
            .widget<VideoPlayer>(find.byType(VideoPlayer))
            .controller;
        for (
          var i = 0;
          i < 60 &&
              player.value.position == Duration.zero &&
              !player.value.hasError;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(player.value.position, greaterThan(Duration.zero));
        expect(player.value.hasError, isFalse);
        binding.reportData!['new_wan_native_playback'] = true;
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot('upload-generated-playing');
        await player.pause();
        await tester.pumpWidget(const SizedBox.shrink());
      }
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          wrap(
            VideoCreatePage(
              config: config,
              api: videos,
              fileApi: files,
              imagePicker: picker,
            ),
            dark: dark,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        await select(tester, '生成模型', '万相 3.0 · 高速版');
        await reveal(tester, find.byKey(const Key('video-first-frame-pick')));
        await binding.takeScreenshot('upload-large-dark-$dark');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 16)),
  );
  gallery.main();
}
