import '../../../core/api/image_task.dart';

export '../../../core/api/image_task.dart';

class ImageTaskPage {
  const ImageTaskPage(
    this.items, {
    required this.page,
    required this.totalPages,
  });

  final List<ImageTask> items;
  final int page, totalPages;

  factory ImageTaskPage.fromJson(Map<String, dynamic> data) {
    final items = data['items'];
    final page = data['page'];
    final totalPages = data['total_pages'];
    if (items is! List ||
        page is! int ||
        page < 1 ||
        totalPages is! int ||
        totalPages < 0) {
      throw const FormatException('Invalid image task page');
    }
    return ImageTaskPage(
      [for (final item in items) ?ImageTask.tryParse(item)],
      page: page,
      totalPages: totalPages,
    );
  }
}

enum ImageCanvasSize {
  automatic(null, '自动'),
  square('1024*1024', '正方形 1:1'),
  landscape('1344*768', '横向 7:4'),
  portrait('768*1344', '纵向 4:7');

  const ImageCanvasSize(this.value, this.label);
  final String? value;
  final String label;
}

class ImageDraft {
  const ImageDraft({
    required this.prompt,
    this.title,
    this.sourceFileIds = const [],
    this.size = ImageCanvasSize.automatic,
  });

  static const maxPromptLength = 4000;
  static const maxTitleLength = 200;
  final String prompt;
  final String? title;
  final List<int> sourceFileIds;
  final ImageCanvasSize size;

  String? validate({required bool hasSourceImage}) {
    if (prompt.trim().isEmpty || prompt.trim().runes.length > maxPromptLength) {
      return '请填写 1–$maxPromptLength 个字符的画面描述';
    }
    if ((title?.trim().runes.length ?? 0) > maxTitleLength) {
      return '标题最多 $maxTitleLength 个字符';
    }
    if (sourceFileIds.length > (hasSourceImage ? 2 : 3) ||
        sourceFileIds.any((id) => id < 1) ||
        sourceFileIds.toSet().length != sourceFileIds.length) {
      return '参考图数量或文件编号无效';
    }
    return null;
  }

  Map<String, Object?> toJson() {
    final cleanTitle = title?.trim();
    return {
      'prompt': prompt.trim(),
      if (cleanTitle != null && cleanTitle.isNotEmpty) 'title': cleanTitle,
      if (sourceFileIds.isNotEmpty) 'source_file_ids': sourceFileIds,
      'size': ?size.value,
    };
  }
}
