import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../conversations/chat_record_widgets.dart';

bool memoryWriteUncertain(Object error) =>
    error is! ApiException || const [0, 503, 504].contains(error.statusCode);

String memoryErrorMessage(Object error, {bool writing = false}) {
  if (writing && memoryWriteUncertain(error)) {
    return '操作结果暂时无法确认，可能已在服务器完成。请刷新核对后再操作，避免重复提交。';
  }
  if (error is ApiException) {
    return switch (error.statusCode) {
      401 => '登录已过期，请返回个人主页重新登录。',
      403 => '当前账号没有权限访问这条记忆。',
      404 => '这条记忆已不存在，请返回列表刷新。',
      422 => '内容或请求格式不符合要求，请检查后重试。',
      503 => '长期记忆暂时不可用，服务可能未启用或正在忙碌。请稍后刷新。',
      504 => '服务器响应超时，请稍后刷新。',
      0 => '无法连接服务器，请检查网络与服务地址后重试。',
      _ => '暂时无法读取记忆，请稍后刷新。',
    };
  }
  return '暂时无法读取记忆，请稍后刷新。';
}

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

class MemoryPageFooter extends StatelessWidget {
  const MemoryPageFooter({
    super.key,
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
    this.error,
  });
  final bool hasMore;
  final bool loading;
  final VoidCallback onLoadMore;
  final Object? error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      children: [
        if (error != null) ...[
          MemoryNotice(message: memoryErrorMessage(error!), error: true),
          const SizedBox(height: 12),
        ],
        if (loading)
          const MemoryLoading()
        else if (hasMore)
          OutlinedButton.icon(
            onPressed: onLoadMore,
            icon: Icon(
              error == null ? Icons.expand_more_rounded : Icons.refresh_rounded,
            ),
            label: Text(error == null ? '加载更多' : '重试加载更多'),
          )
        else
          Text(
            '已经看到全部',
            style: TextStyle(color: RecordPalette(context).muted, fontSize: 12),
          ),
      ],
    ),
  );
}

Future<bool> confirmMemoryDeletion(
  BuildContext context, {
  required bool all,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(all ? '清空全部长期记忆？' : '删除这条记忆？'),
        content: Text(
          all
              ? '这会删除当前账号在 Mem0 · 小美中的全部长期记忆，包括尚未加载的记忆，无法恢复。\n\n历史对话会保留，之后的聊天仍可能生成新的记忆。'
              : '这条长期记忆将从助手的记忆中移除，无法恢复。历史对话与变更记录会保留。',
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(all ? '确认清空全部记忆' : '确认删除'),
          ),
        ],
      ),
    ) ??
    false;
