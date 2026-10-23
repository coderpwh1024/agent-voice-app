import 'package:flutter/material.dart';

import '../../core/api/api_models.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/editorial_widgets.dart';
import '../profile/profile_avatar.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.config,
    required this.user,
    required this.onLogout,
  });

  final AppConfig config;
  final AuthUser? user;
  final Future<void> Function() onLogout;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _baseUrl;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.config.baseUrl);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: EditorialLayout(
          maxWidth: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const EditorialHeading(
                  eyebrow: 'CONNECTION',
                  title: '连接设置',
                  subtitle: '登录凭据已加密保存在系统安全存储中。',
                ),
                if (widget.user != null) ...[
                  const SizedBox(height: 18),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ProfileAvatar(
                      nickname: widget.user!.nickname,
                      imageUrl: widget.user!.imageUrl,
                      size: 40,
                    ),
                    title: Text(widget.user!.nickname),
                    subtitle: widget.user!.email.isEmpty
                        ? const Text('已登录')
                        : Text(widget.user!.email),
                  ),
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: _baseUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (_) => setState(() => _urlError = null),
                  decoration: InputDecoration(
                    labelText: '后端地址',
                    hintText: 'http://127.0.0.1:8000',
                    prefixIcon: const Icon(Icons.dns_outlined),
                    errorText: _urlError,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () {
                    final baseUrl = _baseUrl.text.trim();
                    final uri = Uri.tryParse(baseUrl);
                    if (uri == null ||
                        !uri.hasScheme ||
                        !{'http', 'https'}.contains(uri.scheme) ||
                        uri.host.isEmpty ||
                        uri.userInfo.isNotEmpty) {
                      setState(() => _urlError = '请输入有效的 http/https 后端地址');
                      return;
                    }
                    Navigator.pop(
                      context,
                      AppConfig(
                        baseUrl: baseUrl,
                        accessToken: widget.config.accessToken,
                        userId: widget.config.userId,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await widget.onLogout();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('退出登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
