import 'package:flutter/material.dart';

import '../../core/api/api_models.dart';
import '../../core/config/app_config.dart';

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
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('连接设置', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '登录凭据已加密保存在系统安全存储中。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (widget.user != null) ...[
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(
                      widget.user!.nickname.isEmpty
                          ? 'U'
                          : widget.user!.nickname.characters.first
                                .toUpperCase(),
                    ),
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
                decoration: const InputDecoration(
                  labelText: '后端地址',
                  hintText: 'http://10.0.2.2:8000',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () {
                  final baseUrl = _baseUrl.text.trim();
                  final uri = Uri.tryParse(baseUrl);
                  if (uri == null ||
                      !uri.hasScheme ||
                      !{'http', 'https'}.contains(uri.scheme)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入有效的 http/https 后端地址')),
                    );
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
    );
  }
}
