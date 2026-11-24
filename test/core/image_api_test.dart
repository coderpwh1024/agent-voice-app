import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/api/execution_models.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/images/data/image_api.dart';
import 'package:agent_voice_app/features/images/data/image_loop_models.dart';
import 'package:agent_voice_app/features/images/data/image_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('image CRUD and edits use the authenticated REST contract', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = ImageApi(
      AppConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        accessToken: 'fixture',
        userId: '4',
      ),
    );
    addTearDown(api.close);
    addTearDown(() => server.close(force: true));
    final calls = <String>[];
    final keys = <String?>[];
    final image = {
      'id': 41,
      'title': '树的影子',
      'status': 'SUCCEEDED',
      'image_url': 'https://storage.example/result.png',
    };
    server.listen((request) async {
      expect(request.headers.value('Authorization'), 'Bearer fixture');
      calls.add('${request.method} ${request.uri.path}');
      Object body = image;
      if (request.method == 'POST') {
        keys.add(request.headers.value('Idempotency-Key'));
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'prompt': '树的影子',
          'source_file_ids': [19],
          'size': '1024*1024',
        });
        request.response.statusCode = 202;
        body = {...image, 'status': 'QUEUED', 'image_url': null};
      } else if (request.uri.path == '/images') {
        expect(request.uri.queryParameters, {'page': '2', 'page_size': '20'});
        body = {
          'items': [image],
          'page': 2,
          'total_pages': 3,
        };
      } else if (request.method == 'PATCH') {
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'title': '影子',
        });
        body = {...image, 'title': '影子'};
      } else if (request.method == 'DELETE') {
        body = {'deleted': true};
      }
      request.response.write(jsonEncode({'code': 200, 'data': body}));
      await request.response.close();
    });

    const draft = ImageDraft(
      prompt: ' 树的影子 ',
      sourceFileIds: [19],
      size: ImageCanvasSize.square,
    );
    final creation = ImageSubmission(draft, null);
    final edit = ImageSubmission(draft, 41);
    expect((await api.submit(creation)).status.isActive, isTrue);
    expect((await api.submit(creation)).resultUri, isNull);
    expect((await api.submit(edit)).id, 41);
    expect(keys, [creation.key, creation.key, edit.key]);
    expect(edit.key, isNot(creation.key));
    expect((await api.list(page: 2)).items.single.id, 41);
    expect((await api.detail(41)).resultUri?.host, 'storage.example');
    expect((await api.rename(41, ' 影子 ')).title, '影子');
    await api.delete(41);
    expect(calls, [
      'POST /images',
      'POST /images',
      'POST /images/41/edits',
      'GET /images',
      'GET /images/41',
      'PATCH /images/41',
      'DELETE /images/41',
    ]);
  });

  test('draft and history handle Unicode, unsafe URLs, and legacy data', () {
    expect(
      ImageDraft(prompt: '🌳' * 4000).validate(hasSourceImage: false),
      isNull,
    );
    expect(
      ImageDraft(prompt: '🌳' * 4001).validate(hasSourceImage: false),
      isNotNull,
    );
    expect(
      const ImageDraft(
        prompt: '树',
        sourceFileIds: [1, 2, 3],
      ).validate(hasSourceImage: true),
      isNotNull,
    );
    final data = <String, dynamic>{
      'type': 'execution.progress',
      'version': 1,
      'run_id': 'run',
      'message_id': 'message',
      'sequence': 1,
      'status': 'succeeded',
      'steps': [],
    };
    expect(ExecutionSnapshot.tryParse(data)?.image, isNull);
    data['image'] = {
      'id': 21,
      'status': 'SUCCEEDED',
      'image_url': 'https://owner@storage.example/image.png',
    };
    final image = ExecutionSnapshot.tryParse(data)?.image;
    expect(image?.displayTitle, '图像 #21');
    expect(image?.resultUri, isNull);
    expect(ImageTask.tryParse({'status': 'SUCCEEDED'}), isNull);
    expect(ImageTaskStatus.parse('FUTURE_STATE'), ImageTaskStatus.unknown);
  });

  test(
    'LOOP history, state, branch edits and close use the same user contract',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final api = ImageApi(
        AppConfig(
          baseUrl: 'http://127.0.0.1:${server.port}',
          accessToken: 'fixture',
          userId: '4',
        ),
      );
      addTearDown(api.close);
      addTearDown(() => server.close(force: true));
      final calls = <String>[];
      final root = {'id': 41, 'status': 'SUCCEEDED'};
      final version = {
        'id': 63,
        'status': 'FAILED',
        'loop_version': 3,
        'loop_root_image_id': 41,
        'source_image_id': 41,
      };
      final history = {
        'root_image_id': 41,
        'root_image': root,
        'versions': [version],
        'used_edits': 3,
        'max_edits': 5,
        'status': 'OPEN',
        'accepted_image_id': null,
        'preview_image_id': 41,
        'preview_image_url': 'https://user@storage.example/unsafe.png',
        'create_time': '2026-11-24T10:12:00+08:00',
      };
      final edit = ImageSubmission(
        const ImageDraft(prompt: '改成日落'),
        41,
        loopEdit: true,
      );
      server.listen((request) async {
        expect(request.headers.value('Authorization'), 'Bearer fixture');
        final path = request.uri.path;
        calls.add(path);
        Object body = history;
        switch (path) {
          case '/images/loops':
            expect(request.uri.queryParameters, {
              'page': '2',
              'page_size': '10',
            });
            body = {
              'items': [history],
              'total': 11,
              'page': 2,
              'page_size': 10,
              'total_pages': 2,
            };
          case '/images/41/loop/edits':
            expect(request.method, 'POST');
            expect(request.headers.value('Idempotency-Key'), edit.key);
            expect(jsonDecode(await utf8.decoder.bind(request).join()), {
              'prompt': '改成日落',
            });
            request.response.statusCode = 202;
            body = {
              ...version,
              'id': 65,
              'status': 'QUEUED',
              'loop_version': 4,
            };
          case '/images/41/loop/close':
            expect(request.method, 'POST');
            expect(jsonDecode(await utf8.decoder.bind(request).join()), {
              'action': 'ACCEPTED',
            });
            body = {...history, 'status': 'ACCEPTED', 'accepted_image_id': 41};
          case '/images/loops/99':
            request.response.statusCode = 404;
            request.response.write(jsonEncode({'detail': 'missing'}));
            await request.response.close();
            return;
        }
        request.response.write(jsonEncode({'code': 200, 'data': body}));
        await request.response.close();
      });

      final page = await api.loopHistory(page: 2);
      expect((page.total, page.page, page.totalPages), (11, 2, 2));
      final detail = await api.loopHistoryDetail(page.items.single.loop.rootId);
      expect(detail.previewUri, isNull);
      expect(detail.createdAt, DateTime.utc(2026, 11, 24, 2, 12));
      expect(detail.loop.usedEdits, 3);
      expect(detail.loop.versions.single.loopVersion, 3);
      expect(detail.loop.versions.single.loopRootImageId, 41);
      expect(detail.loop.versions.single.resultUri, isNull);
      expect((await api.loopState(41)).canEdit, isTrue);
      expect((await api.submit(edit)).loopVersion, 4);
      final closed = await api.closeLoop(41, ImageLoopExit.accept);
      expect(closed.acceptedId, 41);
      expect(closed.canEdit, isFalse);
      await expectLater(api.loopHistoryDetail(99), throwsException);
      expect(calls, [
        '/images/loops',
        '/images/loops/41',
        '/images/41/loop',
        '/images/41/loop/edits',
        '/images/41/loop/close',
        '/images/loops/99',
      ]);
    },
  );
}
