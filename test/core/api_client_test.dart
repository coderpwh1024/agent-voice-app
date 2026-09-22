import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late List<HttpRequest> requests;

  setUp(() async {
    requests = <HttpRequest>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  AgentApiClient client({String token = 'access-token'}) => AgentApiClient(
    AppConfig(
      baseUrl: 'http://${server.address.host}:${server.port}',
      accessToken: token,
      userId: '42',
    ),
  );

  test(
    'email verification uses public routes and unwraps response data',
    () async {
      server.listen((request) async {
        requests.add(request);
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/code')) {
          expect(body, <String, dynamic>{'email': 'user@example.com'});
          request.response.write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'success',
              'data': <String, Object?>{'expires_in_seconds': 180},
            }),
          );
        } else {
          expect(body, <String, dynamic>{
            'email': 'user@example.com',
            'code': '012345',
          });
          request.response.write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'success',
              'data': <String, Object?>{
                'access_token': 'jwt-token',
                'token_type': 'bearer',
                'expires_at': 2000000000,
                'is_new_user': true,
                'user': <String, Object?>{
                  'id': 42,
                  'nickname': 'user',
                  'email': 'user@example.com',
                  'image_url': null,
                },
              },
            }),
          );
        }
        await request.response.close();
      });

      final api = client(token: 'must-not-be-sent');
      final accepted = await api.requestEmailCode(' USER@example.com ');
      final result = await api.verifyEmailCode(
        email: 'USER@example.com',
        code: '012345',
      );

      expect(accepted.expiresInSeconds, 180);
      expect(result.accessToken, 'jwt-token');
      expect(result.user.id, 42);
      expect(result.isNewUser, isTrue);
      expect(
        requests.every(
          (request) =>
              request.headers.value(HttpHeaders.authorizationHeader) == null,
        ),
        isTrue,
      );
      api.close();
    },
  );

  test('voice capabilities unwrap data and send bearer token', () async {
    server.listen((request) async {
      requests.add(request);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'code': 200,
          'message': 'success',
          'data': <String, Object?>{
            'enabled': true,
            'protocol_version': 1,
            'voices': <String>['Cherry'],
            'agents': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'chatbot',
                'description': 'Chat',
                'speech_mode': 'streaming',
                'cancel_execution': true,
              },
            ],
          },
        }),
      );
      await request.response.close();
    });

    final api = client();
    final capabilities = await api.capabilities();

    expect(capabilities.enabled, isTrue);
    expect(capabilities.voices, <String>['Cherry']);
    expect(capabilities.agents.single.id, 'chatbot');
    expect(
      requests.single.headers.value(HttpHeaders.authorizationHeader),
      'Bearer access-token',
    );
    api.close();
  });

  test('surfaces backend detail for a failed verification', () async {
    server.listen((request) async {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'detail': 'Invalid or expired verification code',
        }),
      );
      await request.response.close();
    });

    final api = client();

    await expectLater(
      api.verifyEmailCode(email: 'user@example.com', code: '000000'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having(
              (error) => error.message,
              'message',
              'Invalid or expired verification code',
            ),
      ),
    );
    api.close();
  });
}
