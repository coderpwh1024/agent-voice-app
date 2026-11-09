import 'dart:io';
import 'dart:ui' as ui;

import 'package:agent_voice_app/core/api/execution_models.dart';
import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:agent_voice_app/features/execution/execution_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> executionFixture({
  int sequence = 1,
  String status = 'running',
  Object? video,
  bool confirmation = false,
}) => {
  'type': 'execution.progress',
  'version': 1,
  'run_id': 'run-1',
  'response_id': 'response-1',
  'message_id': 'message-1',
  'sequence': sequence,
  'status': status,
  'text': status == 'succeeded' ? '已处理' : '',
  'video': video,
  'steps': [
    {
      'step_id': 'step-1',
      'stage': confirmation ? 'memory.lookup' : 'video.skill',
      'label': confirmation ? '查找目标记忆' : '加载视频技能',
      'status': 'succeeded',
      'duration_ms': 120,
    },
    {
      'step_id': 'step-2',
      'stage': confirmation ? 'memory.command' : 'video.submit',
      'label': confirmation ? '删除所选记忆' : '提交视频任务',
      'status': status,
      'detail': '以服务端返回结果为准',
    },
  ],
  if (confirmation)
    'confirmation': {
      'confirmation_id': 'a' * 64,
      'label': '将删除你选中的记忆，确认后执行。',
      'expires_at': '2099-01-01T00:00:00Z',
    },
};

void main() {
  test(
    'malformed or future progress does not become an executable confirmation',
    () {
      expect(
        ExecutionSnapshot.tryParse({...executionFixture(), 'version': 2}),
        isNull,
      );
      expect(
        ExecutionSnapshot.tryParse({...executionFixture(), 'sequence': -1}),
        isNull,
      );
      expect(
        ExecutionSnapshot.tryParse({
          ...executionFixture(),
          'steps': [{}],
        }),
        isNull,
      );
      expect(
        ExecutionConfirmation.tryParse({
          'confirmation_id': 'bad',
          'label': '删除',
          'expires_at': '2099-01-01',
        }),
        isNull,
      );
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('execution details fit 320px and 200% text in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fontPath = Platform.environment['EXECUTION_FONT_PATH'];
      if (fontPath != null) {
        await tester.runAsync(() async {
          final font = FontLoader('ExecutionPreview')
            ..addFont(
              Future.value(
                ByteData.sublistView(await File(fontPath).readAsBytes()),
              ),
            );
          await font.load();

          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
      }
      final key = GlobalKey();
      var submissions = 0;
      final snapshot = ExecutionSnapshot.tryParse(
        executionFixture(status: 'waiting_confirmation', confirmation: true),
      )!;
      final theme = AppTheme.build(
        brightness,
        baseTheme: fontPath == null
            ? null
            : ThemeData(brightness: brightness, fontFamily: 'ExecutionPreview'),
      );
      final previewTheme = fontPath == null
          ? theme
          : theme.copyWith(
              filledButtonTheme: FilledButtonThemeData(
                style: theme.filledButtonTheme.style!.copyWith(
                  textStyle: WidgetStatePropertyAll(
                    theme.filledButtonTheme.style!.textStyle!
                        .resolve({})!
                        .copyWith(fontFamily: 'ExecutionPreview'),
                  ),
                ),
              ),
            );
      await tester.pumpWidget(
        MaterialApp(
          theme: previewTheme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: AppPalette.forBrightness(brightness).background,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ExecutionProgress(
                        execution: snapshot,
                        onConfirm: (id, approved) {
                          expect(id, 'a' * 64);
                          expect(approved, isTrue);
                          submissions++;
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('执行过程 · 等待确认'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (Platform.environment['EXECUTION_SCREENSHOTS'] == '1') {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(key),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/execution-preview').create(recursive: true);
          await File('build/execution-preview/${brightness.name}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.text('确认操作'));
      await tester.tap(find.text('确认操作'));
      await tester.pump();
      expect(submissions, 1);
      expect(find.text('正在核实'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
