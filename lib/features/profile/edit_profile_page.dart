import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/config/app_config.dart';
import 'profile_avatar.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.config, required this.user});

  final AppConfig config;
  final AuthUser user;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  static const _maxImageBytes = 5 * 1024 * 1024;

  late final TextEditingController _nickname;
  final _picker = ImagePicker();
  Uint8List? _imageBytes;
  String? _imageName;
  String? _imageContentType;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: widget.user.nickname);
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 90,
      );
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxImageBytes) {
        setState(() => _error = '头像不能超过 5 MB，请选择更小的图片');
        return;
      }
      final contentType = _detectImageType(bytes);
      if (contentType == null) {
        setState(() => _error = '仅支持 JPEG、PNG、GIF 或 WebP 图片');
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _imageBytes = bytes;
        _imageName = file.name;
        _imageContentType = contentType;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = '无法读取照片，请检查相册访问权限');
      }
    }
  }

  String? _detectImageType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 6) {
      final signature = String.fromCharCodes(bytes.take(6));
      if (signature == 'GIF87a' || signature == 'GIF89a') {
        return 'image/gif';
      }
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final nickname = _nickname.text.trim();
    if (nickname.isEmpty) {
      setState(() => _error = '昵称不能为空');
      return;
    }
    if (nickname.characters.length > 64) {
      setState(() => _error = '昵称最多 64 个字符');
      return;
    }
    final nicknameChanged = nickname != widget.user.nickname;
    if (!nicknameChanged && _imageBytes == null) {
      Navigator.pop(context, widget.user);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final client = AgentApiClient(widget.config);
    try {
      final updated = await client.updateCurrentUser(
        nickname: nicknameChanged ? nickname : null,
        imageBytes: _imageBytes,
        imageName: _imageName,
        imageContentType: _imageContentType,
      );
      if (mounted) {
        Navigator.pop(context, updated);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _friendlyError(Object error) {
    if (error is ApiException) {
      return switch (error.statusCode) {
        401 => '登录已过期，请重新登录',
        413 => '头像不能超过 5 MB',
        415 => '头像格式不受支持，请重新选择',
        422 => '昵称格式不正确，请检查后重试',
        502 => '头像上传服务暂时不可用',
        _ => error.message,
      };
    }
    return '保存失败，请稍后重试';
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
          '编辑个人资料',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text(
              '完成',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 36),
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Hero(
                    tag: 'profile-avatar',
                    child: ProfileAvatar(
                      nickname: _nickname.text,
                      imageUrl: widget.user.imageUrl,
                      imageBytes: _imageBytes,
                      size: 118,
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: 2,
                    child: Material(
                      color: const Color(0xff17151a),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _saving ? null : _pickImage,
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.photo_camera_outlined,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _saving ? null : _pickImage,
              child: const Text('更换头像'),
            ),
            const SizedBox(height: 24),
            Text(
              '公开资料',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),
            _EditCard(
              children: [
                TextField(
                  controller: _nickname,
                  enabled: !_saving,
                  maxLength: 64,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: const InputDecoration(
                    labelText: '昵称',
                    hintText: '给自己取一个好记的名字',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.mail_outline_rounded),
                  title: const Text('登录邮箱'),
                  subtitle: Text(widget.user.email),
                  trailing: const Icon(Icons.lock_outline_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '邮箱用于验证身份，暂不支持修改。新头像会经过安全上传并同步到你的账户。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xffffeef1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xffc12f4c)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xff8d1f36)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff17151a),
                foregroundColor: Colors.white,
              ),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('保存更改'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditCard extends StatelessWidget {
  const _EditCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: const Color(0x141b1520),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xffece9ef)),
      ),
      child: Column(children: children),
    );
  }
}
