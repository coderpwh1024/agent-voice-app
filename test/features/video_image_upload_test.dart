import 'dart:async';
import 'dart:typed_data';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/api/file_api.dart';
import 'package:agent_voice_app/features/videos/data/video_image.dart';
import 'package:agent_voice_app/features/videos/data/video_models.dart';
import 'package:agent_voice_app/features/videos/video_create_page.dart';
import 'package:agent_voice_app/features/videos/video_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/video_image_fixture.dart';
import 'videos_page_test.dart' show config, FakeVideoApi, wrap, tap;
import 'wan3_video_page_test.dart' show chooseModel;

class FixturePicker extends VideoImagePicker {
  PickedVideoImage? next = PickedVideoImage(videoTestBmp(), '画面.bmp');
  @override
  Future<PickedVideoImage?> pick() async => next;
}

class RecordingFiles extends FileApi {
  RecordingFiles() : super(config);
  final names = <String>[];
  Object? failure;
  Completer<UploadedFileMetadata>? gate;
  @override
  Future<UploadedFileMetadata> upload({
    required Uint8List bytes,
    required String name,
    required String contentType,
  }) async {
    names.add(name);
    if (failure != null) throw failure!;
    if (gate != null) return gate!.future;
    return result(names.length);
  }

  UploadedFileMetadata result(int id) => UploadedFileMetadata(
    id: id,
    url: 'https://cdn.example/image-$id.bmp',
    name: '画面.bmp',
    contentType: 'image/bmp',
    sizeBytes: videoTestBmp().length,
    uploadedAt: DateTime.utc(2026, 10, 24),
  );
}

Future<void> pickImage(WidgetTester tester, String key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final button = find.byKey(Key('$key-pick'));
  await Scrollable.ensureVisible(tester.element(button), alignment: .4);
  await tester.pumpAndSettle();
  await tester.tap(button);
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  testWidgets('cover upload finishes before edit PATCH and uses returned URL', (
    tester,
  ) async {
    final videos = FakeVideoApi();
    final files = RecordingFiles()..gate = Completer<UploadedFileMetadata>();
    addTearDown(videos.close);
    addTearDown(files.close);
    await tester.pumpWidget(
      wrap(
        VideoEditPage(
          config: config,
          task: VideoTask(
            id: 9,
            status: 'SUCCEEDED',
            storageStatus: 'STORED',
            title: '旧标题',
            coverUrl: 'https://cdn.example/old.jpg',
            createdAt: DateTime.utc(2026, 10, 22),
            updatedAt: DateTime.utc(2026, 10, 22),
          ),
          api: videos,
          fileApi: files,
          imagePicker: FixturePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('video-edit-title')), '新标题');
    await pickImage(tester, 'video-edit-cover');
    expect(files.names, ['画面.bmp']);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('video-edit-save')))
          .onPressed,
      isNull,
    );
    expect(videos.updates, isEmpty);
    files.gate!.complete(files.result(1));
    await tester.pumpAndSettle();
    expect(find.text('图片已上传'), findsOneWidget);
    await tap(tester, find.byKey(const Key('video-edit-save')));
    expect(videos.updates.single.toJson(), {
      'title': '新标题',
      'cover_url': 'https://cdn.example/image-1.bmp',
    });
    expect(files.names.length, 1);
  });
  testWidgets(
    'generation waits for upload and retries reuse uploaded frame URLs',
    (tester) async {
      final videos = FakeVideoApi();
      final files = RecordingFiles()..gate = Completer<UploadedFileMetadata>();
      final picker = FixturePicker();
      addTearDown(videos.close);
      addTearDown(files.close);
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
      await chooseModel(tester, '万相 3.0 · 标准版');
      await pickImage(tester, 'video-first-frame');
      expect(files.names, ['画面.bmp']);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('video-submit')))
            .onPressed,
        isNull,
      );
      expect(videos.keys, isEmpty);
      files.gate!.complete(files.result(1));
      await tester.pumpAndSettle();
      expect(find.text('图片已上传'), findsOneWidget);
      await tap(tester, find.byKey(const Key('video-submit')));
      expect(
        videos.drafts.single.firstFrameUrl,
        'https://cdn.example/image-1.bmp',
      );
      expect(videos.drafts.single.coverUrl, isEmpty);
      expect(videos.drafts.single.prompt, isEmpty);
      await tap(tester, find.byKey(const Key('video-submit')));
      expect(videos.keys[0], videos.keys[1]);
      expect(files.names.length, 1);
      expect(videos.drafts[0], same(videos.drafts[1]));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed upload blocks generation and can retry or be removed', (
    tester,
  ) async {
    final videos = FakeVideoApi();
    final files = RecordingFiles()..failure = const ApiException(502, 'failed');
    addTearDown(videos.close);
    addTearDown(files.close);
    await tester.pumpWidget(
      wrap(
        VideoCreatePage(
          config: config,
          api: videos,
          fileApi: files,
          imagePicker: FixturePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await chooseModel(tester, '万相 3.0 · 高速版');
    await tester.enterText(find.byKey(const Key('video-prompt')), '海边日落');
    await pickImage(tester, 'video-first-frame');
    await tap(tester, find.byKey(const Key('video-submit')));
    expect(videos.keys, isEmpty);
    expect(find.text('请先完成图片上传，或移除未上传的图片'), findsOneWidget);
    files.failure = null;
    await tap(tester, find.byKey(const Key('video-first-frame-retry')));
    expect(files.names.length, 2);
    await tap(tester, find.byKey(const Key('video-first-frame-remove')));
    await tap(tester, find.byKey(const Key('video-submit')));
    expect(videos.drafts.single.firstFrameUrl, isEmpty);
  });
  testWidgets(
    'tail still requires first frame and cancelling picker makes no upload',
    (tester) async {
      final videos = FakeVideoApi();
      final files = RecordingFiles();
      final picker = FixturePicker();
      addTearDown(videos.close);
      addTearDown(files.close);
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
      await chooseModel(tester, '万相 3.0 · 标准版');
      await tester.enterText(find.byKey(const Key('video-prompt')), '海边日落');
      picker.next = null;
      await pickImage(tester, 'video-first-frame');
      expect(files.names, isEmpty);
      picker.next = PickedVideoImage(videoTestBmp(), 'tail.bmp');
      await pickImage(tester, 'video-last-frame');
      await tap(tester, find.byKey(const Key('video-submit')));
      expect(videos.keys, isEmpty);
      expect(find.text('提供尾帧时，请同时填写首帧图片地址'), findsOneWidget);
    },
  );
  test(
    'image input validates content, dimensions, alpha, name and byte limit',
    () async {
      final valid = await VideoImageFile.validate(
        PickedVideoImage(videoTestBmp(), '画面.bmp'),
      );
      expect(valid.contentType, 'image/bmp');
      for (final image in [
        PickedVideoImage(Uint8List(0), 'x.bmp'),
        PickedVideoImage(Uint8List(FileApi.maxImageBytes + 1), 'x.bmp'),
        PickedVideoImage(
          Uint8List.fromList([71, 73, 70, 56, 57, 97]),
          'fake.jpg',
        ),
        PickedVideoImage(videoTestBmp(width: 239), 'small.bmp'),
        PickedVideoImage(videoTestBmp(width: 2000), 'wide.bmp'),
        PickedVideoImage(videoTestBmp(), 'bad\nname.bmp'),
        PickedVideoImage(videoTestBmp(), 'a' * 256),
        PickedVideoImage(
          Uint8List(26)
            ..[0] = 137
            ..[1] = 80
            ..[2] = 78
            ..[3] = 71
            ..[25] = 6,
          'alpha.png',
        ),
      ]) {
        await expectLater(
          VideoImageFile.validate(image),
          throwsFormatException,
        );
      }
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'photo upload, error and removal are usable at 320px/200% dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final videos = FakeVideoApi();
        final files = RecordingFiles()
          ..failure = const ApiException(503, 'offline');
        addTearDown(videos.close);
        addTearDown(files.close);
        await tester.pumpWidget(
          wrap(
            VideoCreatePage(
              config: config,
              api: videos,
              fileApi: files,
              imagePicker: FixturePicker(),
            ),
            dark: dark,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        await chooseModel(tester, '万相 3.0 · 标准版');
        await pickImage(tester, 'video-first-frame');
        await tap(tester, find.byKey(const Key('video-first-frame-remove')));
        for (var i = 0; i < 24; i++) {
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
      },
    );
  }
}
