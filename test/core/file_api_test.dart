import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/api/file_api.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> fileJson() => {
  'id': 42,
  'url': 'https://cdn.example/users/7/files/image',
  'original_name': '画面.bmp',
  'content_type': 'image/bmp',
  'size_bytes': 3,
  'uploaded_at': '2026-10-24T08:00:00Z',
};

void main() {
  late HttpServer server;
  late FileApi api;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = FileApi(
      AppConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        accessToken: 'test-only-token',
        userId: '7',
      ),
    );
  });
  tearDown(() async {
    api.close();
    await server.close(force: true);
  });
  test(
    'multipart upload and owner-bound URL lookup use the uniform response',
    () async {
      final paths = <String>[];
      server.listen((request) async {
        paths.add('${request.method} ${request.uri.path}');
        expect(
          request.headers.value('authorization'),
          'Bearer test-only-token',
        );
        expect(request.uri.queryParameters.containsKey('user_id'), isFalse);
        if (request.method == 'POST') {
          expect(request.headers.contentType!.mimeType, 'multipart/form-data');
          final body = await utf8.decodeStream(request);
          expect(body, contains('name="file"; filename="画面.bmp"'));
          expect(body, contains('Content-Type: image/bmp\r\n'));
          expect(body, contains('\r\nabc\r\n--'));
          request.response.statusCode = 201;
        }
        request.response.write(jsonEncode({'code': 200, 'data': fileJson()}));
        await request.response.close();
      });
      final uploaded = await api.upload(
        bytes: Uint8List.fromList(utf8.encode('abc')),
        name: '画面.bmp',
        contentType: 'image/bmp',
      );
      expect(uploaded.url, fileJson()['url']);
      final queried = await api.get(uploaded.id);
      expect(queried.name, '画面.bmp');
      expect(queried.sizeBytes, 3);
      expect(paths, ['POST /files', 'GET /files/42/url']);
    },
  );
  for (final status in [401, 403, 404, 413, 422, 502, 503]) {
    test(
      'HTTP $status is preserved and an upload is never automatically retried',
      () async {
        var count = 0;
        server.listen((request) async {
          count++;
          await request.drain<void>();
          request.response.statusCode = status;
          request.response.write(
            jsonEncode({'code': status, 'message': 'failure', 'data': null}),
          );
          await request.response.close();
        });
        await expectLater(
          api.upload(
            bytes: Uint8List.fromList([1]),
            name: 'x.bmp',
            contentType: 'image/bmp',
          ),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', status),
          ),
        );
        expect(count, 1);
      },
    );
  }
  test('bad metadata and invalid requests are rejected', () async {
    for (final patch in [
      {'id': 0},
      {'url': 'file:///a.png'},
      {'url': 'https://user:secret@example.com/a'},
      {'size_bytes': 0},
      {'uploaded_at': 'bad'},
    ]) {
      expect(
        () => UploadedFileMetadata.fromJson({...fileJson(), ...patch}),
        throwsFormatException,
      );
    }
    await expectLater(
      api.upload(bytes: Uint8List(0), name: 'x.bmp', contentType: 'image/bmp'),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      api.upload(
        bytes: Uint8List(1),
        name: 'x\r\n.bmp',
        contentType: 'image/bmp',
      ),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      api.upload(
        bytes: Uint8List(1),
        name: 'x.bmp',
        contentType: 'image/bmp\r\nX: injected',
      ),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      api.upload(
        bytes: Uint8List(FileApi.maxImageBytes + 1),
        name: 'x.bmp',
        contentType: 'image/bmp',
      ),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 413)),
    );
    await expectLater(api.get(0), throwsA(isA<ApiException>()));
  });
  test('redirects do not forward an upload or its bearer token', () async {
    var calls = 0;
    server.listen((request) async {
      calls++;
      await request.drain<void>();
      request.response.statusCode = 307;
      request.response.headers.set('location', '/another-origin');
      await request.response.close();
    });
    await expectLater(
      api.upload(
        bytes: Uint8List.fromList([1]),
        name: 'a.bmp',
        contentType: 'image/bmp',
      ),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 1);
  });
}
