import 'dart:io';

import 'package:agent_voice_app/core/content/message_image_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/video_image_fixture.dart';

void main() {
  test('loads extensionless image bytes without app authorization and follows a safe redirect', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    server.listen((r) async {
      expect(r.headers.value(HttpHeaders.authorizationHeader), isNull);
      paths.add(r.uri.path);
      if (r.uri.path == '/redirect') {
        r.response.statusCode = 302;
        r.response.headers.set('location', '/static/asset');
      } else {
        r.response.headers.contentType = ContentType.binary;
        r.response.add(videoTestBmp());
      }
      await r.response.close();
    });
    addTearDown(() => server.close(force: true));
    final loader = MessageImageLoader();
    addTearDown(loader.close);
    final bytes = await loader.load(
      Uri.parse('http://127.0.0.1:${server.port}/redirect'),
    );
    expect(bytes, videoTestBmp());
    expect(paths, ['/redirect', '/static/asset']);
  });
  for (final mode in [
    'missing',
    'html',
    'oversize',
    'chunked',
    'unsafe-redirect',
    'loop',
  ]) {
    test('fails cleanly for $mode resources', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((r) async {
        requests++;
        switch (mode) {
          case 'missing':
            r.response.statusCode = 404;
          case 'html':
            r.response.write('<html>This is not an image</html>');
          case 'oversize':
            r.response.contentLength = MessageImageLoader.maxBytes + 1;
            r.response.add(List.filled(MessageImageLoader.maxBytes + 1, 0));
          case 'chunked':
            r.response.add(List.filled(MessageImageLoader.maxBytes + 1, 0));
          case 'unsafe-redirect':
            r.response.statusCode = 302;
            r.response.headers.set(
              'location',
              'http://user:secret@example.com/asset',
            );
          case 'loop':
            r.response.statusCode = 302;
            r.response.headers.set('location', '/loop');
        }
        try {
          await r.response.close();
        } catch (_) {
          r.response.detachSocket().then((s) => s.destroy()).catchError((_) {});
        }
      });
      addTearDown(() => server.close(force: true));
      final loader = MessageImageLoader();
      addTearDown(loader.close);
      await expectLater(
        loader.load(Uri.parse('http://127.0.0.1:${server.port}/$mode')),
        throwsA(isA<FormatException>()),
      );
      expect(requests, lessThanOrEqualTo(4));
    });
  }
}
