class VideoDraft {
  const VideoDraft({
    required this.prompt,
    this.model = 'happyhorse-1.1-t2v',
    this.resolution = '1080P',
    this.ratio = '16:9',
    this.duration = 5,
    this.watermark = true,
    this.seed,
  });

  static const models = ['happyhorse-1.1-t2v', 'happyhorse-1.0-t2v'];
  static const ratios = [
    '16:9',
    '9:16',
    '1:1',
    '4:3',
    '3:4',
    '4:5',
    '5:4',
    '9:21',
    '21:9',
  ];
  final String prompt, model, resolution, ratio;
  final int duration;
  final bool watermark;
  final int? seed;

  String? get validationError {
    final text = prompt.trim();
    if (text.isEmpty) return '写下你想看见的画面';
    if (text.runes.length > 5000) return '描述最多 5000 个字符';
    if (text.runes.where((r) => r >= 0x4e00 && r <= 0x9fff).length > 2500) {
      return '中文描述最多 2500 字';
    }
    if (!models.contains(model) ||
        !ratios.contains(ratio) ||
        !['480P', '720P', '1080P'].contains(resolution)) {
      return '请选择有效的生成参数';
    }
    if (model == models.last && resolution == '480P') {
      return 'HappyHorse 1.0 不支持 480P';
    }
    if (duration < 3 || duration > 15) return '时长需要在 3–15 秒之间';
    if (seed != null && (seed! < 0 || seed! > 2147483647)) {
      return '种子需要在 0–2147483647 之间';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'prompt': prompt.trim(),
    'model': model,
    'resolution': resolution,
    'ratio': ratio,
    'duration': duration,
    'watermark': watermark,
    if (seed != null) 'seed': seed,
  };
}

class VideoTask {
  const VideoTask({
    required this.id,
    required this.status,
    required this.storageStatus,
    required this.createdAt,
    required this.updatedAt,
    this.taskId,
    this.videoUrl,
    this.errorCode,
  });
  final int id;
  final String status, storageStatus;
  final String? taskId, videoUrl, errorCode;
  final DateTime createdAt, updatedAt;

  factory VideoTask.fromJson(Map<String, dynamic> json) => VideoTask(
    id: json['id'] as int,
    status: json['status'] as String,
    storageStatus: json['storage_status'] as String,
    taskId: json['task_id'] as String?,
    videoUrl: json['qiniu_video_url'] as String?,
    errorCode: json['error_code'] as String?,
    createdAt: DateTime.parse(json['create_time'] as String),
    updatedAt: DateTime.parse(json['update_time'] as String),
  );

  Uri? get playableUri {
    final uri = Uri.tryParse(videoUrl ?? '');
    return status == 'SUCCEEDED' &&
            storageStatus == 'STORED' &&
            uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty
        ? uri
        : null;
  }

  bool get shouldPoll =>
      ['SUBMITTING', 'PENDING', 'RUNNING'].contains(status) ||
      (status == 'SUCCEEDED' && storageStatus != 'STORED');
  String get label => switch (status) {
    'SUBMITTING' => '正在提交',
    'SUBMISSION_UNKNOWN' => '提交待核实',
    'PENDING' => '排队中',
    'RUNNING' => '生成中',
    'SUCCEEDED' => switch (storageStatus) {
      'STORED' => '已完成',
      'FAILED' => '保存待重试',
      _ => '正在保存',
    },
    'FAILED' => '生成失败',
    'CANCELED' => '已取消',
    'UNKNOWN' => '任务已失效',
    _ => '状态待确认',
  };
  String get description => switch (status) {
    'SUBMITTING' => '任务已记录，正在确认提交结果。',
    'SUBMISSION_UNKNOWN' => '提交结果尚不确定，请核实当前任务，避免重复生成。',
    'PENDING' => '灵感已就位，等待开始生成。可以离开，稍后在作品中查看。',
    'RUNNING' => '正在把文字变成流动的画面。可以离开，稍后再来看。',
    'SUCCEEDED' => switch (storageStatus) {
      'STORED' => '画面已生成并保存，点击播放，看看你的灵感。',
      'FAILED' => '视频已生成，保存暂未完成。后台会继续尝试，也可刷新查询。',
      _ => '视频已生成，正在保存。保存完成后即可播放。',
    },
    'FAILED' => '这次生成未能完成。请核对任务状态和描述后，再决定是否新建。',
    'CANCELED' => '生成任务已由服务端取消。',
    'UNKNOWN' => '上游任务不存在或已过期，请联系服务管理员核实。',
    _ => '暂时无法识别当前状态，请稍后刷新查询。',
  };
}

class VideoTaskPage {
  const VideoTaskPage({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
  });
  final List<VideoTask> items;
  final int total, page, totalPages;
  bool get hasMore => page < totalPages;
  factory VideoTaskPage.fromJson(Map<String, dynamic> json) => VideoTaskPage(
    items: (json['items'] as List)
        .map((v) => VideoTask.fromJson(v as Map<String, dynamic>))
        .toList(),
    total: json['total'] as int,
    page: json['page'] as int,
    totalPages: json['total_pages'] as int,
  );
}
