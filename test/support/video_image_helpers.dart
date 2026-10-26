import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openVideoImageAddress(WidgetTester tester, String key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  if (key == 'video-cover-url' &&
      find.byKey(Key('$key-address')).evaluate().isEmpty) {
    final cover = find.byKey(const Key('video-custom-cover'));
    await Scrollable.ensureVisible(tester.element(cover), alignment: .3);
    await tester.pumpAndSettle();
    await tester.tap(cover);
    await tester.pumpAndSettle();
  }
  if (find.byKey(Key(key)).evaluate().isEmpty) {
    final toggle = find.byKey(Key('$key-address'));
    await Scrollable.ensureVisible(tester.element(toggle), alignment: .3);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }
  await Scrollable.ensureVisible(
    tester.element(find.byKey(Key(key))),
    alignment: .3,
  );
  await tester.pumpAndSettle();
}
