import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/api/video_reference.dart';
import 'package:agent_voice_app/features/voice_session/voice_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> videoSummary({
  String status = 'SUCCEEDED',
  String storage = 'STORED',
  String? url = 'https://cdn.example/videos/happyhorse/clip.mp4',
}) => {
  'title': '海边日落',
  'cover_url': 'https://cdn.example/cover.jpg',
  'record_id': 42,
  'status': status,
  'storage_status': storage,
  'qiniu_video_url': url,
  'error_code': null,
};

void main() {
  test(
    'history metadata and streamed text retain the complete video reference',
    () {
      final item = ChatItem.fromJson({
        'type': 'ai',
        'content': '视频已经好了',
        'response_metadata': {
          'memory_status': 'saved',
          'video': videoSummary(),
        },
      });
      expect(item.video!.recordId, 42);
      expect(item.video!.displayTitle, '海边日落');
      expect(item.video!.coverUri.toString(), 'https://cdn.example/cover.jpg');
      expect(
        item.video!.playableUri.toString(),
        'https://cdn.example/videos/happyhorse/clip.mp4',
      );
      final entry = ConversationEntry(
        role: item.role,
        text: item.content,
        memoryStatus: item.memoryStatus,
        video: item.video,
      );
      expect(entry.copyWith(text: '补充文字').video, same(item.video));
      expect(entry.copyWith(text: '补充文字').memoryStatus, MemoryStatus.saved);
    },
  );
  test('old text-only and malformed metadata remain readable without promoting text URLs', () {
    for (final metadata in [
      null,
      42,
      {'video': 'https://cdn.example/a.mp4'},
      {
        'video': {
          'record_id': '42',
          'status': 'SUCCEEDED',
          'storage_status': 'STORED',
        },
      },
      {
        'video': {'record_id': 42, 'status': 9},
      },
      {
        'video': {
          'record_id': -1,
          'status': 'SUCCEEDED',
          'storage_status': 'STORED',
        },
      },
    ]) {
      final item = ChatItem.fromJson({
        'type': 'ai',
        'content': '完整地址 https://cdn.example/a.mp4',
        'response_metadata': metadata,
      });
      expect(item.content, contains('https://'));
      expect(item.video, isNull);
    }
  });
  test('only generated, archived videos with a usable public URL can play', () {
    for (final data in [
      videoSummary(status: 'RUNNING'),
      videoSummary(storage: 'FAILED'),
      videoSummary(storage: 'PENDING'),
      videoSummary(url: null),
      videoSummary(url: ''),
      videoSummary(url: 'javascript:alert(1)'),
      videoSummary(url: 'file:///a.mp4'),
      videoSummary(url: 'https://name:secret@cdn.example/a.mp4'),
    ]) {
      expect(VideoReference.tryParse(data)!.playableUri, isNull);
    }
    expect(
      VideoReference.tryParse(videoSummary(url: 'http://cdn.example/a.mp4'))!
          .playableUri,
      isNotNull,
    );
    expect(
      VideoReference.tryParse(videoSummary(url: null))!.description,
      contains('地址暂不可用'),
    );
    expect(
      VideoReference.tryParse(videoSummary(status: 'FUTURE_STATE'))!.label,
      '状态待确认',
    );
  });
}
