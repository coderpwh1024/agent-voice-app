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
    this.firstFrameUrl,
    this.lastFrameUrl,
    this.audio,
    this.promptExtend,
  });

  static const models = [
    'happyhorse-1.1-t2v',
    'happyhorse-1.0-t2v',
    'wan3.0-video',
    'wan3.0-video-prime',
  ];
  static const wanRatios = [
    'adaptive',
    '21:9',
    '16:9',
    '4:3',
    '1:1',
    '3:4',
    '9:16',
  ];
  static bool isWanModel(String model) => model.startsWith('wan3.0-');
  static List<String> ratiosFor(String model) =>
      isWanModel(model) ? wanRatios : ratios;
  static List<String> resolutionsFor(String model) =>
      model == 'happyhorse-1.0-t2v'
      ? ['720P', '1080P']
      : ['480P', '720P', '1080P'];
  bool get isWan => isWanModel(model);
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
  final String? title, coverUrl, firstFrameUrl, lastFrameUrl;
  final bool? audio, promptExtend;

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

  static String? frameError(String? value, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (text.runes.length > 2048) return '$label地址最多 2048 个字符';
    return VideoReference.imageUri(text) == null
        ? '请输入有效的 HTTP/HTTPS $label地址'
        : null;
  }

  static String? seedError(String? value, String model) {
    if (value == null || value.trim().isEmpty) return null;
    final number = int.tryParse(value.trim());
    final wan = isWanModel(model);
    return number == null || number < (wan ? -1 : 0) || number > 2147483647
        ? (wan ? '请输入 -1–2147483647 的整数' : '请输入 0–2147483647 的整数')
        : null;
  }

  String? get promptError {
    final text = prompt.trim();
    if (text.isEmpty && !(isWan && firstFrameUrl?.trim().isNotEmpty == true)) {
      return isWan ? '请填写画面描述或提供首帧图片' : '写下你想看见的画面';
    }
    if (text.runes.length > (isWan ? 20000 : 5000)) {
      return isWan ? '描述最多 20000 个字符' : '描述最多 5000 个字符';
    }
    if (!isWan &&
        text.runes.where((r) => r >= 0x4e00 && r <= 0x9fff).length > 2500) {
      return '中文描述最多 2500 字';
    }
    return null;
  }

  String? get validationError {
    if (titleError(title) case final error?) return error;
    if (coverError(coverUrl) case final error?) return error;
    if (frameError(firstFrameUrl, '首帧') case final error?) return error;
    if (frameError(lastFrameUrl, '尾帧') case final error?) return error;
    if (promptError case final error?) return error;
    if (!models.contains(model) ||
        !ratiosFor(model).contains(ratio) ||
        !resolutionsFor(model).contains(resolution)) {
      return '请选择当前模型支持的生成参数';
    }
    if (isWan) {
      if (lastFrameUrl?.trim().isNotEmpty == true &&
          firstFrameUrl?.trim().isNotEmpty != true) {
        return '提供尾帧时，请同时填写首帧图片地址';
      }
      if (duration != -1 && (duration < 2 || duration > 30)) {
        return '万相时长需要在 2–30 秒之间，或选择智能时长';
      }
    } else {
      if (firstFrameUrl?.trim().isNotEmpty == true ||
          lastFrameUrl?.trim().isNotEmpty == true ||
          audio != null ||
          promptExtend != null) {
        return '首尾帧、音轨和提示词改写仅支持万相 3.0';
      }
      if (duration < 3 || duration > 15) return '时长需要在 3–15 秒之间';
    }
    if (seed != null && (seed! < (isWan ? -1 : 0) || seed! > 2147483647)) {
      return isWan ? '种子需要在 -1–2147483647 之间' : '种子需要在 0–2147483647 之间';
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
    if (firstFrameUrl?.trim().isNotEmpty == true)
      'first_frame_url': firstFrameUrl!.trim(),
    if (lastFrameUrl?.trim().isNotEmpty == true)
      'last_frame_url': lastFrameUrl!.trim(),
    if (audio != null) 'audio': audio,
    if (promptExtend != null) 'prompt_extend': promptExtend,
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
    super.model,
    super.firstFrameUrl,
    super.lastFrameUrl,
  }) : super(recordId: id);

  int get id => recordId;
  final String? taskId;
  final DateTime createdAt, updatedAt;

  factory VideoTask.fromJson(Map<String, dynamic> json) => VideoTask(
    id: json['id'] as int,
    model: json['model'] as String?,
    firstFrameUrl: json['first_frame_url'] as String?,
    lastFrameUrl: json['last_frame_url'] as String?,
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
