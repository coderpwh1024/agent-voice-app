class ExecutionStep {
  const ExecutionStep({
    required this.id,
    required this.stage,
    required this.label,
    required this.status,
    this.detail,
    this.durationMs,
  });
  final String id, stage, label, status;
  final String? detail;
  final int? durationMs;
  bool get needsAttention => const [
    'failed',
    'unknown',
    'warning',
    'waiting_input',
    'waiting_confirmation',
  ].contains(status);
  static ExecutionStep? tryParse(Object? value) {
    if (value is! Map ||
        value['step_id'] is! String ||
        value['stage'] is! String ||
        value['label'] is! String ||
        !ExecutionSnapshot.statuses.contains(value['status'])) {
      return null;
    }
    return ExecutionStep(
      id: value['step_id'] as String,
      stage: value['stage'] as String,
      label: value['label'] as String,
      status: value['status'] as String,
      detail: value['detail'] is String ? value['detail'] as String : null,
      durationMs: value['duration_ms'] is int
          ? value['duration_ms'] as int
          : null,
    );
  }
}

class ExecutionConfirmation {
  const ExecutionConfirmation(this.id, this.label, this.expiresAt);
  final String id, label;
  final DateTime expiresAt;
  bool get expired => !expiresAt.isAfter(DateTime.now());
  static ExecutionConfirmation? tryParse(Object? value) {
    if (value is! Map ||
        value['confirmation_id'] is! String ||
        value['label'] is! String) {
      return null;
    }
    final id = value['confirmation_id'] as String;
    final expiry = DateTime.tryParse(value['expires_at']?.toString() ?? '');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) || expiry == null) return null;
    return ExecutionConfirmation(id, value['label'] as String, expiry);
  }
}

class ExecutionSnapshot {
  const ExecutionSnapshot({
    required this.runId,
    required this.messageId,
    required this.sequence,
    required this.status,
    required this.steps,
    this.responseId,
    this.confirmation,
    this.text = '',
    this.video,
  });
  static const statuses = {
    'running',
    'succeeded',
    'warning',
    'failed',
    'cancelled',
    'waiting_input',
    'waiting_confirmation',
    'unknown',
  };
  final String runId, messageId, status, text;
  final String? responseId;
  final int sequence;
  final List<ExecutionStep> steps;
  final ExecutionConfirmation? confirmation;
  final Object? video;
  bool get isRunning => status == 'running';
  bool get needsAttention =>
      steps.any((step) => step.needsAttention) ||
      const [
        'failed',
        'unknown',
        'waiting_input',
        'waiting_confirmation',
      ].contains(status);
  String get label => switch (status) {
    'running' =>
      steps.where((step) => step.status == 'running').lastOrNull?.label ??
          '正在处理',
    'succeeded' =>
      steps.any((step) => step.status == 'warning') ? '已完成，部分步骤需留意' : '已完成',
    'warning' => '部分步骤需留意',
    'failed' => '未能完成',
    'cancelled' => '已结束本次执行',
    'waiting_input' => '等待补充信息',
    'waiting_confirmation' => '等待确认',
    _ => '结果待核实',
  };
  static ExecutionSnapshot? tryParse(Object? value) {
    if (value is! Map ||
        value['type'] != 'execution.progress' ||
        value['version'] != 1 ||
        value['run_id'] is! String ||
        value['message_id'] is! String ||
        value['sequence'] is! int ||
        (value['sequence'] as int) < 0 ||
        !statuses.contains(value['status']) ||
        value['steps'] is! List) {
      return null;
    }
    final raw = value['steps'] as List;
    if (raw.length > 50) return null;
    final steps = raw
        .map(ExecutionStep.tryParse)
        .whereType<ExecutionStep>()
        .toList();
    if (steps.length != raw.length) return null;
    return ExecutionSnapshot(
      runId: value['run_id'] as String,
      messageId: value['message_id'] as String,
      responseId: value['response_id'] is String
          ? value['response_id'] as String
          : null,
      sequence: value['sequence'] as int,
      status: value['status'] as String,
      steps: List.unmodifiable(steps),
      confirmation: ExecutionConfirmation.tryParse(value['confirmation']),
      text: value['text'] is String ? value['text'] as String : '',
      video: value['video'],
    );
  }
}
