import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/api/execution_models.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/images/data/image_api.dart';
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
}
