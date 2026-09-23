import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

sealed class VoiceSocketMessage {
  const VoiceSocketMessage();
}

final class VoiceSocketEventMessage extends VoiceSocketMessage {
  const VoiceSocketEventMessage(this.event);

  final Map<String, dynamic> event;
}

final class VoiceSocketAudioMessage extends VoiceSocketMessage {
  const VoiceSocketAudioMessage(this.bytes);

  final Uint8List bytes;
}

class VoiceSocket {
  VoiceSocket._(this._socket);

  final WebSocket _socket;
  final StreamController<VoiceSocketMessage> _messages =
      StreamController<VoiceSocketMessage>();
  StreamSubscription<dynamic>? _subscription;

  Stream<VoiceSocketMessage> get messages => _messages.stream;

  static Future<VoiceSocket> connect(
    Uri uri, {
    required Map<String, dynamic> headers,
  }) async {
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: headers,
      compression: CompressionOptions.compressionOff,
    ).timeout(const Duration(seconds: 12));
    final result = VoiceSocket._(socket);
    result._listen();
    return result;
  }

  void _listen() {
    _subscription = _socket.listen(
      (dynamic value) {
        try {
          if (value is String) {
            final decoded = jsonDecode(value);
            if (decoded is Map<String, dynamic>) {
              _messages.add(VoiceSocketEventMessage(decoded));
            } else {
              throw const FormatException('Voice event must be a JSON object');
            }
          } else if (value is List<int>) {
            _messages.add(VoiceSocketAudioMessage(Uint8List.fromList(value)));
          }
        } catch (error, stackTrace) {
          _messages.addError(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _messages.addError(error, stackTrace);
      },
      onDone: () {
        if (!_messages.isClosed) {
          _messages.add(
            VoiceSocketEventMessage(<String, dynamic>{
              'type': 'socket.closed',
              'code': _socket.closeCode,
              'reason': _socket.closeReason,
            }),
          );
        }
      },
      cancelOnError: false,
    );
  }

  void sendJson(Map<String, Object?> value) => _socket.add(jsonEncode(value));

  void sendAudio(Uint8List bytes) => _socket.add(bytes);

  Future<void> close([
    int code = WebSocketStatus.normalClosure,
    String? reason,
  ]) async {
    await _socket.close(code, reason);
    await _subscription?.cancel();
    await _messages.close();
  }
}
