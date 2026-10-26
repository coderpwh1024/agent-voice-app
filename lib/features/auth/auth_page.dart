import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editorial_widgets.dart';

enum AuthMode { login, register }

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.baseUrl,
    required this.onAuthenticated,
  });

  final String baseUrl;
  final Future<void> Function(EmailAuthResult result, String baseUrl)
  onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  late final TextEditingController _serverController;
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();

  AuthMode _mode = AuthMode.login;
  bool _codeSent = false;
  bool _loading = false;
  bool _showServer = false;
  bool _acceptedTerms = false;
  String? _error;
  int _secondsRemaining = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: widget.baseUrl);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _serverController.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  bool get _emailValid =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
          .hasMatch(_emailController.text.trim());

  bool get _serverValid {
    final uri = Uri.tryParse(_serverController.text.trim());
    return uri != null &&
        uri.hasScheme &&
        const <String>{'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty;
  }

  AgentApiClient _client() => AgentApiClient(
    AppConfig(
      baseUrl: _serverController.text.trim(),
      accessToken: '',
      userId: '',
    ),
  );

  Future<void> _sendCode() async {
    if (_loading) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_emailValid) {
      setState(() => _error = '请输入有效的邮箱地址');
      return;
    }
    if (!_serverValid) {
      setState(() {
        _showServer = true;
        _error = '请输入有效的服务地址';
      });
      return;
    }
    if (_mode == AuthMode.register && !_acceptedTerms) {
      setState(() => _error = '请先阅读并同意服务条款与隐私政策');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = _client();
    try {
      final accepted = await client.requestEmailCode(_emailController.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _codeSent = true;
        _secondsRemaining = accepted.expiresInSeconds;
      });
      _startTimer();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _codeFocus.requestFocus(),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyCode() async {
    if (_loading) {
      return;
    }
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = '请输入邮件中的 6 位验证码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = _client();
    try {
      final result = await client.verifyEmailCode(
        email: _emailController.text,
        code: code,
      );
      await widget.onAuthenticated(result, _serverController.text.trim());
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsRemaining <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() => _secondsRemaining = 0);
        }
        return;
      }
      setState(() => _secondsRemaining--);
    });
  }

  void _changeEmail() {
    _timer?.cancel();
    setState(() {
      _codeSent = false;
      _codeController.clear();
      _secondsRemaining = 0;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _emailFocus.requestFocus(),
    );
  }

  String _friendlyError(Object error) {
    if (error is ApiException) {
      return switch (error.statusCode) {
        401 => '验证码错误或已过期，请重新确认',
        429 => '验证码发送次数已达上限，请稍后再试',
        502 => '邮件暂时无法送达，请稍后重试',
        503 => '登录服务暂不可用，请联系管理员',
        _ => error.message,
      };
    }
    return '连接服务失败，请检查网络和服务地址';
  }

  void _setMode(AuthMode value) {
    if (_loading || value == _mode) {
      return;
    }
    _timer?.cancel();
    setState(() {
      _mode = value;
      _codeSent = false;
      _codeController.clear();
      _secondsRemaining = 0;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _BrandHeader(),
                  const SizedBox(height: 32),
                  EditorialPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ModeSelector(mode: _mode, onChanged: _setMode),
                        const SizedBox(height: 24),
                        AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 260),
                          child: _codeSent
                              ? _buildCodeForm(theme)
                              : _buildEmailForm(theme),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SecurityHint(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailForm(ThemeData theme) {
    final registering = _mode == AuthMode.register;
    return Column(
      key: ValueKey('email-${_mode.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          registering ? '创建你的账号' : '欢迎回来',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: .2,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          registering ? '使用邮箱即可注册，无需设置密码' : '输入邮箱，我们会发送一次性验证码',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        TextField(
          key: const ValueKey('emailField'),
          controller: _emailController,
          focusNode: _emailFocus,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _sendCode(),
          decoration: const InputDecoration(
            labelText: '邮箱地址',
            hintText: 'name@example.com',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () => setState(() => _showServer = !_showServer),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          icon: Icon(
            _showServer ? Icons.expand_less_rounded : Icons.tune_rounded,
            size: 18,
          ),
          label: const Text('服务地址'),
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: _showServer
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _serverController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: 'http://127.0.0.1:8000',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (registering)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _acceptedTerms,
                    visualDensity: VisualDensity.compact,
                    onChanged: (value) =>
                        setState(() => _acceptedTerms = value ?? false),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('我已阅读并同意服务条款与隐私政策'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _ErrorMessage(message: _error!),
        ],
        const SizedBox(height: 18),
        FilledButton(
          key: const ValueKey('sendCodeButton'),
          onPressed: _loading ? null : _sendCode,
          child: _loading
              ? const _ButtonProgress()
              : Text(registering ? '获取验证码并注册' : '获取登录验证码'),
        ),
      ],
    );
  }

  Widget _buildCodeForm(ThemeData theme) {
    return Column(
      key: const ValueKey('code-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '修改邮箱',
              onPressed: _loading ? null : _changeEmail,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '查收验证码',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  letterSpacing: .2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '验证码已发送至',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _emailController.text.trim().toLowerCase(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          key: const ValueKey('codeField'),
          controller: _codeController,
          focusNode: _codeFocus,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: 8,
          ),
          onChanged: (value) {
            setState(() => _error = null);
            if (value.length == 6) {
              _verifyCode();
            }
          },
          onSubmitted: (_) => _verifyCode(),
          decoration: const InputDecoration(
            labelText: '6 位验证码',
            hintText: '000000',
            counterText: '',
          ),
          maxLength: 6,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorMessage(message: _error!),
        ],
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('verifyButton'),
          onPressed: _loading ? null : _verifyCode,
          child: _loading
              ? const _ButtonProgress()
              : Text(_mode == AuthMode.register ? '完成注册' : '登录'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _loading || _secondsRemaining > 0 ? null : _sendCode,
          child: Text(
            _secondsRemaining > 0 ? '${_secondsRemaining}s 后可重新发送' : '重新发送验证码',
          ),
        ),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final AuthMode mode;
  final ValueChanged<AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AuthMode>(
      segments: const [
        ButtonSegment(value: AuthMode.login, label: Text('登录')),
        ButtonSegment(value: AuthMode.register, label: Text('注册')),
      ],
      selected: <AuthMode>{mode},
      onSelectionChanged: (value) => onChanged(value.first),
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity(horizontal: 0, vertical: 2),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.graphic_eq_rounded, size: 22, color: palette.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Agent Voice',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        const EditorialHeading(
          eyebrow: 'XIAOMEI / VOICE JOURNAL',
          title: '让每一句话，都有回应。',
          subtitle: '与你的 AI 助手，自然地聊一聊',
        ),
      ],
    );
  }
}

class _SecurityHint extends StatelessWidget {
  const _SecurityHint();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '免密码登录 · 凭据加密保存在本机',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2.2,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}
