import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'features/settings/settings_sheet.dart';
import 'features/voice_session/voice_home_page.dart';
import 'features/voice_session/voice_session_controller.dart';

class AgentVoiceApp extends StatefulWidget {
  const AgentVoiceApp({super.key});

  @override
  State<AgentVoiceApp> createState() => _AgentVoiceAppState();
}

class _AgentVoiceAppState extends State<AgentVoiceApp> {
  late final VoiceSessionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VoiceSessionController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _showSettings(BuildContext context) async {
    final config = await showModalBottomSheet<AppConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SettingsSheet(config: _controller.config),
    );
    if (config == null) {
      return;
    }
    _controller.updateConfig(config);
    if (config.isComplete) {
      try {
        await _controller.loadCapabilities();
      } catch (_) {
        // The controller exposes the actionable error in the page.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agent Voice',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff4169e1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff7c9cff),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
        ),
      ),
      home: VoiceHomePage(
        controller: _controller,
        onOpenSettings: _showSettings,
      ),
    );
  }
}
