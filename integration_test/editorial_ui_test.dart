import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/core/theme/app_theme.dart';
import 'package:agent_voice_app/features/auth/auth_page.dart';
import 'package:agent_voice_app/features/conversations/chat_record_detail_page.dart';
import 'package:agent_voice_app/features/conversations/chat_records_page.dart';
import 'package:agent_voice_app/features/conversations/personal_library_page.dart';
import 'package:agent_voice_app/features/memories/memories_page.dart';
import 'package:agent_voice_app/features/memories/memory_detail_page.dart';
import 'package:agent_voice_app/features/memories/memory_history_page.dart';
import 'package:agent_voice_app/features/profile/edit_profile_page.dart';
import 'package:agent_voice_app/features/profile/profile_page.dart';
import 'package:agent_voice_app/features/settings/settings_sheet.dart';
import 'package:agent_voice_app/features/voice_session/voice_home_page.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/backend_auth.dart';

class _VoicePreview extends VoiceSessionController {
  _VoicePreview({required AppConfig config, required this.abilities})
    : super(config: config);
  final VoiceCapabilities abilities;
  bool conversation = false;
  @override
  VoiceCapabilities get capabilities => abilities;
  @override
  bool get wakeWordEnabled => true;
  @override
  bool get isConnected => conversation;
  @override
  VoiceConnectionState get state => conversation
      ? VoiceConnectionState.listening
      : VoiceConnectionState.wakeListening;
  @override
  List<ConversationEntry> get messages => conversation
      ? const [
          ConversationEntry(role: 'human', text: '今天的阳光很好，想把这些小事慢慢说给你听。'),
          ConversationEntry(role: 'ai', text: '我在听。那些平常又温暖的瞬间，都值得留一点时间。'),
        ]
      : const [];
  @override
  Future<void> disableWakeWord() async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'editorial UI: voice states and read-only account, journal and memory screens',
    (tester) async {
      final config = await backendTestConfig();
      final api = AgentApiClient(config);
      addTearDown(api.close);
      final user = await api.currentUser();
      final abilities = await api.capabilities();
      final agentId = abilities.defaultAgentId ?? abilities.agents.first.id;
      final days = await api.chatRecords(agentId);
      final memories = await api.memories();
      final voice = _VoicePreview(config: config, abilities: abilities);
      addTearDown(voice.dispose);
      var converted = false;
      Widget voicePage() => VoiceHomePage(
        controller: voice,
        user: user,
        onOpenProfile: (_) async {},
        onOpenSettings: (_) async {},
      );
      Future<void> capture(
        String name,
        Widget page, {
        bool dark = false,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(dark ? Brightness.dark : Brightness.light),
            home: page,
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        await binding.takeScreenshot(name);
      }

      await capture('voice-welcome', voicePage());
      await tester.tap(find.byTooltip('对话偏好'));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('voice-preferences');
      await tester.tap(find.byTooltip('关闭对话偏好'));
      await tester.pumpAndSettle();
      voice.conversation = true;
      await capture('voice-conversation', voicePage());
      await capture(
        'profile',
        ProfilePage(
          config: config,
          initialUser: user,
          onUserChanged: (_) async {},
          onOpenSettings: (_) async {},
          onLogout: () async {},
        ),
      );
      await capture(
        'profile-edit',
        EditProfilePage(config: config, user: user),
      );
      await capture(
        'personal-library',
        PersonalLibraryPage(
          config: config,
          agents: abilities.agents,
          initialAgentId: agentId,
          api: api,
        ),
      );
      await capture(
        'chat-records',
        ChatRecordsPage(
          config: config,
          agents: abilities.agents,
          initialAgentId: agentId,
          api: api,
        ),
      );
      if (days.isNotEmpty) {
        await capture(
          'chat-record-detail',
          ChatRecordDetailPage(api: api, agentId: agentId, record: days.first),
        );
      }
      await capture('memories', MemoriesPage(config: config, api: api));
      if (memories.items.isNotEmpty) {
        final memory = memories.items.first;
        await capture(
          'memory-detail',
          MemoryDetailPage(api: api, memoryId: memory.id),
        );
        await capture('memory-edit', MemoryEditPage(api: api, record: memory));
        await capture(
          'memory-history',
          MemoryHistoryPage(api: api, memoryId: memory.id),
        );
      }
      await capture(
        'settings',
        Scaffold(
          body: SettingsSheet(
            config: config,
            user: user,
            onLogout: () async {},
          ),
        ),
      );
      await capture(
        'auth',
        AuthPage(baseUrl: config.baseUrl, onAuthenticated: (_, _) async {}),
      );
      voice.conversation = false;
      await capture('voice-dark', voicePage(), dark: true);
      await capture(
        'profile-dark',
        ProfilePage(
          config: config,
          initialUser: user,
          onUserChanged: (_) async {},
          onOpenSettings: (_) async {},
          onLogout: () async {},
        ),
        dark: true,
      );
      await capture(
        'memories-dark',
        MemoriesPage(config: config, api: api),
        dark: true,
      );
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'read_only_account_journal_memory': true,
        'voice_state_preview': true,
        'voice_network_session_created': false,
        'profile_updated': false,
        'memory_modified': false,
        'base_url': config.baseUrl,
        'light_and_dark': true,
        'memory_detail_available': memories.items.isNotEmpty,
        'chat_detail_available': days.isNotEmpty,
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
