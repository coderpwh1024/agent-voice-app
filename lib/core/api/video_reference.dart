class VideoReference {
  const VideoReference({
    required this.recordId,
    required this.status,
    required this.storageStatus,
    this.videoUrl,
    this.errorCode,
  });

  final int recordId;
  final String status, storageStatus;
  final String? videoUrl, errorCode;

  static VideoReference? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = value['record_id'];
    final status = value['status'];
    final storage = value['storage_status'];
    if (id is! int ||
        id <= 0 ||
        status is! String ||
        status.isEmpty ||
        storage is! String ||
        storage.isEmpty) {
      return null;
    }
    return VideoReference(
      recordId: id,
      status: status,
      storageStatus: storage,
      videoUrl: value['qiniu_video_url'] is String
          ? value['qiniu_video_url'] as String
          : null,
      errorCode: value['error_code'] is String
          ? value['error_code'] as String
          : null,
    );
  }

  Uri? get playableUri {
    final uri = Uri.tryParse(videoUrl ?? '');
    return status == 'SUCCEEDED' &&
            storageStatus == 'STORED' &&
            uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
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
      'STORED' =>
        playableUri != null
            ? '画面已生成并保存，点击播放，看看你的灵感。'
            : '视频已保存，播放地址暂不可用，请在详情中刷新。',
      'FAILED' => '视频已生成，保存暂未完成。后台会继续尝试，也可刷新查询。',
      _ => '视频已生成，正在保存。保存完成后即可播放。',
    },
    'FAILED' => '这次生成未能完成。请核对任务状态和描述后，再决定是否新建。',
    'CANCELED' => '生成任务已由服务端取消。',
    'UNKNOWN' => '上游任务不存在或已过期，请联系服务管理员核实。',
    _ => '暂时无法识别当前状态，请稍后刷新查询。',
  };
}
