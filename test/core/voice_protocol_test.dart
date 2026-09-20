import 'dart:typed_data';

import 'package:agent_voice_app/core/api/voice_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const connectionId = '00112233-4455-6677-8899-aabbccddeeff';

  test('encodes the backend 45-byte input frame contract', () {
    final frame = encodeInputAudioFrame(
      pcm: Uint8List.fromList(<int>[0x34, 0x12, 0xcd, 0xab]),
      connectionId: connectionId,
      sequence: 7,
    );

    expect(frame.length, audioHeaderBytes + 4);
    expect(String.fromCharCodes(frame.sublist(0, 4)), 'VCE1');
    expect(frame[4], 1);
    expect(frame.sublist(5, 21), <int>[
      0x00,
      0x11,
      0x22,
      0x33,
      0x44,
      0x55,
      0x66,
      0x77,
      0x88,
      0x99,
      0xaa,
      0xbb,
      0xcc,
      0xdd,
      0xee,
      0xff,
    ]);
    expect(frame.sublist(21, 37), everyElement(0));
    expect(ByteData.sublistView(frame).getUint32(41), 7);
    expect(frame.sublist(45), <int>[0x34, 0x12, 0xcd, 0xab]);
  });

  test('decodes and preserves little-endian PCM output payload', () {
    final frame = Uint8List(audioHeaderBytes + 4);
    frame.setRange(0, 4, 'VCE1'.codeUnits);
    frame[4] = 2;
    frame.setRange(5, 21, <int>[
      0x00,
      0x11,
      0x22,
      0x33,
      0x44,
      0x55,
      0x66,
      0x77,
      0x88,
      0x99,
      0xaa,
      0xbb,
      0xcc,
      0xdd,
      0xee,
      0xff,
    ]);
    frame.setRange(21, 37, <int>[
      0xff,
      0xee,
      0xdd,
      0xcc,
      0xbb,
      0xaa,
      0x99,
      0x88,
      0x77,
      0x66,
      0x55,
      0x44,
      0x33,
      0x22,
      0x11,
      0x00,
    ]);
    final data = ByteData.sublistView(frame);
    data.setUint32(37, 3);
    data.setUint32(41, 42);
    frame.setRange(45, 49, <int>[0x34, 0x12, 0xcd, 0xab]);

    final decoded = decodeOutputAudioFrame(frame);
    expect(decoded.connectionId, connectionId);
    expect(decoded.responseId, 'ffeeddcc-bbaa-9988-7766-554433221100');
    expect(decoded.segmentIndex, 3);
    expect(decoded.sequence, 42);
    expect(decoded.pcm, <int>[0x34, 0x12, 0xcd, 0xab]);
  });

  test('rejects malformed payloads', () {
    expect(
      () => encodeInputAudioFrame(
        pcm: Uint8List(3),
        connectionId: connectionId,
        sequence: 0,
      ),
      throwsFormatException,
    );
    expect(() => decodeOutputAudioFrame(Uint8List(10)), throwsFormatException);
  });

  test('client events use unique UUID identifiers', () {
    final first = clientEvent('ping');
    final second = clientEvent('ping');

    expect(first['event_id'], isNot(second['event_id']));
    expect(
      first['event_id'],
      matches(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'),
      ),
    );
  });
}
