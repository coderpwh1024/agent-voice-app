import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editorial_widgets.dart';

String recordDateLabel(String recordDate, {DateTime? now}) {
  final date = DateTime.parse('${recordDate}T00:00:00Z');
  final utcNow = (now ?? DateTime.now()).toUtc();
  final today = DateTime.utc(utcNow.year, utcNow.month, utcNow.day);
  final days = today.difference(date).inDays;
  if (days == 0) return '今天';
  if (days == 1) return '昨天';
  return '${date.month}月${date.day}日';
}

String recordWeekday(DateTime date) =>
    const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][date.weekday - 1];

String recordTime(DateTime date) {
  final utc = date.toUtc();
  return '${utc.hour.toString().padLeft(2, '0')}:${utc.minute.toString().padLeft(2, '0')}';
}

String recordAgentName(String agentId) => switch (agentId) {
  'mem0-chatbot' => 'Mem0 · 小美',
  'chatbot' => '小美',
  'research-assistant' => '研究助手',
  'rag-assistant' => '知识助手',
  'supervisor' => '协作助手',
  'github-mcp-agent' => 'GitHub 助手',
  _ => agentId,
};

class MemoryStatusNote extends StatelessWidget {
  const MemoryStatusNote({super.key, required this.status});

  final MemoryStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    final color = status.hasWarning ? palette.accent : palette.muted;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            status.hasWarning
                ? Icons.info_outline_rounded
                : Icons.psychology_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              status.label,
              style: TextStyle(color: color, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

String recordErrorMessage(Object error) {
  if (error is ApiException) {
    return switch (error.statusCode) {
      401 => '登录已过期，请返回个人主页重新登录。',
      403 => '当前账号无法访问这段记录，请确认登录账号。',
      404 => '暂时找不到这份记录，请刷新后重试。',
      422 => '这份记录已超出最近 30 天的范围，请返回列表刷新。',
      0 => error.message,
      _ => '服务器暂时无法读取聊天记录，请稍后重试。',
    };
  }
  return '暂时无法读取聊天记录，请稍后重试。';
}

class RecordPalette extends AppPalette {
  RecordPalette(super.context);
  Color get accent => accentInk;
  Color get lavender => blush;
}

class RecordLayout extends StatelessWidget {
  const RecordLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SafeArea(top: false, child: EditorialLayout(child: child));
}

class RecordHero extends StatelessWidget {
  const RecordHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    this.stats = const [],
  });

  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final List<String> stats;

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditorialHeading(eyebrow: eyebrow, title: title, subtitle: description),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: stats.map((label) => RecordTag(label: label)).toList(),
          ),
        ],
        const SizedBox(height: 24),
        Divider(color: palette.border, height: 1),
      ],
    );
  }
}

class RecordTag extends StatelessWidget {
  const RecordTag({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: palette.blush,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.ink,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class RecordStatus extends StatelessWidget {
  const RecordStatus({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: palette.blush,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: palette.accent, size: 32),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              color: palette.ink,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, height: 1.7),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重新加载'),
            ),
          ],
        ],
      ),
    );
  }
}

class RecordLoading extends StatelessWidget {
  const RecordLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            label: '正在加载聊天记录',
            child: const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        for (var index = 0; index < 3; index++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 12, width: 100, color: palette.border),
                      const SizedBox(height: 12),
                      Container(height: 10, width: 160, color: palette.border),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
