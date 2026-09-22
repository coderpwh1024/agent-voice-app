import 'dart:async';

import 'package:flutter/material.dart';

import 'core/api/api_models.dart';
import 'core/auth/auth_session_store.dart';
import 'core/config/app_config.dart';
import 'features/auth/auth_page.dart';
import 'features/settings/settings_sheet.dart';
import 'features/voice_session/voice_home_page.dart';
import 'features/voice_session/voice_session_controller.dart';

class AgentVoiceApp extends StatefulWidget {
  const AgentVoiceApp({
    super.key,
    this.sessionStore = const AuthSessionStore(),
  });

  final AuthSessionStore sessionStore;

  @override
  State<AgentVoiceApp> createState() => _AgentVoiceAppState();
}

class _AgentVoiceAppState extends State<AgentVoiceApp> {
  late final VoiceSessionController _controller;
  late final AuthSessionStore _sessionStore;
  AuthUser? _currentUser;
  bool _restoringSession = true;

  @override
  void initState() {
    super.initState();
    _sessionStore = widget.sessionStore;
    _controller = VoiceSessionController();
    unawaited(_restoreSession());
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
      builder: (_) => SettingsSheet(
        config: _controller.config,
        user: _currentUser,
        onLogout: _logout,
      ),
    );
    if (config == null) {
      return;
    }
    _controller.updateConfig(config);
    unawaited(_persistBaseUrl(config.baseUrl));
    if (config.isComplete) {
      try {
        await _controller.loadCapabilities();
      } catch (_) {
        // The controller exposes the actionable error in the page.
      }
    }
  }

  Future<void> _restoreSession() async {
    final defaults = _controller.config;
    if (defaults.isComplete) {
      _currentUser = AuthUser(
        id: int.tryParse(defaults.userId) ?? 0,
        nickname: '开发用户',
        email: '',
      );
      if (mounted) {
        setState(() => _restoringSession = false);
      }
      unawaited(_loadCapabilities());
      return;
    }
    final saved = await _sessionStore.read();
    if (!mounted) {
      return;
    }
    if (saved != null) {
      _controller.updateConfig(saved.config);
      _currentUser = saved.user;
      unawaited(_loadCapabilities());
    }
    setState(() => _restoringSession = false);
  }

  Future<void> _loadCapabilities() async {
    try {
      await _controller.loadCapabilities();
    } catch (_) {
      // The home page exposes backend availability without invalidating login.
    }
  }

  Future<void> _authenticated(EmailAuthResult result, String baseUrl) async {
    final config = AppConfig(
      baseUrl: baseUrl,
      accessToken: result.accessToken,
      userId: result.user.id.toString(),
    );
    _controller.updateConfig(config);
    try {
      await _sessionStore.save(config: config, result: result);
    } catch (_) {
      // Keep the authenticated in-memory session if secure persistence fails.
    }
    if (!mounted) {
      return;
    }
    setState(() => _currentUser = result.user);
    unawaited(_loadCapabilities());
  }

  Future<void> _logout() async {
    await _controller.disconnect();
    try {
      await _sessionStore.clear();
    } catch (_) {
      // Logout must still clear the active in-memory credentials.
    }
    final loggedOut = AppConfig(
      baseUrl: _controller.config.baseUrl,
      accessToken: '',
      userId: '',
    );
    _controller.updateConfig(loggedOut);
    if (mounted) {
      setState(() => _currentUser = null);
    }
  }

  Future<void> _persistBaseUrl(String baseUrl) async {
    try {
      await _sessionStore.updateBaseUrl(baseUrl);
    } catch (_) {
      // The current session already uses the new address.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agent Voice',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff6157f5),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff8f8fc),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xffdfe1eb)),
          ),
          filled: true,
          fillColor: const Color(0xfff7f7fb),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
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
      home: _restoringSession
          ? const _SessionSplash()
          : _currentUser == null
          ? AuthPage(
              baseUrl: _controller.config.baseUrl,
              onAuthenticated: _authenticated,
            )
          : VoiceHomePage(
              controller: _controller,
              onOpenSettings: _showSettings,
            ),
    );
  }
}

class _SessionSplash extends StatelessWidget {
  const _SessionSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq_rounded, size: 54),
            SizedBox(height: 20),
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
