import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:agent_voice_app/features/images/data/image_api.dart';
import 'package:agent_voice_app/features/images/image_widgets.dart';
import 'package:agent_voice_app/features/voice_session/voice_home_page.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/backend_auth.dart';

class VoicePreview extends VoiceSessionController {
  VoicePreview({required super.config});

  @override
  bool get wakeWordEnabled => true;

  @override
  Future<void> disableWakeWord() async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('USB reads a real image and opens independent creation routes', (
    tester,
  ) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final config = await backendTestConfig();
    final api = AgentApiClient(config);
    final images = ImageApi(config, client: api);
    final voice = VoicePreview(config: config);
    addTearDown(api.close);
    addTearDown(voice.dispose);
    final user = await api.currentUser();
    final page = await images.list();
    const targetId = int.fromEnvironment('IMAGE_TEST_ID');
    final task = page.items.firstWhere(
      (item) =>
          item.resultUri != null && (targetId == 0 || item.id == targetId),
    );
    final detail = await images.detail(task.id);
    expect(detail.resultUri, isNotNull);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: VoiceHomePage(
          controller: voice,
          user: user,
          onOpenProfile: (_) async {},
          onOpenSettings: (_) async {},
        ),
      ),
    );
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('image-entry');

    final direct = find.byTooltip('图像工作室');
    if (direct.evaluate().isNotEmpty) {
      await tester.tap(direct);
    } else {
      await tester.tap(find.byTooltip('创作工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('图像工作室'));
    }
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(task.id)),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final galleryTile = find.byKey(ValueKey(task.id));
    await expectRenderedImage(tester, galleryTile);
    await binding.takeScreenshot('image-gallery');
    await tester.tap(galleryTile);
    await tester.pumpAndSettle();
    expect(find.text('图像详情'), findsOneWidget);

    await expectRenderedImage(tester, find.byType(ImagePreview).first);
    await binding.takeScreenshot('image-detail');

    await tester.scrollUntilVisible(
      find.text('继续编辑'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('修改描述'), findsOneWidget);
    await expectRenderedImage(tester, find.byType(ImagePreview).first);
    await binding.takeScreenshot('image-edit');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('新建图像'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('新建图像'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('image-choose-asset')), findsOneWidget);
    await binding.takeScreenshot('image-create');
    expect(tester.takeException(), isNull);
  });
}

Future<void> expectRenderedImage(WidgetTester tester, Finder parent) async {
  final imageFinder = find.descendant(of: parent, matching: find.byType(Image));
  expect(imageFinder, findsOneWidget);
  final provider = tester.widget<Image>(imageFinder).image;
  Object? loadError;
  await precacheImage(
    provider,
    tester.element(imageFinder),
    onError: (error, _) => loadError = error,
  );
  expect(loadError, isNull);
  await tester.pumpAndSettle();
  final rawImage = find.descendant(
    of: imageFinder,
    matching: find.byType(RawImage),
  );
  expect(tester.renderObject<RenderImage>(rawImage).image, isNotNull);
}
