enum ImageTaskStatus {
  queued('QUEUED', '排队中'),
  submitting('SUBMITTING', '正在提交'),
  pending('PENDING', '排队中'),
  running('RUNNING', '生成中'),
  storing('STORING', '保存到云端'),
  succeeded('SUCCEEDED', '已完成'),
  failed('FAILED', '生成失败'),
  submissionUnknown('SUBMISSION_UNKNOWN', '提交结果待核实'),
  canceled('CANCELED', '已取消'),
  unknown('', '状态待更新');

  const ImageTaskStatus(this.value, this.label);
  final String value;
  final String label;

  bool get isActive => switch (this) {
    queued || submitting || pending || running || storing => true,
    _ => false,
  };

  bool get canDelete => switch (this) {
    succeeded || failed || submissionUnknown || canceled => true,
    _ => false,
  };

  static ImageTaskStatus parse(Object? value) => values.firstWhere(
    (status) => status.value == value,
    orElse: () => unknown,
  );
}

class ImageTask {
  const ImageTask({
    required this.id,
    required this.status,
    this.title,
    this.prompt,
    this.model,
    this.size,
    this.sourceImageId,
    this.imageUri,
    this.errorCode,
    this.createdAt,
    this.loopRootImageId,
    this.loopVersion,
  });

  final int id;
  final ImageTaskStatus status;
  final String? title, prompt, model, size, errorCode;
  final int? sourceImageId, loopRootImageId, loopVersion;
  final Uri? imageUri;
  final DateTime? createdAt;

  String get displayTitle => title ?? '图像 #$id';
  Uri? get resultUri => status == ImageTaskStatus.succeeded ? imageUri : null;

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static Uri? parseImageUri(Object? value) {
    final uri = value is String ? Uri.tryParse(value.trim()) : null;
    return uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.hasAuthority &&
            uri.host.isNotEmpty &&
            !uri.authority.contains('@')
        ? uri
        : null;
  }

  factory ImageTask.fromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final status = data['status'];
    if (id is! int || id <= 0 || status is! String || status.isEmpty) {
      throw const FormatException('Invalid image task');
    }
    return ImageTask(
      id: id,
      status: ImageTaskStatus.parse(status),
      title: _text(data['title']),
      prompt: _text(data['prompt']),
      model: _text(data['model']),
      size: _text(data['size']),
      sourceImageId: _positiveInt(data['source_image_id']),
      imageUri: parseImageUri(data['image_url']),
      errorCode: _text(data['error_code']),
      createdAt: DateTime.tryParse(_text(data['create_time']) ?? ''),
      loopRootImageId: _positiveInt(data['loop_root_image_id']),
      loopVersion: _positiveInt(data['loop_version']),
    );
  }

  static int? _positiveInt(Object? value) =>
      value is int && value > 0 ? value : null;

  static ImageTask? tryParse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    try {
      return ImageTask.fromJson(value);
    } on FormatException {
      return null;
    }
  }
}

class ImageResultPage {
  const ImageResultPage({required this.items, required this.total});

  final List<ImageTask> items;
  final int total;

  static ImageResultPage? tryParse(Object? value) {
    if (value is! Map || value['items'] is! List || value['total'] is! int) {
      return null;
    }
    final raw = value['items'] as List;
    final total = value['total'] as int;
    if (raw.isEmpty || raw.length > 6 || total < raw.length) return null;
    final items = <int, ImageTask>{};
    for (final entry in raw) {
      if (ImageTask.tryParse(entry) case final image?) {
        items.putIfAbsent(image.id, () => image);
      }
    }
    if (items.isEmpty) return null;
    return ImageResultPage(
      items: List.unmodifiable(items.values),
      total: total,
    );
  }
}
