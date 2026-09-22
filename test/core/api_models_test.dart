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
    });

    expect(capabilities.voices, <String>['Cherry', 'Serena']);
    expect(capabilities.defaultVoice, 'Serena');
    expect(capabilities.voiceOptions.first.displayName, '芊悦 · Cherry');
    expect(capabilities.voiceOption('Serena')?.name, '苏瑶');
    expect(capabilities.voiceOption('Serena')?.description, '温柔自然');
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
