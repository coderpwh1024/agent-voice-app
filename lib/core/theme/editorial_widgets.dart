import 'package:flutter/material.dart';

import 'app_theme.dart';

class EditorialHeading extends StatelessWidget {
  const EditorialHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
  });
  final String eyebrow, title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow.isNotEmpty) ...[
          EditorialEyebrow(eyebrow),
          const SizedBox(height: 14),
        ],
        Text(
          title,
          style: TextStyle(
            fontFamily: 'StudioSerif',
            color: p.ink,
            fontSize: 30,
            fontWeight: FontWeight.w400,
            height: 1.5,
            letterSpacing: .5,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          Text(
            subtitle!,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.8),
          ),
        ],
      ],
    );
  }
}

class EditorialEyebrow extends StatelessWidget {
  const EditorialEyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: color ?? AppPalette(context).muted,
      fontSize: 10,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.8,
    ),
  );
}

class EditorialPanel extends StatelessWidget {
  const EditorialPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette(context);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}
