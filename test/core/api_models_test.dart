import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'model upgrades replace stale voices without changing PCM transport',
    () {
      final capabilities = VoiceCapabilities.fromJson({
        'stt_model': 'qwen-audio-3.1-asr-flash-message',
        'tts_model': 'qwen-audio-3.1-tts-flash',
        'voice_catalog_model': 'qwen-audio-3.1-tts-flash',
        'voices': ['longanhuan_v3.1', 'longanlingxin_v3.1'],
        'default_voice': 'longanhuan_v3.1',
        'input_format': 'pcm16_16000_mono',
        'output_format': 'pcm16_24000_mono',
      });
      expect(capabilities.selectVoice('Cherry'), 'longanhuan_v3.1');
      expect(
        capabilities.selectVoice('longanlingxin_v3.1'),
        'longanlingxin_v3.1',
      );
      expect(capabilities.hasCompatibleAudioFormats, isTrue);
      expect(capabilities.hasMatchingVoiceCatalog, isTrue);
      expect(capabilities.sttModel, 'qwen-audio-3.1-asr-flash-message');
    },
  );

  test('detects mismatched catalogs and incompatible output audio', () {
    final capabilities = VoiceCapabilities.fromJson({
      'tts_model': 'new-model',
      'voice_catalog_model': 'old-model',
      'output_format': 'mp3',
    });
    expect(capabilities.hasCompatibleAudioFormats, isFalse);
    expect(capabilities.hasMatchingVoiceCatalog, isFalse);
    expect(capabilities.selectVoice('Cherry'), isNull);
    expect(VoiceCapabilities.fromJson({}).hasCompatibleAudioFormats, isTrue);
    expect(VoiceCapabilities.fromJson({}).hasMatchingVoiceCatalog, isTrue);
  });

  test('Chinese chat only offers voices supporting Chinese', () {
    final capabilities = VoiceCapabilities.fromJson({
      'voices': ['english-only', 'chinese'],
      'default_voice': 'english-only',
      'voice_options': [
        {
          'id': 'english-only',
          'name': '英语音色',
          'languages': ['en'],
        },
        {
          'id': 'chinese',
          'name': '中文音色',
          'languages': ['zh'],
        },
      ],
    });
    expect(capabilities.voices, ['chinese']);
    expect(capabilities.defaultVoice, 'chinese');
  });

  test('honors backend defaults and never remaps an existing thread', () {
    final capabilities = VoiceCapabilities.fromJson({
      'default_agent': 'mem0-chatbot',
      'agents': [
        {'id': 'chatbot'},
        {'id': 'mem0-chatbot'},
      ],
    });
    expect(capabilities.defaultAgentId, 'mem0-chatbot');
    expect(capabilities.selectAgent(null)?.id, 'mem0-chatbot');
    expect(
      capabilities.selectAgent('chatbot', hasExistingThread: true)?.id,
      'chatbot',
    );
    expect(
      capabilities.selectAgent('removed-agent', hasExistingThread: true),
      isNull,
    );
    expect(capabilities.selectAgent('removed-agent')?.id, 'mem0-chatbot');
  });

  test('legacy and unavailable defaults fall back to an advertised agent', () {
    for (final advertised in [null, 'removed-agent']) {
      final capabilities = VoiceCapabilities.fromJson({
        'default_agent': advertised,
        'agents': [
          {'id': 'research-assistant'},
          {'id': 'chatbot'},
        ],
      });
      expect(capabilities.defaultAgentId, 'chatbot');
    }
    expect(
      VoiceCapabilities.fromJson({
        'agents': [
          {'id': 'research-assistant'},
        ],
      }).defaultAgentId,
      'research-assistant',
    );
    expect(VoiceCapabilities.fromJson({}).defaultAgentId, isNull);
  });

  test(
    'parses each memory status without interpreting SDK output as saved facts',
    () {
      for (final entry in {
        'disabled': MemoryStatus.disabled,
        'saved': MemoryStatus.saved,
        'saved_search_failed': MemoryStatus.savedSearchFailed,
        'write_failed': MemoryStatus.writeFailed,
      }.entries) {
        final item = ChatItem.fromJson({
          'type': 'ai',
          'content': '回答',
          'response_metadata': {'memory_status': entry.key},
        });
        expect(item.memoryStatus, entry.value);
        expect(item.content, '回答');
      }
      expect(
        ChatItem.fromJson({
          'type': 'ai',
          'response_metadata': {'memory_status': 'future-status'},
        }).memoryStatus,
        isNull,
      );
      expect(ChatItem.fromJson({'type': 'ai'}).memoryStatus, isNull);
      expect(MemoryStatus.saved.label, '记忆处理完成');
      expect(MemoryStatus.writeFailed.hasWarning, isTrue);
    },
  );

  test('parses structured voice metadata and configured default', () {
    final capabilities = VoiceCapabilities.fromJson(<String, dynamic>{
      'enabled': true,
      'protocol_version': 1,
      'voices': <String>['Cherry', 'Serena'],
      'default_voice': 'Serena',
      'voice_options': <Map<String, String>>[
        <String, String>{
          'id': 'Cherry',
          'name': '芊悦',
          'description': '阳光积极、亲切自然',
        },
        <String, String>{'id': 'Serena', 'name': '苏瑶', 'description': '温柔自然'},
      ],
      'agents': <Object?>[],
      'wake_word': <String, Object>{
        'enabled': true,
        'keyword': '小美',
        'confirm_with_asr': true,
        'pre_roll_ms': 1200,
        'kws_score': 1.0,
        'kws_threshold': 0.5,
      },
      'client_vad': <String, Object>{
        'enabled': true,
        'rms_dbfs': -42,
        'speech_frames': 3,
      },
      'audio_metrics_seconds': 5,
    });

    expect(capabilities.voices, <String>['Cherry', 'Serena']);
    expect(capabilities.defaultVoice, 'Serena');
    expect(capabilities.voiceOptions.first.displayName, '芊悦 · Cherry');
    expect(capabilities.voiceOption('Serena')?.name, '苏瑶');
    expect(capabilities.voiceOption('Serena')?.description, '温柔自然');
    expect(capabilities.wakeWord.enabled, isTrue);
    expect(capabilities.wakeWord.keyword, '小美');
    expect(capabilities.wakeWord.preRollMs, 1200);
    expect(capabilities.clientVad.rmsDbfs, -42);
    expect(capabilities.clientVad.speechFrames, 3);
    expect(capabilities.audioMetricsSeconds, 5);
  });

  test('falls back to legacy voice ids and the first valid default', () {
    final capabilities = VoiceCapabilities.fromJson(<String, dynamic>{
      'enabled': true,
      'protocol_version': 1,
      'voices': <String>['Cherry', 'Serena'],
      'default_voice': 'Unknown',
      'agents': <Object?>[],
    });

    expect(capabilities.defaultVoice, 'Cherry');
    expect(capabilities.voiceOptions, hasLength(2));
    expect(capabilities.voiceOptions.first.name, 'Cherry');
    expect(capabilities.voiceOptions.first.description, isEmpty);
    expect(capabilities.wakeWord.enabled, isFalse);
  });

  test('uses structured options when a future backend omits legacy ids', () {
    final capabilities = VoiceCapabilities.fromJson(<String, dynamic>{
      'enabled': true,
      'protocol_version': 1,
      'voice_options': <Map<String, String>>[
        <String, String>{'id': 'Maia', 'name': '四月'},
      ],
      'agents': <Object?>[],
    });

    expect(capabilities.voices, <String>['Maia']);
    expect(capabilities.defaultVoice, 'Maia');
  });
}
