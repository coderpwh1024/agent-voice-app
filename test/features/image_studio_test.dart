import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/api/file_api.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:agent_voice_app/features/images/data/image_api.dart';
import 'package:agent_voice_app/features/images/data/image_asset_picker.dart';
import 'package:agent_voice_app/features/images/data/image_models.dart';
import 'package:agent_voice_app/features/images/image_create_page.dart';
import 'package:agent_voice_app/features/images/image_detail_page.dart';
import 'package:agent_voice_app/features/images/image_studio_page.dart';
import 'package:agent_voice_app/features/images/image_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/video_image_fixture.dart';

const config = AppConfig(
  baseUrl: 'http://127.0.0.1:8000',
  accessToken: 'fixture',
  userId: '1',
);

class _ImageApi extends ImageApi {
  _ImageApi() : super(config);

  final submissions = <ImageSubmission>[];
  final pages = <int>[];
  var current = const ImageTask(
    id: 89,
    title: '微光',
    status: ImageTaskStatus.queued,
  );
  bool deleted = false;

  @override
  Future<ImageTask> submit(ImageSubmission submission) async {
    submissions.add(submission);
    if (submissions.length == 1) throw const ApiException(504, 'timeout');
    return current;
  }

  @override
  Future<ImageTask> detail(int id) async => current;

  @override
  Future<ImageTaskPage> list({int page = 1}) async {
    pages.add(page);
    return ImageTaskPage(deleted ? [] : [current], page: page, totalPages: 1);
  }

  @override
  Future<ImageTask> rename(int id, String title) async =>
      current = ImageTask(id: id, title: title, status: current.status);

  @override
  Future<void> delete(int id) async {
    deleted = true;
  }
}

class _Files extends FileApi {
  _Files() : super(config);

  final response = Completer<UploadedFileMetadata>();
  var uploads = 0;

  @override
  Future<UploadedFileMetadata> upload({
    required Uint8List bytes,
    required String name,
    required String contentType,
  }) async {
    uploads++;
    return response.future;
  }
}

class _Picker extends StudioImagePicker {
  @override
  Future<StudioImageAsset> pick() async =>
      StudioImageAsset(Uint8List(10), '选图.png', 'image/png');
}

Widget wrap(Widget page, {double textScale = 1, bool dark = false}) =>
    MaterialApp(
      theme: AppTheme.build(dark ? Brightness.dark : Brightness.light),
      home: page,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
    );

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final (width, height) in [
    (400, 224),
    (224, 400),
    (320, 320),
    (100, 600),
  ]) {
    testWidgets('image $width×$height keeps its ratio on open and zoom', (
      tester,
    ) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final api = _ImageApi();
        final files = _Files();
        addTearDown(api.close);
        addTearDown(files.close);
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var requests = 0;
        final server = (await tester.runAsync(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            requests++;
            expect(
              request.headers.value(HttpHeaders.authorizationHeader),
              isNull,
            );
            request.response.add(videoTestBmp(width: width, height: height));
            await request.response.close();
          });
          return server;
        }))!;
        addTearDown(() => server.close(force: true));
        api.current = ImageTask(
          id: 89,
          title: '山间日光',
          status: ImageTaskStatus.succeeded,
          imageUri: Uri.http('127.0.0.1:${server.port}', '/art'),
        );

        await tester.runAsync(() async {
          await tester.pumpWidget(
            wrap(
              ImageStudioPage(config: config, api: api, files: files),
              textScale: 2,
              dark: height > width,
            ),
          );
          await tester.pumpAndSettle();
        });
        final art = find.byType(Image);
        await tester.pumpAndSettle();
        await _waitForImage(tester, art);
        await tap(tester, find.text('山间日光'));
        expect(find.byType(ImageDetailPage), findsOneWidget);
        await _waitForImage(tester, art);
        final size = tester.getSize(find.byType(RawImage));
        expect(size.aspectRatio, closeTo(width / height, .01));
        expect(size.height, lessThan(440));
        await tap(tester, find.text('查看原图'));
        expect(find.byType(InteractiveViewer), findsOneWidget);
        await _waitForImage(tester, art);
        expect(requests, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, _RealHttp());
    });
  }

  testWidgets('slow image shows loading and retries a failed download', (
    tester,
  ) async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final api = _ImageApi();
      final files = _Files();
      addTearDown(api.close);
      addTearDown(files.close);
      final release = (await tester.runAsync(() async => Completer<void>()))!;
      var requests = 0;
      final server = (await tester.runAsync(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          if (++requests == 1) {
            await release.future;
            request.response.statusCode = 503;
          } else {
            request.response.add(videoTestBmp());
          }
          await request.response.close();
        });
        return server;
      }))!;
      addTearDown(() => server.close(force: true));
      api.current = ImageTask(
        id: 89,
        status: ImageTaskStatus.succeeded,
        imageUri: Uri.http('127.0.0.1:${server.port}', '/slow-art'),
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(
          wrap(ImageDetailPage(config: config, id: 89, api: api, files: files)),
        );
        await tester.pumpAndSettle();
      });
      await tester.pumpAndSettle();
      expect(find.text('正在加载图片…'), findsOneWidget);
      final retry = find.text('重新加载图片');
      await tester.runAsync(() async {
        release.complete();
        await precacheImage(
          tester.widget<Image>(find.byType(Image)).image,
          tester.element(find.byType(ImagePreview)),
          onError: (_, _) {},
        ).timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      expect(find.text('图片暂时无法加载'), findsOneWidget);
      await tester.runAsync(() => tap(tester, retry));
      await _waitForImage(tester, find.byType(Image));
      expect(requests, 2);
      expect(retry, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }, _RealHttp());
  });

  testWidgets(
    'photo upload completes before creation and retries reuse its ID',
    (tester) async {
      final api = _ImageApi();
      final files = _Files();
      addTearDown(api.close);
      addTearDown(files.close);
      await tester.pumpWidget(
        wrap(ImageCreatePage(api: api, files: files, picker: _Picker())),
      );
      final prompt = find.byKey(const Key('image-prompt'));
      final choose = find.byKey(const Key('image-choose-asset'));
      final submit = find.byKey(const Key('image-submit'));
      await tester.enterText(prompt, '微光');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pump();
      expect(files.uploads, 1);
      expect(api.submissions, isEmpty);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      files.response.complete(
        UploadedFileMetadata(
          id: 8,
          url: 'https://storage.example/source.png',
          name: '选图.png',
          contentType: 'image/png',
          sizeBytes: 10,
          uploadedAt: DateTime.utc(2026),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).imageProvider, isA<NetworkImage>());
      await tester.scrollUntilVisible(
        submit,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, submit);
      expect(find.text('确认提交'), findsOneWidget);
      await tap(tester, submit);
      expect(files.uploads, 1);
      expect(
        api.submissions.map((submission) => submission.key).toSet(),
        hasLength(1),
      );
      expect(api.submissions.last.draft.sourceFileIds, [8]);
    },
  );

  testWidgets(
    'studio refreshes pending records and retains small-screen layout',
    (tester) async {
      final api = _ImageApi();
      final files = _Files();
      addTearDown(api.close);
      addTearDown(files.close);
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        wrap(
          ImageStudioPage(config: config, api: api, files: files),
          textScale: 2,
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('图像工作室'), findsOneWidget);
      expect(find.text('排队中'), findsOneWidget);
      api.current = const ImageTask(
        id: 89,
        title: '微光',
        status: ImageTaskStatus.failed,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(api.pages, [1, 1]);
      expect(find.text('生成失败'), findsOneWidget);
      await tap(tester, find.text('微光'));
      expect(find.byType(ImageDetailPage), findsOneWidget);
      await tap(tester, find.byTooltip('图像操作'));
      await tap(tester, find.text('修改标题'));
      await tester.enterText(find.byType(TextFormField), '再见微光');
      await tap(tester, find.text('保存'));
      expect(find.text('再见微光'), findsOneWidget);
      await tap(tester, find.byTooltip('图像操作'));
      await tap(tester, find.text('删除图像'));
      await tap(tester, find.text('删除'));
      expect(find.byType(ImageStudioPage), findsOneWidget);
      expect(find.text('再见微光'), findsNothing);
      expect(api.deleted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

class _RealHttp extends HttpOverrides {}

Future<void> _waitForImage(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await precacheImage(
      tester.widget<Image>(finder).image,
      tester.element(finder),
    ).timeout(const Duration(seconds: 5));
  });
  await tester.pumpAndSettle();
  expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
}
