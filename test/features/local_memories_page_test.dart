import 'dart:io';
import 'dart:ui' as ui;

import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/core/memory/local_memory_store.dart';
import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:agent_voice_app/features/memories/local_memories_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = await rootBundle.load('assets/fonts/StudioSerif-Regular.ttf');
    await (FontLoader('StudioSerif')..addFont(Future.value(font))).load();
    final systemFont = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    final bodyFont = await systemFont.exists()
        ? ByteData.sublistView(await systemFont.readAsBytes())
        : font;
    for (final family in ['Roboto', 'Ahem']) {
      await (FontLoader(family)..addFont(Future.value(bodyFont))).load();
    }
    final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
  });
  for (final dark in [false, true]) {
    testWidgets(
      'local memory editing, confirmation and 320px layout dark=$dark',
      (tester) async {
        final folder = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('local-memory-ui-'),
        ))!;
        final store = LocalMemoryStore(directory: () async => folder);
        await tester.runAsync(() => store.save('请叫我小林，回答尽量简短。', 'profile'));
        addTearDown(() async {
          store.dispose();
          await folder.delete(recursive: true);
        });
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = GlobalKey();
        Future<void> screenshot(String state) => tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/local-memory-qa').create(recursive: true);
          await File(
            'build/local-memory-qa/${dark ? 'dark' : 'light'}-$state.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
        final theme = AppTheme.build(dark ? Brightness.dark : Brightness.light);
        Widget page(LocalMemoryStore target) => RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(
              appBarTheme: theme.appBarTheme.copyWith(
                titleTextStyle: theme.appBarTheme.titleTextStyle!.copyWith(
                  fontFamily: 'Roboto',
                ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: theme.filledButtonTheme.style!.copyWith(
                  textStyle: WidgetStatePropertyAll(
                    theme.filledButtonTheme.style!.textStyle!
                        .resolve({})!
                        .copyWith(fontFamily: 'Roboto'),
                  ),
                ),
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: LocalMemoriesPage(
              key: ObjectKey(target),
              config: const AppConfig(
                baseUrl: 'http://localhost',
                accessToken: 'test',
                userId: '42',
              ),
              store: target,
            ),
          ),
        );
        await tester.pumpWidget(page(store));
        await tester.pumpAndSettle();
        expect(find.text('本机记忆'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await screenshot('overview');
        final scroller = find
            .descendant(
              of: find.byType(LocalMemoriesPage),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('请叫我小林，回答尽量简短。'),
          400,
          scrollable: scroller,
        );
        expect(find.text('请叫我小林，回答尽量简短。'), findsOneWidget);
        await tester.dragUntilVisible(
          find.text('编辑').hitTestable(),
          scroller,
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        await screenshot('entry');
        await tester.tap(find.text('编辑'));
        await tester.pumpAndSettle();
        await screenshot('editor');
        await tester.enterText(find.byType(TextField).last, '回答时先给结论。');
        await tester.tap(find.text('保存到手机'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          for (
            var i = 0;
            i < 50 &&
                !(await File(
                  '${folder.path}/MEMORY.md',
                ).readAsString()).contains('回答时先给结论。');
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(store.entries.single.text, '回答时先给结论。');
        for (var attempt = 0; attempt < 50; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (tester
                  .widget<TextButton>(find.widgetWithText(TextButton, '忘记'))
                  .onPressed !=
              null) {
            break;
          }
        }
        await tester.dragUntilVisible(
          find.text('忘记').hitTestable(),
          scroller,
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        final forget = find.widgetWithText(TextButton, '忘记');
        expect(
          tester.widget<TextButton>(forget).onPressed,
          isNotNull,
          reason: '落盘后应恢复操作',
        );
        await tester.tap(forget);
        await tester.pumpAndSettle();
        expect(find.text('忘记这条信息'), findsOneWidget);
        await screenshot('confirmation');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(store.entries, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.runAsync(store.clear);
        await tester.pumpAndSettle();
        await tester.dragUntilVisible(
          find.text('这里还没有匹配的记忆。可以手动添加，也可以在聊天后回来查看。').hitTestable(),
          scroller,
          const Offset(0, -200),
        );
        await screenshot('empty');
        final unreadable = LocalMemoryStore(
          directory: () async => throw const FileSystemException('unavailable'),
        );
        addTearDown(unreadable.dispose);
        await tester.pumpWidget(page(unreadable));
        await tester.pumpAndSettle();
        await tester.dragUntilVisible(
          find.text('重新读取文件').hitTestable(),
          scroller,
          const Offset(0, -200),
        );
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) => widget is IconButton && widget.tooltip == '添加记忆',
                ),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await screenshot('read-error');
      },
    );
  }
}
