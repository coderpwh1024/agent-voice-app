import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/api/voice_protocol.dart';
import '../../core/api/voice_socket.dart';
import '../../core/audio/audio_bridge.dart';
import '../../core/config/app_config.dart';

enum VoiceConnectionState {
  disconnected,
  connecting,
  ready,
  listening,
  thinking,
  speaking,
}

class ConversationEntry {
  const ConversationEntry({
    required this.role,
    required this.text,
    this.responseId,
  });

  final String role;
  final String text;
  final String? responseId;

  ConversationEntry copyWith({String? text}) => ConversationEntry(
    role: role,
    text: text ?? this.text,
    responseId: responseId,
  );
}

class ApprovalPrompt {
  const ApprovalPrompt({required this.interruptId, required this.value});

  final String interruptId;
  final Object? value;
}

class VoiceSessionController extends ChangeNotifier {
  VoiceSessionController({AppConfig? config, AudioBridge? audio})
    : _config = config ?? AppConfig.defaults(),
      _audio = audio ?? NativeAudioBridge() {
    _api = AgentApiClient(_config);
  }

  AppConfig _config;
  late AgentApiClient _api;
  final AudioBridge _audio;
  VoiceSocket? _socket;
  VoiceSession? _session;
  VoiceCapabilities? _capabilities;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  StreamSubscription<Uint8List>? _socketAudioSubscription;
  StreamSubscription<Uint8List>? _microphoneSubscription;
  StreamSubscription<Map<String, dynamic>>? _playbackSubscription;
  Completer<void>? _readyCompleter;
  int _inputSequence = 0;
  String? _connectionId;
  String? _currentResponseId;
  String _partialTranscript = '';
  String? _error;
  VoiceConnectionState _state = VoiceConnectionState.disconnected;
  final Set<String> _invalidResponses = <String>{};
  final Map<String, int> _assistantIndexes = <String, int>{};
  final List<ConversationEntry> _messages = <ConversationEntry>[];
  ApprovalPrompt? _approval;
  bool _disposed = false;

  AppConfig get config => _config;
  VoiceConnectionState get state => _state;
  VoiceCapabilities? get capabilities => _capabilities;
  VoiceSession? get session => _session;
  String get partialTranscript => _partialTranscript;
  String? get error => _error;
  String? get currentResponseId => _currentResponseId;
  List<ConversationEntry> get messages => List.unmodifiable(_messages);
  ApprovalPrompt? get approval => _approval;
  bool get isConnected => _connectionId != null && _socket != null;

  void updateConfig(AppConfig config) {
    if (isConnected) {
      throw StateError('请先断开当前语音会话');
    }
    _api.close();
    _config = config;
    _api = AgentApiClient(config);
    _capabilities = null;
    _error = null;
    notifyListeners();
  }

  Future<void> loadCapabilities() async {
    _setState(VoiceConnectionState.connecting);
    try {
      _ensureConfigured();
      final value = await _api.capabilities();
      if (!value.enabled) {
        throw const ApiException(503, '后端实时语音功能未启用');
      }
      if (value.protocolVersion != voiceProtocolVersion) {
        throw ApiException(
          0,
          '协议版本不兼容：App=$voiceProtocolVersion，后端=${value.protocolVersion}',
        );
      }
      _capabilities = value;
      _error = null;
    } catch (error) {
      _recordError(error);
      rethrow;
    } finally {
      if (!isConnected) {
        _setState(VoiceConnectionState.disconnected);
      }
    }
  }

  Future<void> connect({
    required String agentId,
    required String voice,
    String? threadId,
  }) async {
    if (_state != VoiceConnectionState.disconnected) {
      return;
    }
    _ensureConfigured();
    _setState(VoiceConnectionState.connecting);
    _error = null;
    try {
      if (_capabilities == null) {
        await loadCapabilities();
        _setState(VoiceConnectionState.connecting);
      }
      final granted = await _audio.requestMicrophonePermission();
      if (!granted) {
        throw StateError('没有麦克风权限，无法启动实时语音');
      }
      _session = await _api.createVoiceSession(
        agentId: agentId,
        voice: voice,
        threadId: threadId,
      );
      final socket = await VoiceSocket.connect(
        _api.websocketUri(_session!.sessionId),
        headers: _api.websocketHeaders(),
      );
      _socket = socket;
      _readyCompleter = Completer<void>();
      _eventSubscription = socket.events.listen(
        (event) => unawaited(_handleEvent(event)),
        onError: _recordError,
      );
      _socketAudioSubscription = socket.audio.listen(
        (bytes) => unawaited(_handleAudio(bytes)),
        onError: _recordError,
      );
      _microphoneSubscription = _audio.microphoneFrames.listen(
        _handleMicrophone,
        onError: _recordError,
      );
      _playbackSubscription = _audio.playbackEvents.listen(
        _handlePlaybackEvent,
        onError: _recordError,
      );
      socket.sendJson(
        clientEvent('session.configure', <String, Object?>{
          'protocol_version': voiceProtocolVersion,
          'input_format': 'pcm16_16000_mono',
          'output_format': 'pcm16_24000_mono',
        }),
      );
      await _readyCompleter!.future.timeout(const Duration(seconds: 12));
      await _audio.start();
      _setState(VoiceConnectionState.listening);
    } catch (error) {
      _recordError(error);
      await _teardown(sendClose: false);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _teardown(sendClose: true);
  }

  Future<void> reconnect() async {
    final previous = _session;
    if (previous == null) {
      return;
    }
    final agentId = previous.agentId;
    final voice = previous.voice;
    final threadId = previous.threadId;
    await _teardown(sendClose: false, preserveSession: true);
    await connect(agentId: agentId, voice: voice, threadId: threadId);
  }

  void sendText(String text) {
    final normalized = text.trim();
    if (!isConnected || normalized.isEmpty) {
      return;
    }
    _messages.add(ConversationEntry(role: 'human', text: normalized));
    _socket!.sendJson(
      clientEvent('input.text', <String, Object?>{'text': normalized}),
    );
    _setState(VoiceConnectionState.thinking);
  }

  Future<void> cancelCurrent() async {
    final responseId = _currentResponseId;
    if (responseId == null || !isConnected) {
      return;
    }
    _invalidResponses.add(responseId);
    await _audio.cancel(responseId);
    _socket!.sendJson(
      clientEvent('response.cancel', <String, Object?>{
        'response_id': responseId,
      }),
    );
    _setState(VoiceConnectionState.listening);
  }

  Future<void> speechHint() async {
    if (!isConnected) {
      return;
    }
    await _audio.pause();
    _socket!.sendJson(clientEvent('input.speech_hint'));
  }

  void submitApproval(Object? value) {
    final prompt = _approval;
    if (!isConnected || prompt == null) {
      return;
    }
    _socket!.sendJson(
      clientEvent('approval.submit', <String, Object?>{
        'interrupt_id': prompt.interruptId,
        'value': value,
      }),
    );
    _approval = null;
    _setState(VoiceConnectionState.thinking);
  }

  Future<List<ThreadSummary>> threads(String agentId) => _api.threads(agentId);

  Future<void> loadHistory(String agentId, String threadId) async {
    final history = await _api.history(agentId, threadId);
    _messages
      ..clear()
      ..addAll(
        history.map(
          (item) => ConversationEntry(role: item.role, text: item.content),
        ),
      );
    notifyListeners();
  }

  Future<void> _handleEvent(Map<String, dynamic> event) async {
    final type = event['type'] as String? ?? '';
    final responseId = event['response_id'] as String?;
    if (responseId != null &&
        _invalidResponses.contains(responseId) &&
        const <String>{
          'text.delta',
          'audio.segment.started',
          'audio.segment.done',
          'response.started',
        }.contains(type)) {
      return;
    }
    switch (type) {
      case 'session.ready':
        _connectionId = event['connection_id'] as String;
        _inputSequence = 0;
        _readyCompleter?.complete();
        _setState(VoiceConnectionState.ready);
      case 'input.started':
        _setState(VoiceConnectionState.listening);
      case 'transcript.partial':
        _partialTranscript = event['text'] as String? ?? '';
        notifyListeners();
      case 'transcript.final':
        final text = event['text'] as String? ?? '';
        _partialTranscript = '';
        if (text.trim().isNotEmpty) {
          _messages.add(ConversationEntry(role: 'human', text: text.trim()));
        }
        _setState(VoiceConnectionState.thinking);
      case 'response.started':
        _currentResponseId = responseId;
        if (responseId != null) {
          _assistantIndexes[responseId] = _messages.length;
          _messages.add(
            ConversationEntry(role: 'ai', text: '', responseId: responseId),
          );
        }
        _setState(VoiceConnectionState.thinking);
      case 'text.delta':
        if (responseId != null) {
          final index = _assistantIndexes[responseId];
          if (index != null && index < _messages.length) {
            _messages[index] = _messages[index].copyWith(
              text: '${_messages[index].text}${event['text'] as String? ?? ''}',
            );
          }
        }
        _setState(VoiceConnectionState.speaking);
      case 'audio.segment.done':
        if (responseId != null) {
          await _audio.completeSegment(
            responseId: responseId,
            segmentIndex: event['segment_index'] as int,
            samples: event['samples'] as int,
          );
        }
      case 'response.cancelled':
        if (responseId != null) {
          _invalidResponses.add(responseId);
          await _audio.cancel(responseId);
        }
        _setState(VoiceConnectionState.listening);
      case 'response.done':
        if (responseId != null && !_invalidResponses.contains(responseId)) {
          await _audio.completeResponse(responseId);
        }
        _setState(VoiceConnectionState.listening);
      case 'playback.resume':
        if (responseId != null && !_invalidResponses.contains(responseId)) {
          await _audio.resume();
          _setState(VoiceConnectionState.speaking);
        }
      case 'approval.required':
        _approval = ApprovalPrompt(
          interruptId: event['interrupt_id'] as String,
          value: event['value'],
        );
        notifyListeners();
      case 'error':
        _recordError(event['code']?.toString() ?? '未知语音错误');
      case 'session.closed':
      case 'socket.closed':
        await _teardown(sendClose: false);
    }
  }

  Future<void> _handleAudio(Uint8List bytes) async {
    try {
      final frame = decodeOutputAudioFrame(bytes);
      if (frame.connectionId != _connectionId ||
          _invalidResponses.contains(frame.responseId)) {
        return;
      }
      await _audio.enqueue(
        frame.pcm,
        responseId: frame.responseId,
        segmentIndex: frame.segmentIndex,
      );
      _setState(VoiceConnectionState.speaking);
    } catch (error) {
      _recordError(error);
    }
  }

  void _handleMicrophone(Uint8List bytes) {
    final connectionId = _connectionId;
    final socket = _socket;
    if (connectionId == null || socket == null) {
      return;
    }
    var offset = 0;
    while (offset < bytes.length) {
      final remaining = bytes.length - offset;
      var length = remaining > maxAudioPayloadBytes
          ? maxAudioPayloadBytes
          : remaining;
      if (length.isOdd) {
        length--;
      }
      if (length <= 0) {
        break;
      }
      final pcm = Uint8List.sublistView(bytes, offset, offset + length);
      socket.sendAudio(
        encodeInputAudioFrame(
          pcm: pcm,
          connectionId: connectionId,
          sequence: _inputSequence++,
        ),
      );
      offset += length;
    }
  }

  void _handlePlaybackEvent(Map<String, dynamic> event) {
    if (!isConnected) {
      return;
    }
    final responseId = event['responseId'] as String?;
    if (responseId == null || _invalidResponses.contains(responseId)) {
      return;
    }
    switch (event['type']) {
      case 'segment.completed':
        _socket!.sendJson(
          clientEvent('playback.progress', <String, Object?>{
            'response_id': responseId,
            'segment_index': event['segmentIndex'] as int,
            'played_samples': event['playedSamples'] as int,
          }),
        );
      case 'response.finished':
        _socket!.sendJson(
          clientEvent('playback.finished', <String, Object?>{
            'response_id': responseId,
          }),
        );
        _setState(VoiceConnectionState.listening);
    }
  }

  Future<void> _teardown({
    required bool sendClose,
    bool preserveSession = false,
  }) async {
    final socket = _socket;
    final oldSession = _session;
    _socket = null;
    _connectionId = null;
    _currentResponseId = null;
    _readyCompleter = null;
    if (sendClose && socket != null) {
      socket.sendJson(clientEvent('session.close'));
    }
    await _microphoneSubscription?.cancel();
    await _playbackSubscription?.cancel();
    await _socketAudioSubscription?.cancel();
    await _eventSubscription?.cancel();
    _microphoneSubscription = null;
    _playbackSubscription = null;
    _socketAudioSubscription = null;
    _eventSubscription = null;
    await _audio.stop();
    await socket?.close();
    if (sendClose && oldSession != null) {
      try {
        await _api.closeVoiceSession(oldSession.sessionId);
      } catch (_) {
        // The WebSocket close is authoritative; HTTP cleanup is best effort.
      }
    }
    if (!preserveSession) {
      _session = null;
    }
    _partialTranscript = '';
    _setState(VoiceConnectionState.disconnected);
  }

  void _ensureConfigured() {
    if (!_config.isComplete) {
      throw StateError('请先配置后端地址和 App access token');
    }
  }

  void _recordError(Object error) {
    _error = error.toString().replaceFirst('Bad state: ', '');
    if (!_disposed) {
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setState(VoiceConnectionState value) {
    _state = value;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_teardown(sendClose: true));
    _api.close();
    super.dispose();
  }
}
