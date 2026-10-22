import '../../../core/api/video_reference.dart';

class VideoDraft {
  const VideoDraft({
    required this.prompt,
    this.model = 'happyhorse-1.1-t2v',
    this.resolution = '1080P',
    this.ratio = '16:9',
    this.duration = 5,
    this.watermark = true,
    this.seed,
    this.title,
    this.coverUrl,
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
  final String? title, coverUrl;

  static String? titleError(String? value) =>
      value != null && value.runes.length > 200 ? '视频标题最多 200 个字符' : null;

  static String? coverError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (text.runes.length > 2048) return '封面地址最多 2048 个字符';
    return VideoReference.imageUri(text) == null
        ? '请输入有效的 HTTP/HTTPS 封面地址'
        : null;
  }

  String? get validationError {
    if (titleError(title) case final error?) return error;
    if (coverError(coverUrl) case final error?) return error;
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
    if (title?.trim().isNotEmpty == true) 'title': title!.trim(),
    if (coverUrl?.trim().isNotEmpty == true) 'cover_url': coverUrl!.trim(),
    'model': model,
    'resolution': resolution,
    'ratio': ratio,
    'duration': duration,
    'watermark': watermark,
    if (seed != null) 'seed': seed,
  };
}

class VideoTask extends VideoReference {
  const VideoTask({
    required int id,
    required super.status,
    required super.storageStatus,
    required this.createdAt,
    required this.updatedAt,
    this.taskId,
    super.videoUrl,
    super.errorCode,
    super.title,
    super.coverUrl,
  }) : super(recordId: id);

  int get id => recordId;
  final String? taskId;
  final DateTime createdAt, updatedAt;

  factory VideoTask.fromJson(Map<String, dynamic> json) => VideoTask(
    id: json['id'] as int,
    status: json['status'] as String,
    storageStatus: json['storage_status'] as String,
    taskId: json['task_id'] as String?,
    videoUrl: json['qiniu_video_url'] as String?,
    title: json['title'] as String?,
    coverUrl: json['cover_url'] as String?,
    errorCode: json['error_code'] as String?,
    createdAt: DateTime.parse(json['create_time'] as String),
    updatedAt: DateTime.parse(json['update_time'] as String),
  );
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
