import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
