import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/config/app_config.dart';
import 'edit_profile_page.dart';
import 'profile_avatar.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.config,
    required this.initialUser,
    required this.onUserChanged,
    required this.onOpenSettings,
    required this.onLogout,
  });

  final AppConfig config;
  final AuthUser initialUser;
  final Future<void> Function(AuthUser user) onUserChanged;
  final Future<void> Function(BuildContext context) onOpenSettings;
  final Future<void> Function() onLogout;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late AuthUser _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user = widget.initialUser;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _error = null);
    final client = AgentApiClient(widget.config);
    try {
      final user = await client.currentUser();
      if (!mounted) {
        return;
      }
      setState(() => _user = user);
      await widget.onUserChanged(user);
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

  String _friendlyError(Object error) {
    if (error is ApiException) {
      return switch (error.statusCode) {
        401 => '登录已过期，请重新登录',
        404 => '没有找到当前用户资料',
        503 => '用户资料服务暂时不可用',
        _ => error.message,
      };
    }
    return '暂时无法获取资料，请下拉重试';
  }

  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<AuthUser>(
      MaterialPageRoute<AuthUser>(
        builder: (_) => EditProfilePage(config: widget.config, user: _user),
      ),
    );
    if (updated == null || !mounted) {
      return;
    }
    setState(() => _user = updated);
    await widget.onUserChanged(updated);
  }

  Future<void> _logout() async {
    await widget.onLogout();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xfffbfafc),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '个人主页',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '刷新资料',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xfffff8fc), Color(0xfffbfafc)],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 40),
            children: [
              Center(
                child: Hero(
                  tag: 'profile-avatar',
                  child: ProfileAvatar(
                    nickname: _user.nickname,
                    imageUrl: _user.imageUrl,
                    size: 112,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _user.nickname,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _user.email.isEmpty ? '开发账户' : _user.email,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xffefebff),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 16,
                        color: Color(0xff6941c6),
                      ),
                      SizedBox(width: 6),
                      Text(
                        '邮箱已验证',
                        style: TextStyle(
                          color: Color(0xff5f3aae),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _edit,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xff17151a),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      label: const Text('编辑个人资料'),
                    ),
                  ),
                ],
              ),
              if (_loading) ...[
                const SizedBox(height: 18),
                const LinearProgressIndicator(
                  minHeight: 2,
                  borderRadius: BorderRadius.all(Radius.circular(99)),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 18),
                _StatusCard(message: _error!, onRetry: _refresh),
              ],
              const SizedBox(height: 26),
              Text(
                '账户信息',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _ProfileCard(
                children: [
                  _InfoRow(
                    icon: Icons.badge_outlined,
                    label: '用户 ID',
                    value: '#${_user.id.toString().padLeft(6, '0')}',
                  ),
                  const _CardDivider(),
                  _InfoRow(
                    icon: Icons.mail_outline_rounded,
                    label: '登录邮箱',
                    value: _user.email.isEmpty ? '开发账户' : _user.email,
                  ),
                  const _CardDivider(),
                  const _InfoRow(
                    icon: Icons.shield_outlined,
                    label: '账户安全',
                    value: '系统安全存储',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '更多',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _ProfileCard(
                children: [
                  _ActionRow(
                    icon: Icons.tune_rounded,
                    label: '连接设置',
                    onTap: () => widget.onOpenSettings(context),
                  ),
                  const _CardDivider(),
                  _ActionRow(
                    icon: Icons.logout_rounded,
                    label: '退出登录',
                    destructive: true,
                    onTap: _logout,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 1,
      shadowColor: const Color(0x14211529),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xffece9ef)),
      ),
      child: Column(children: children),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 56, endIndent: 16);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Icon(icon, size: 21, color: const Color(0xff6d6672)),
          const SizedBox(width: 18),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xffd43654) : null;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: color),
      onTap: onTap,
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xffffeef1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, color: Color(0xffc12f4c)),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
