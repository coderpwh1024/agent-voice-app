import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

const int voiceProtocolVersion = 1;
const int audioHeaderBytes = 45;
const int maxAudioPayloadBytes = 6400;
const String zeroUuid = '00000000-0000-0000-0000-000000000000';

final Random _secureRandom = Random.secure();

String newEventId() {
  final bytes = Uint8List.fromList(
    List<int>.generate(16, (_) => _secureRandom.nextInt(256)),
  );
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return _uuidFromBytes(bytes);
}

Map<String, Object?> clientEvent(
  String type, [
  Map<String, Object?> data = const {},
]) {
  return <String, Object?>{'type': type, 'event_id': newEventId(), ...data};
}

Uint8List encodeInputAudioFrame({
  required Uint8List pcm,
  required String connectionId,
  required int sequence,
}) {
  if (pcm.isEmpty || pcm.length > maxAudioPayloadBytes || pcm.length.isOdd) {
    throw const FormatException('PCM payload must be 2..6400 even bytes');
  }
  if (sequence < 0 || sequence > 0xffffffff) {
    throw const FormatException('Audio sequence must fit uint32');
  }
  final output = Uint8List(audioHeaderBytes + pcm.length);
  final data = ByteData.sublistView(output);
  output.setRange(0, 4, ascii.encode('VCE1'));
  data.setUint8(4, 1);
  output.setRange(5, 21, _uuidBytes(connectionId));
  output.setRange(21, 37, _uuidBytes(zeroUuid));
  data.setUint32(37, 0, Endian.big);
  data.setUint32(41, sequence, Endian.big);
  output.setRange(audioHeaderBytes, output.length, pcm);
  return output;
}

VoiceAudioFrame decodeOutputAudioFrame(Uint8List bytes) {
  if (bytes.length <= audioHeaderBytes ||
      bytes.length > audioHeaderBytes + maxAudioPayloadBytes) {
    throw const FormatException('Invalid audio frame size');
  }
  final data = ByteData.sublistView(bytes);
  if (ascii.decode(bytes.sublist(0, 4)) != 'VCE1' || data.getUint8(4) != 2) {
    throw const FormatException('Invalid output audio frame');
  }
  final pcm = Uint8List.sublistView(bytes, audioHeaderBytes);
  if (pcm.length.isOdd) {
    throw const FormatException(
      'PCM payload must contain complete int16 samples',
    );
  }
  return VoiceAudioFrame(
    connectionId: _uuidFromBytes(bytes.sublist(5, 21)),
    responseId: _uuidFromBytes(bytes.sublist(21, 37)),
    segmentIndex: data.getUint32(37, Endian.big),
    sequence: data.getUint32(41, Endian.big),
    pcm: Uint8List.fromList(pcm),
  );
}

class VoiceAudioFrame {
  const VoiceAudioFrame({
    required this.connectionId,
    required this.responseId,
    required this.segmentIndex,
    required this.sequence,
    required this.pcm,
  });

  final String connectionId;
  final String responseId;
  final int segmentIndex;
  final int sequence;
  final Uint8List pcm;
}

Uint8List _uuidBytes(String value) {
  final compact = value.replaceAll('-', '');
  if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(compact)) {
    throw const FormatException('Invalid UUID');
  }
  return Uint8List.fromList(
    List<int>.generate(
      16,
      (index) =>
          int.parse(compact.substring(index * 2, index * 2 + 2), radix: 16),
    ),
  );
}

String _uuidFromBytes(List<int> bytes) {
  if (bytes.length != 16) {
    throw const FormatException('UUID must contain 16 bytes');
  }
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
