const defaultWakeKeyword = '小美小美';

const _wakeSeparators = r'[\s，,。！？!?、；;：:．.…]*';

String normalizeWakeKeyword(String keyword) =>
    keyword.replaceAll(RegExp(_wakeSeparators), '');

String stripWakePrefix(String text, String keyword) {
  final normalized = normalizeWakeKeyword(keyword);
  if (normalized.isEmpty) return text.trim();
  final unit = normalized == defaultWakeKeyword || normalized == '小美'
      ? '小美'
      : normalized;
  final phrase = unit.split('').map(RegExp.escape).join(_wakeSeparators);
  return text
      .replaceFirst(RegExp('^$_wakeSeparators(?:$phrase$_wakeSeparators)+'), '')
      .trim();
}
