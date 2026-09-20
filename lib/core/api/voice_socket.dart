import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class VoiceSocket {
  VoiceSocket._(this._socket);

  final WebSocket _socket;
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Uint8List> _audio =
      StreamController<Uint8List>.broadcast();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  StreamSubscription<dynamic>? _subscription;

  Stream<Map<String, dynamic>> get events => _events.stream;
  Stream<Uint8List> get audio => _audio.stream;
  Stream<Object> get errors => _errors.stream;

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
              _events.add(decoded);
            } else {
              throw const FormatException('Voice event must be a JSON object');
            }
          } else if (value is List<int>) {
            _audio.add(Uint8List.fromList(value));
          }
        } catch (error, stackTrace) {
          _errors.add(error);
          _events.addError(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _errors.add(error);
        _events.addError(error, stackTrace);
      },
      onDone: () {
        if (!_events.isClosed) {
          _events.add(<String, dynamic>{
            'type': 'socket.closed',
            'code': _socket.closeCode,
            'reason': _socket.closeReason,
          });
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
    await _events.close();
    await _audio.close();
    await _errors.close();
  }
}
