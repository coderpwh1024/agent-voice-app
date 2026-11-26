import 'package:flutter/material.dart';

import '../conversations/chat_record_widgets.dart';

String memoryDateLabel(String? value) {
  if (value == null) return '时间未记录';
  final date = DateTime.tryParse(value);
  if (date == null) return '时间未记录';
  final local = date.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}.${two(local.month)}.${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class MemoryNotice extends StatelessWidget {
  const MemoryNotice({super.key, required this.message, this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error ? colors.errorContainer : palette.blush,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: error ? colors.onErrorContainer : palette.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: error ? colors.onErrorContainer : palette.ink,
                height: 1.6,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MemoryLoading extends StatelessWidget {
  const MemoryLoading({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(30),
    child: Center(
      child: Semantics(
        label: '正在加载记忆',
        child: const SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  );
}
