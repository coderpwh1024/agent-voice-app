import 'package:agent_voice_app/core/audio/wake_phrase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wake display removes repeated calls and punctuation', () {
    for (final text in <String>[
      '小美小美，介绍一下你自己',
      ' 小 美！小美，小美、小美：介绍一下你自己',
      '小美小美小美介绍一下你自己',
    ]) {
      expect(stripWakePrefix(text, defaultWakeKeyword), '介绍一下你自己');
    }
    expect(stripWakePrefix('小美，小美，小美。', defaultWakeKeyword), isEmpty);
    expect(stripWakePrefix('小美小美，介绍小美的功能', defaultWakeKeyword), '介绍小美的功能');
    expect(stripWakePrefix('请叫小美小美', defaultWakeKeyword), '请叫小美小美');
  });

  test('legacy and custom wake keywords remain compatible', () {
    expect(stripWakePrefix('小美，小美，查天气', '小美'), '查天气');
    expect(stripWakePrefix('你好助手，你好助手，查天气', '你好助手'), '查天气');
    expect(normalizeWakeKeyword('小美， 小美。'), defaultWakeKeyword);
    expect(stripWakePrefix('查天气', ''), '查天气');
  });
}
