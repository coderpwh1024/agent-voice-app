import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.config});

  final AppConfig config;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _token;
  late final TextEditingController _userId;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.config.baseUrl);
    _token = TextEditingController(text: widget.config.accessToken);
    _userId = TextEditingController(text: widget.config.userId);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _token.dispose();
    _userId.dispose();
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
                'Token 只保存在本次进程内，不会把后端 AUTH_SECRET 写入安装包。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _baseUrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '后端地址',
                  hintText: 'http://10.0.2.2:8080',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _token,
                obscureText: !_showToken,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'App access token',
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showToken = !_showToken),
                    icon: Icon(
                      _showToken ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _userId,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'user_id（历史列表需要）',
                  prefixIcon: Icon(Icons.person_outline),
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
                      accessToken: _token.text.trim(),
                      userId: _userId.text.trim(),
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
