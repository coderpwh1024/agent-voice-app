import 'dart:typed_data';

import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.nickname,
    this.imageUrl,
    this.imageBytes,
    this.size = 88,
    this.ring = true,
  });

  final String nickname;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final ringWidth = ring ? 3.0 : 0.0;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ring
            ? const LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: <Color>[
                  Color(0xfff9ce34),
                  Color(0xffee2a7b),
                  Color(0xff6228d7),
                ],
              )
            : null,
      ),
      child: Container(
        padding: EdgeInsets.all(ring ? 3 : 0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
        ),
        child: ClipOval(child: _image(context)),
      ),
    );
  }

  Widget _image(BuildContext context) {
    final bytes = imageBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }
    final url = imageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final initial =
        nickname.trim().characters.firstOrNull?.toUpperCase() ?? 'U';
    return ColoredBox(
      color: const Color(0xfff0edff),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: const Color(0xff5f3dc4),
            fontSize: size * 0.34,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
