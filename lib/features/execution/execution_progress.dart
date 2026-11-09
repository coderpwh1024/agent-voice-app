import 'package:flutter/material.dart';

import '../../core/api/execution_models.dart';
import '../../core/theme/app_theme.dart';

class ExecutionProgress extends StatefulWidget {
  const ExecutionProgress({
    super.key,
    required this.execution,
    this.onConfirm,
    this.onRefresh,
    this.refreshError,
  });
  final ExecutionSnapshot execution;
  final VoidCallback? onRefresh;
  final String? refreshError;
  final void Function(String id, bool approved)? onConfirm;
  @override
  State<ExecutionProgress> createState() => _ExecutionProgressState();
}

class _ExecutionProgressState extends State<ExecutionProgress> {
  bool? _expanded;
  String? _submitted;
  @override
  void didUpdateWidget(ExecutionProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onConfirm == null && widget.onConfirm != null) {
      _submitted = null;
    }
    if (oldWidget.execution.runId != widget.execution.runId) {
      _expanded = null;
      _submitted = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final execution = widget.execution;
    final p = AppPalette(context);
    final expanded =
        _expanded ?? (execution.isRunning || execution.needsAttention);
    final confirmation = execution.confirmation;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !expanded),
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  if (execution.isRunning)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else
                    Icon(
                      execution.needsAttention
                          ? Icons.info_outline
                          : Icons.check_rounded,
                      size: 18,
                      color: p.accentInk,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '执行过程 · ${execution.label}',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: p.muted,
                  ),
                ],
              ),
            ),
          ),
          if (widget.refreshError != null)
            Text(
              widget.refreshError!,
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          if (widget.onRefresh != null &&
              (widget.refreshError != null || execution.status == 'unknown'))
            TextButton.icon(
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新执行状态'),
            ),
          if (expanded) ...[
            for (final step in execution.steps)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (step.status) {
                        'running' => Icons.more_horiz,
                        'succeeded' => Icons.check_rounded,
                        'cancelled' => Icons.stop_circle_outlined,
                        'waiting_confirmation' => Icons.fact_check_outlined,
                        'waiting_input' => Icons.chat_bubble_outline,
                        _ => Icons.info_outline,
                      },
                      size: 17,
                      color: step.status == 'failed'
                          ? Theme.of(context).colorScheme.error
                          : p.accentInk,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${step.label} · ${_status(step.status)}',
                            style: TextStyle(color: p.ink, fontSize: 13),
                          ),
                          if (step.detail != null)
                            Text(
                              step.detail!,
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                          if (step.durationMs != null)
                            Text(
                              '${(step.durationMs! / 1000).toStringAsFixed(1)} 秒',
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (confirmation != null) ...[
              const SizedBox(height: 12),
              Text(confirmation.label),
              if (confirmation.expired)
                const Text('确认已过期，请重新发起操作')
              else if (widget.onConfirm != null)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _submitted == confirmation.id
                          ? null
                          : () => _submit(confirmation.id, false),
                      child: const Text('取消操作'),
                    ),
                    FilledButton(
                      onPressed: _submitted == confirmation.id
                          ? null
                          : () => _submit(confirmation.id, true),
                      child: Text(
                        _submitted == confirmation.id ? '正在核实' : '确认操作',
                      ),
                    ),
                  ],
                ),
            ],
            if (execution.status == 'unknown' ||
                execution.steps.any((step) => step.status == 'unknown'))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('请查询业务结果后再决定是否重试。'),
              ),
          ],
        ],
      ),
    );
  }

  void _submit(String id, bool approved) {
    setState(() => _submitted = id);
    widget.onConfirm?.call(id, approved);
  }
}

String _status(String status) => switch (status) {
  'running' => '进行中',
  'succeeded' => '完成',
  'warning' => '需留意',
  'failed' => '失败',
  'cancelled' => '已停止',
  'waiting_input' => '等待补充',
  'waiting_confirmation' => '等待确认',
  _ => '待核实',
};
