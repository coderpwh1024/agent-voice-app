import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  test('gets and updates the authenticated user profile', () async {
    String? multipartBody;
    server.listen((request) async {
      requests.add(request);
      if (request.method == 'PATCH') {
        final bytes = await request.fold<BytesBuilder>(
          BytesBuilder(),
          (builder, chunk) => builder..add(chunk),
        );
        multipartBody = utf8.decode(bytes.takeBytes(), allowMalformed: true);
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'code': 200,
          'message': 'success',
          'data': <String, Object?>{
            'id': 42,
            'nickname': request.method == 'PATCH' ? 'New name' : 'Old name',
            'email': 'user@example.com',
            'image_url': request.method == 'PATCH'
                ? 'https://cdn.example.com/avatar.png'
                : null,
          },
        }),
      );
      await request.response.close();
    });

    final api = client();
    final before = await api.currentUser();
    final updated = await api.updateCurrentUser(
      nickname: 'New name',
      imageBytes: Uint8List.fromList(<int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
        1,
        2,
        3,
      ]),
      imageName: 'avatar.png',
      imageContentType: 'image/png',
    );

    expect(before.nickname, 'Old name');
    expect(updated.nickname, 'New name');
    expect(updated.imageUrl, 'https://cdn.example.com/avatar.png');
    expect(requests, hasLength(2));
    expect(requests.first.uri.path, '/users/me');
    expect(requests.first.method, 'GET');
    expect(requests.last.method, 'PATCH');
    expect(
      requests.every(
        (request) =>
            request.headers.value(HttpHeaders.authorizationHeader) ==
            'Bearer access-token',
      ),
      isTrue,
    );
    expect(requests.last.headers.contentType?.mimeType, 'multipart/form-data');
    expect(multipartBody, contains('name="nickname"'));
    expect(multipartBody, contains('New name'));
    expect(multipartBody, contains('filename="avatar.png"'));
    expect(multipartBody, contains('Content-Type: image/png'));
    api.close();
  });

  test(
    'daily records use authenticated GET routes and preserve UTC dates',
    () async {
      server.listen((request) async {
        requests.add(request);
        expect(request.method, 'GET');
        expect(request.uri.queryParameters, {'user_id': '42'});
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer access-token',
        );
        request.response.headers.contentType = ContentType.json;
        final detail = request.uri.path.endsWith('/2026-10-13');
        request.response.write(
          jsonEncode({
            'code': 200,
            'message': 'success',
            'data': detail
                ? {
                    'record_date': '2026-10-13',
                    'conversations': [
                      {
                        'thread_id': 'thread-1',
                        'agent_id': 'chatbot',
                        'title': '今天的计划',
                        'updated_at': '2026-10-13T23:59:00Z',
                        'messages': [
                          {'type': 'human', 'content': '今天的计划'},
                          {
                            'type': 'ai',
                            'content': '',
                            'tool_calls': [
                              {'name': 'calendar'},
                            ],
                          },
                          {'type': 'tool', 'content': '查询完成'},
                          {'type': 'ai', 'content': '先完成最重要的一件事。'},
                        ],
                      },
                    ],
                  }
                : {
                    'records': [
                      {
                        'record_date': '2026-10-12',
                        'latest_at': '2026-10-12T22:00:00Z',
                        'conversation_count': 1,
                      },
                      {
                        'record_date': '2026-10-13',
                        'latest_at': '2026-10-13T23:59:00Z',
                        'conversation_count': 2,
                      },
                    ],
                  },
          }),
        );
        await request.response.close();
      });
      final api = client();
      final records = await api.chatRecords('chatbot');
      expect(records.map((record) => record.recordDate), [
        '2026-10-13',
        '2026-10-12',
      ]);
      expect(records.first.date.isUtc, isTrue);
      expect(records.first.conversationCount, 2);
      final detail = await api.chatRecordDetail(
        'chatbot',
        records.first.recordDate,
      );
      expect(requests.map((request) => request.uri.path), [
        '/chatbot/chat-records',
        '/chatbot/chat-records/2026-10-13',
      ]);
      expect(detail.messageCount, 4);
      expect(detail.conversations.single.messages[1].toolNames, ['calendar']);
      expect(detail.conversations.single.thread.threadId, 'thread-1');
      expect(detail.conversations.single.updatedAt.isUtc, isTrue);
      api.close();
    },
  );

  test(
    'daily records reject a missing user and surface forbidden responses',
    () async {
      final anonymous = AgentApiClient(
        AppConfig(
          baseUrl: 'http://${server.address.host}:${server.port}',
          accessToken: 'token',
          userId: '',
        ),
      );
      await expectLater(
        anonymous.chatRecords('chatbot'),
        throwsA(
          isA<ApiException>().having((error) => error.statusCode, 'status', 0),
        ),
      );
      anonymous.close();
      server.listen((request) async {
        request.response.statusCode = 403;
        request.response.write(
          jsonEncode({
            'code': 403,
            'message': 'user_id does not match the authenticated user',
            'data': null,
          }),
        );
        await request.response.close();
      });
      final api = client();
      await expectLater(
        api.chatRecords('chatbot'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'status',
            403,
          ),
        ),
      );
      await expectLater(
        api.chatRecordDetail('chatbot', '../history'),
        throwsA(
          isA<ApiException>().having((error) => error.statusCode, 'status', 0),
        ),
      );
      api.close();
    },
  );

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
