import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/voice_session/voice_home_page.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class CapabilitiesController extends VoiceSessionController {
  CapabilitiesController(this.data)
    : super(
        config: const AppConfig(
          baseUrl: 'http://127.0.0.1:8000',
          accessToken: 'test-token',
          userId: '42',
        ),
      );

  final Map<String, dynamic> data;
  int clearCount = 0;
  VoiceSession? activeSession;

  @override
  VoiceCapabilities get capabilities => VoiceCapabilities.fromJson(data);

  @override
  VoiceSession? get session => activeSession;

  @override
  Future<void> connect({
    required String agentId,
    required String voice,
    String? threadId,
  }) async {
    activeSession = VoiceSession(
      sessionId: 'test-session',
      threadId: 'new-mem0-thread',
      agentId: agentId,
      voice: voice,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
    notifyListeners();
  }

  void redraw() => notifyListeners();

  @override
  void clearConversation() {
    clearCount++;
    activeSession = null;
    super.clearConversation();
  }
}

void main() {
  testWidgets(
    'home follows the server Mem0 default and respects an explicit legacy selection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = CapabilitiesController({
        'enabled': true,
        'protocol_version': 1,
        'default_agent': 'mem0-chatbot',
        'voices': ['Cherry'],
        'agents': [
          {
            'id': 'chatbot',
            'speech_mode': 'streaming',
            'cancel_execution': true,
          },
          {
            'id': 'mem0-chatbot',
            'speech_mode': 'streaming',
            'cancel_execution': true,
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: VoiceHomePage(
            controller: controller,
            user: const AuthUser(id: 42, nickname: 'tester', email: ''),
            onOpenProfile: (_) async {},
            onOpenSettings: (_) async {},
          ),
        ),
      );
      await tester.pump();
      Finder agentField() => find.byType(DropdownButtonFormField<String>).first;
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(agentField())
            .initialValue,
        'mem0-chatbot',
      );
      expect(find.textContaining('Mem0'), findsWidgets);
      expect(tester.getSize(agentField()).width, greaterThan(300));
      await tester.ensureVisible(find.text('现在开始说话'));
      await tester.tap(find.text('现在开始说话'));
      await tester.pump();
      controller.redraw();
      await tester.pump();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(agentField())
            .initialValue,
        'mem0-chatbot',
      );
      await tester.ensureVisible(agentField());
      await tester.tap(agentField());
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Mem0'), findsWidgets);
      await tester.tap(find.text('小美').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(agentField())
            .initialValue,
        'chatbot',
      );
      expect(controller.clearCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
