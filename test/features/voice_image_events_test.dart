import 'dart:convert';
import 'dart:io';

import 'package:agent_voice_app/core/api/image_task.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/images/image_message_card.dart';
import 'package:agent_voice_app/features/images/image_widgets.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/video_image_fixture.dart';
import 'voice_home_page_test.dart'
    show
        ChatPreviewController,
        captureInputPreview,
        mountChat,
        previewDirectory;
import 'voice_session_controller_test.dart' show FakeAudioBridge, waitUntil;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('agent_voice/audio'),
          (_) async => null,
        );
  });

  if (previewDirectory.isNotEmpty) {
    setUpAll(() async {
      final font = await File(const String.fromEnvironment('CHAT_PREVIEW_FONT'))
          .readAsBytes();
      for (final family in ['ChatPreview', 'Roboto', 'Ahem']) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(font)))).load();
      }
      final icons = await File(
        const String.fromEnvironment('CHAT_PREVIEW_ICON_FONT'),
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    });
  }

  test(
    'image results survive text updates and history and refresh shared tasks once',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final audio = FakeAudioBridge();
      final controller = VoiceSessionController(
        config: AppConfig(
          baseUrl: 'http://127.0.0.1:${server.port}',
          accessToken: 'fixture',
          userId: '2',
        ),
        audio: audio,
      );
      addTearDown(() async {
        controller.dispose();
        await audio.close();
        await server.close(force: true);
      });
      final image = {'id': 31, 'status': 'QUEUED', 'title': '远山'};
      final imageResults = {
        'items': [
          {
            'id': 33,
            'status': 'SUCCEEDED',
            'title': '山谷',
            'image_url': 'https://example.test/33.png',
          },
          image,
        ],
        'total': 5,
      };
      final execution = {
        'type': 'execution.progress',
        'version': 1,
        'run_id': 'run',
        'message_id': 'msg',
        'sequence': 1,
        'status': 'succeeded',
        'steps': [],
        'image': image,
      };
      final listExecution = {
        ...execution,
        'run_id': 'run-list',
        'message_id': 'msg-list',
        'image': null,
        'image_results': imageResults,
      };
      var imageReads = 0;
      WebSocket? socket;
      server.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          socket = await WebSocketTransformer.upgrade(request);
          socket!.listen((message) {
            if (message is String &&
                (jsonDecode(message) as Map)['type'] == 'session.configure') {
              socket!.add(
                jsonEncode({
                  'type': 'session.ready',
                  'connection_id': '00112233-4455-6677-8899-aabbccddeeff',
                }),
              );
            }
          });
          return;
        }
        if (request.uri.path == '/images/31') imageReads++;
        final Object data = switch (request.uri.path) {
          '/voice/capabilities' => {
            'enabled': true,
            'protocol_version': 1,
            'voices': ['Cherry'],
            'default_voice': 'Cherry',
          },
          '/voice/sessions' => {
            'session_id': 'session-1',
            'thread_id': 'thread-1',
            'agent_id': 'chatbot',
            'voice': 'Cherry',
            'expires_at': '2099-01-01T00:00:00Z',
          },
          '/images/31' => {
            ...image,
            'status': 'SUCCEEDED',
            'image_url': 'https://example.test/31.png',
            'create_time': '2026-11-23T10:00:00Z',
          },
          final path when path.endsWith('/executions') => {
            'executions': [
              {...execution, 'response_id': 'reply-1'},
              {...listExecution, 'response_id': 'reply-list'},
            ],
          },
          final path when path.endsWith('/history') => {
            'messages': [
              {
                'type': 'ai',
                'content': '历史图像任务',
                'response_metadata': {'execution': execution},
              },
              {
                'type': 'ai',
                'content': '历史查询结果',
                'response_metadata': {'execution': listExecution},
              },
            ],
          },
          _ => {'status': 'closing'},
        };
        request.response.write(jsonEncode({'code': 200, 'data': data}));
        await request.response.close();
      });
      await controller.connect(agentId: 'chatbot', voice: 'Cherry');

      void send(
        String type,
        String responseId, [
        Map<String, Object?> data = const {},
      ]) {
        socket!.add(
          jsonEncode({'type': type, 'response_id': responseId, ...data}),
        );
      }

      final custom = {
        'data': {'type': 'image.task', 'image': image},
      };
      send('response.started', 'reply-1');
      send('text.delta', 'reply-1', {'text': '查看'});
      send('agent.custom', 'reply-1', custom);
      send('agent.custom', 'reply-1', custom);
      send('text.delta', 'reply-1', {'text': '图像'});
      await waitUntil(() => controller.messages.lastOrNull?.text == '查看图像');
      expect(controller.messages.single.image?.id, 31);

      send('response.cancelled', 'reply-2');
      send('agent.custom', 'reply-2', custom);
      send('agent.custom', 'reply-1', {
        'data': {'type': 'image.task', 'image': {}},
      });
      send('text.delta', 'reply-1', {'text': '。'});
      await waitUntil(() => controller.messages.lastOrNull?.text == '查看图像。');
      expect(controller.messages.single.image?.displayTitle, '远山');

      send('response.started', 'reply-list');
      send('agent.custom', 'reply-list', {
        'data': {'type': 'image.list', ...imageResults},
      });
      send('agent.custom', 'reply-list', {
        'data': {'type': 'image.list', 'items': [], 'total': 0},
      });
      send('agent.custom', 'reply-list', {'data': listExecution});
      send('text.delta', 'reply-list', {'text': '找到 5 张图片。'});
      await waitUntil(() => controller.messages.last.text == '找到 5 张图片。');
      expect(
        controller.messages.last.imageResults?.items.map((image) => image.id),
        [33, 31],
      );
      expect(controller.messages.last.imageResults?.total, 5);

      await controller.refreshExecutionState();
      expect(imageReads, 1);
      final expectedUri = Uri.parse('https://example.test/31.png');
      expect(controller.messages.first.image?.resultUri, expectedUri);
      expect(
        controller.messages.last.imageResults?.items.last.resultUri,
        expectedUri,
      );
      expect(
        controller.messages.last.imageResults?.items.last.createdAt,
        DateTime.utc(2026, 11, 23, 10),
      );

      await controller.refreshExecutionState();
      expect(imageReads, 1);
      expect(controller.messages.first.image?.resultUri, expectedUri);

      await controller.disconnect();
      await controller.loadHistory('chatbot', 'thread-1');
      expect(controller.messages.first.image?.id, 31);
      expect(
        controller.messages.last.imageResults?.items.map((image) => image.id),
        [33, 31],
      );
      expect(
        controller.messages.last.imageResults?.items.last.resultUri,
        expectedUri,
      );
    }, _GalleryHttpOverrides()),
  );

  for (final wide in [true, false]) {
    testWidgets(
      'voice gallery draws completed works with ${wide ? 'two columns' : 'one column at large text'}',
      (tester) async {
        final downloaded = <String>[];
        final server = (await tester.runAsync(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            downloaded.add(request.uri.path);
            request.response.add(videoTestBmp());
            await request.response.close();
          });
          return server;
        }))!;
        addTearDown(() => server.close(force: true));
        final controller = ChatPreviewController()..entries.clear();
        await mountChat(
          tester,
          controller,
          size: wide ? const Size(390, 844) : const Size(320, 844),
          textScale: wide ? 1 : 2,
          brightness: wide ? Brightness.light : Brightness.dark,
          useAppTheme: true,
        );
        await tester.runAsync(
          () => HttpOverrides.runWithHttpOverrides(() async {
            controller.entries.add(
              ConversationEntry(
                role: 'ai',
                text: '没有找到符合条件的图片。最近 3 天有 2 张图片。',
                imageResults: ImageResultPage(
                  items: [
                    for (final (id, title) in [(33, '海边的远山'), (31, '山间的蓝色小船')])
                      ImageTask(
                        id: id,
                        title: title,
                        size: '1024*768',
                        createdAt: DateTime(2026, 11, 23),
                        status: ImageTaskStatus.succeeded,
                        imageUri: Uri.http(
                          '127.0.0.1:${server.port}',
                          '/$id.bmp',
                        ),
                      ),
                  ],
                  total: 2,
                ),
              ),
            );
            controller.redraw();
            await tester.pump();
            final previews = find.byType(ImagePreview);
            expect(previews, findsNWidgets(2));
            for (var index = 0; index < 2; index++) {
              final element = previews.at(index);
              final image = find.descendant(
                of: element,
                matching: find.byType(Image),
              );
              await precacheImage(
                tester.widget<Image>(image).image,
                tester.element(element),
              ).timeout(const Duration(seconds: 5));
            }
          }, _GalleryHttpOverrides()),
        );
        await tester.pumpAndSettle();
        final cards = find.byType(ImageMessageCard);
        expect(downloaded, unorderedEquals(['/33.bmp', '/31.bmp']));
        expect(find.text('11月23日'), findsNWidgets(2));
        expect(
          tester
              .widgetList<RawImage>(
                find.descendant(
                  of: find.byType(ImageMessageGallery),
                  matching: find.byType(RawImage),
                ),
              )
              .where((image) => image.image != null),
          hasLength(2),
        );
        final first = tester.getTopLeft(cards.first);
        final second = tester.getTopLeft(cards.last);
        if (wide) {
          expect(second.dy, first.dy);
          expect(second.dx, greaterThan(first.dx));
        } else {
          expect(second.dx, first.dx);
          expect(second.dy, greaterThan(first.dy));
        }
        expect(tester.takeException(), isNull);
        await captureInputPreview(
          tester,
          wide ? 'voice-image-gallery' : 'voice-image-gallery-large-dark',
        );
        if (wide) {
          final result = controller.entries.single;
          final finished = result.images.first;
          controller.entries[0] = result.copyWith(
            imageResults: ImageResultPage(
              items: [
                finished,
                const ImageTask(
                  id: 31,
                  status: ImageTaskStatus.running,
                  title: '山间的蓝色小船',
                ),
              ],
              total: 2,
            ),
          );
          controller.redraw();
          await tester.pump();
          final previews = find.byType(ImagePreview);
          expect(tester.getSize(previews.first), tester.getSize(previews.last));
          expect(find.text('生成中'), findsOneWidget);
          await captureInputPreview(tester, 'voice-image-gallery-pending');

          controller.entries[0] = ConversationEntry(
            role: 'ai',
            text: '图片已保存。',
            image: finished,
          );
          controller.redraw();
          await tester.pumpAndSettle();
          expect(cards, findsOneWidget);
          expect(tester.widget<ImagePreview>(previews).fit, BoxFit.contain);
        }
      },
    );
  }
}

class _GalleryHttpOverrides extends HttpOverrides {}
