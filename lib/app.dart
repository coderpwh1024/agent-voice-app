import 'dart:async';

import 'package:flutter/material.dart';

import 'core/api/api_models.dart';
import 'core/auth/auth_session_store.dart';
import 'core/config/app_config.dart';
import 'features/auth/auth_page.dart';
import 'features/profile/profile_page.dart';
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
    await _controller.disableWakeWord();
    if (!context.mounted) return;
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

  Future<void> _showProfile(BuildContext context) async {
    final user = _currentUser;
    if (user == null) {
      return;
    }
    await _controller.disableWakeWord();
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePage(
          config: _controller.config,
          initialUser: user,
          onUserChanged: _userChanged,
          onOpenSettings: _showSettings,
          onLogout: _logout,
        ),
      ),
    );
  }

  Future<void> _userChanged(AuthUser user) async {
    if (mounted) {
      setState(() => _currentUser = user);
    }
    try {
      await _sessionStore.updateUser(user);
    } catch (_) {
      // The live profile remains available if secure persistence is unavailable.
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
    await _controller.disableWakeWord();
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
          seedColor: const Color(0xffd87568),
          brightness: Brightness.light,
          surface: const Color(0xfffffcfa),
        ),
        scaffoldBackgroundColor: const Color(0xfffbf8f4),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xffeadfd9)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xffd87568), width: 1.4),
          ),
          filled: true,
          fillColor: const Color(0xfffffaf7),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
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
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xfffbf8f4),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Color(0xff3f302c),
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          iconTheme: IconThemeData(color: Color(0xff4b3a35)),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xffeee5df)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffe58b7d),
          brightness: Brightness.dark,
          surface: const Color(0xff211d1b),
        ),
        scaffoldBackgroundColor: const Color(0xff171412),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          filled: true,
          fillColor: const Color(0xff2d2825),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xff171412),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Color(0xfffff8f2),
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          iconTheme: IconThemeData(color: Color(0xfffff8f2)),
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
      home: _restoringSession
          ? const _SessionSplash()
          : _currentUser == null
          ? AuthPage(
              baseUrl: _controller.config.baseUrl,
              onAuthenticated: _authenticated,
            )
          : VoiceHomePage(
              controller: _controller,
              user: _currentUser!,
              onOpenProfile: _showProfile,
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
