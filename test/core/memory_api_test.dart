import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

const memoryId = '11111111-1111-4111-8111-111111111111';
const nextId = '22222222-2222-4222-8222-222222222222';
Map<String, Object?> record(String text) => {
  'id': memoryId,
  'memory': text,
  'user_id': '42',
  'agent_id': 'mem0-chatbot',
  'created_at': null,
  'updated_at': '2026-10-14T09:00:00Z',
  'metadata': {'source_thread_id': 'thread-1'},
};

void main() {
  late HttpServer server;
  late AgentApiClient api;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = AgentApiClient(
      AppConfig(
        baseUrl: 'http://${server.address.host}:${server.port}',
        accessToken: 'test-token',
        userId: '42',
      ),
    );
  });

  tearDown(() async {
    api.close();
    await server.close(force: true);
  });

  test(
    'all six endpoints bind the logged-in user and honor distinct cursors',
    () async {
      final calls = <String>[];
      server.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-token',
        );
        expect(request.uri.queryParameters['user_id'], '42');
        calls.add('${request.method} ${request.uri.path}');
        Object data;
        if (request.uri.path.endsWith('/history')) {
          expect(request.uri.queryParameters['cursor'], '7');
          expect(request.uri.queryParameters['limit'], '2');
          data = {
            'history': [
              {
                'id': 8,
                'memory_id': memoryId,
                'event': 'UPDATE',
                'old_memory': '喜欢茶',
                'new_memory': '喜欢咖啡',
                'created_at': null,
                'updated_at': null,
              },
            ],
            'next_cursor': 8,
          };
        } else if (request.method == 'DELETE') {
          data = {'deleted_count': request.uri.path == '/memories' ? 3 : 1};
        } else if (request.method == 'PUT') {
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'text': '喜欢咖啡',
          });
          data = record('喜欢咖啡');
        } else if (request.uri.path == '/memories') {
          expect(request.uri.queryParameters['cursor'], nextId);
          expect(request.uri.queryParameters['limit'], '2');
          data = {
            'memories': [record('喜欢茶')],
            'next_cursor': null,
          };
        } else {
          data = record('喜欢茶');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'code': 200, 'message': 'success', 'data': data}),
        );
        await request.response.close();
      });

      final page = await api.memories(limit: 2, cursor: nextId);
      expect(page.items.single.memory, '喜欢茶');
      expect(page.nextCursor, isNull);
      final detail = await api.memory(memoryId);
      expect(detail.metadata['source_thread_id'], 'thread-1');
      expect(detail.createdAt, isNull);
      expect((await api.updateMemory(memoryId, ' 喜欢咖啡 ')).memory, '喜欢咖啡');
      expect(await api.deleteMemory(memoryId), 1);
      expect(await api.deleteMemories(), 3);
      final history = await api.memoryHistory(memoryId, limit: 2, cursor: 7);
      expect(history.items.single.oldMemory, '喜欢茶');
      expect(history.nextCursor, 8);
      expect(calls, [
        'GET /memories',
        'GET /memories/$memoryId',
        'PUT /memories/$memoryId',
        'DELETE /memories/$memoryId',
        'DELETE /memories',
        'GET /memories/$memoryId/history',
      ]);
    },
  );

  test('rejects invalid inputs before making any request', () async {
    var calls = 0;
    server.listen((request) {
      calls++;
      request.response.close();
    });
    final invalid = <Future<Object?>>[
      api.memories(limit: 0),
      api.memories(limit: 101),
      api.memories(cursor: 'bad'),
      api.memory('../users'),
      api.deleteMemory('bad'),
      api.updateMemory(memoryId, '  '),
      api.updateMemory(memoryId, 'x' * 6001),
      api.memoryHistory(memoryId, cursor: 0),
    ];
    for (final operation in invalid) {
      await expectLater(operation, throwsA(isA<ApiException>()));
    }
    expect(calls, 0);
  });

  test('Unicode text limit matches backend code points', () async {
    server.listen((request) async {
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      expect((body['text'] as String).runes.length, 6000);
      request.response.write(
        jsonEncode({
          'code': 200,
          'message': 'success',
          'data': record(body['text'] as String),
        }),
      );
      await request.response.close();
    });
    expect(
      (await api.updateMemory(memoryId, '😀' * 6000)).memory.runes.length,
      6000,
    );
    await expectLater(
      api.updateMemory(memoryId, '😀' * 6001),
      throwsA(isA<ApiException>()),
    );
  });

  for (final status in [401, 403, 404, 422, 503, 504]) {
    test('preserves HTTP $status for actionable UI feedback', () async {
      server.listen((request) async {
        request.response.statusCode = status;
        request.response.write(
          jsonEncode({
            'code': status,
            'message': 'memory unavailable',
            'data': null,
          }),
        );
        await request.response.close();
      });
      await expectLater(
        api.memory(memoryId),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', status),
        ),
      );
    });
  }

  test('requires login for every memory operation', () async {
    final loggedOut = AgentApiClient(
      const AppConfig(
        baseUrl: 'http://127.0.0.1:1',
        accessToken: '',
        userId: '',
      ),
    );
    addTearDown(loggedOut.close);
    for (final operation in <Future<Object?>>[
      loggedOut.memories(),
      loggedOut.memory(memoryId),
      loggedOut.updateMemory(memoryId, 'text'),
      loggedOut.deleteMemory(memoryId),
      loggedOut.deleteMemories(),
      loggedOut.memoryHistory(memoryId),
    ]) {
      await expectLater(
        operation,
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
    }
  });
}
