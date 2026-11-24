import 'image_models.dart';

enum ImageLoopStatus {
  open('OPEN', '可继续编辑'),
  processing('PROCESSING', '版本处理中'),
  exhausted('EXHAUSTED', '已用完编辑次数'),
  accepted('ACCEPTED', '已定稿'),
  stopped('STOPPED', '已结束'),
  unknown('', '状态待更新');

  const ImageLoopStatus(this.value, this.label);

  final String value, label;
}

enum ImageLoopExit {
  accept('ACCEPTED'),
  stop('STOPPED');

  const ImageLoopExit(this.value);

  final String value;
}

class ImageLoopState {
  const ImageLoopState({
    required this.rootId,
    required this.status,
    required this.usedEdits,
    required this.maxEdits,
    required this.versions,
    this.acceptedId,
  });

  final int rootId, usedEdits, maxEdits;
  final int? acceptedId;
  final ImageLoopStatus status;
  final List<ImageTask> versions;

  bool get canEdit => status == ImageLoopStatus.open && usedEdits < maxEdits;
  bool get canClose => switch (status) {
    ImageLoopStatus.open ||
    ImageLoopStatus.exhausted ||
    ImageLoopStatus.processing => true,
    _ => false,
  };
  bool get shouldPoll =>
      status == ImageLoopStatus.processing ||
      versions.any((item) => item.status.isActive);

  factory ImageLoopState.fromJson(Map<String, dynamic> data) {
    final root = data['root_image_id'];
    final used = data['used_edits'];
    final max = data['max_edits'];
    final state = data['status'];
    final versions = data['versions'];
    final accepted = data['accepted_image_id'];
    if (root is! int ||
        root < 1 ||
        used is! int ||
        used < 0 ||
        max is! int ||
        max < 1 ||
        state is! String ||
        versions is! List ||
        (accepted != null && (accepted is! int || accepted < 1))) {
      throw const FormatException('Invalid image loop');
    }
    return ImageLoopState(
      rootId: root,
      usedEdits: used,
      maxEdits: max,
      status: ImageLoopStatus.values.firstWhere(
        (status) => status.value == state,
        orElse: () => ImageLoopStatus.unknown,
      ),
      acceptedId: accepted as int?,
      versions: List.unmodifiable(
        versions.map(
          (item) =>
              ImageTask.tryParse(item) ??
              (throw const FormatException('Invalid image loop version')),
        ),
      ),
    );
  }
}

class ImageLoopHistory {
  const ImageLoopHistory({
    required this.loop,
    required this.root,
    required this.previewId,
    this.previewUri,
    this.createdAt,
    this.updatedAt,
  });

  final ImageLoopState loop;
  final ImageTask root;
  final int previewId;
  final Uri? previewUri;
  final DateTime? createdAt, updatedAt;

  factory ImageLoopHistory.fromJson(Map<String, dynamic> data) {
    final loop = ImageLoopState.fromJson(data);
    final root = ImageTask.tryParse(data['root_image']);
    final preview = data['preview_image_id'];
    if (root == null ||
        root.id != loop.rootId ||
        preview is! int ||
        preview < 1) {
      throw const FormatException('Invalid image loop history');
    }
    return ImageLoopHistory(
      loop: loop,
      root: root,
      previewId: preview,
      previewUri: ImageTask.parseImageUri(data['preview_image_url']),
      createdAt: _time(data['create_time']),
      updatedAt: _time(data['update_time']),
    );
  }

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

class ImageLoopHistoryPage {
  const ImageLoopHistoryPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  final List<ImageLoopHistory> items;
  final int total, page, pageSize, totalPages;

  factory ImageLoopHistoryPage.fromJson(Map<String, dynamic> data) {
    final items = data['items'];
    final total = data['total'];
    final page = data['page'];
    final size = data['page_size'];
    final pages = data['total_pages'];
    if (items is! List ||
        total is! int ||
        total < 0 ||
        page is! int ||
        page < 1 ||
        size is! int ||
        size < 1 ||
        pages is! int ||
        pages < 0) {
      throw const FormatException('Invalid image loop history page');
    }
    return ImageLoopHistoryPage(
      items: List.unmodifiable(
        items.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Invalid image loop history item');
          }
          return ImageLoopHistory.fromJson(item);
        }),
      ),
      total: total,
      page: page,
      pageSize: size,
      totalPages: pages,
    );
  }
}
