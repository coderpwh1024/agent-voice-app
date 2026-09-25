import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/api/voice_protocol.dart';
import '../../core/api/voice_socket.dart';
import '../../core/audio/audio_bridge.dart';
import '../../core/audio/wake_word_detector.dart';
import '../../core/config/app_config.dart';

enum VoiceConnectionState {
  disconnected,
  wakeListening,
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
  VoiceSessionController({
    AppConfig? config,
    AudioBridge? audio,
    WakeWordDetector? wakeWordDetector,
  }) : _config = config ?? AppConfig.defaults(),
       _audio = audio ?? NativeAudioBridge(),
       _wakeWordDetector = wakeWordDetector ?? SherpaWakeWordDetector() {
    _api = AgentApiClient(_config);
  }

  AppConfig _config;
  late AgentApiClient _api;
  final AudioBridge _audio;
  final WakeWordDetector _wakeWordDetector;
  VoiceSocket? _socket;
  VoiceSession? _session;
  VoiceCapabilities? _capabilities;
  StreamSubscription<void>? _socketSubscription;
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
  bool _wakeArmed = false;
  bool _wakeTriggered = false;
  bool _acceptLiveAudio = false;
  String? _wakeAgentId;
  String? _wakeVoice;
  String? _wakeThreadId;
  StreamSubscription<WakeDetection>? _wakeSubscription;
  final Queue<Uint8List> _preRoll = Queue<Uint8List>();
  final List<Uint8List> _pendingWakeAudio = <Uint8List>[];
  int _preRollBytes = 0;
  AudioProcessingState? _processingState;
  final _AudioMetricsAccumulator _metrics = _AudioMetricsAccumulator();
  int _speechFrames = 0;
  bool _speechHintPending = false;
  bool _tearingDown = false;
  bool _wakeConfirmationPending = false;
  String? _pendingWakeTranscript;

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
  bool get isWakeListening => _state == VoiceConnectionState.wakeListening;
  bool get wakeWordEnabled => _wakeArmed;
  AudioProcessingState? get audioProcessingState => _processingState;

  void updateConfig(AppConfig config) {
    if (isConnected || _wakeArmed) {
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
        _capabilities = value;
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
    if (_state != VoiceConnectionState.disconnected &&
        _state != VoiceConnectionState.wakeListening) {
      return;
    }
    await _connect(
      agentId: agentId,
      voice: voice,
      threadId: threadId,
      wakeActivation: false,
    );
  }

  Future<void> enableWakeWord({
    required String agentId,
    required String voice,
    String? threadId,
  }) async {
    if (isConnected) {
      throw StateError('请先结束当前语音会话');
    }
    _ensureConfigured();
    if (_capabilities == null) {
      await loadCapabilities();
    }
    final wake = _capabilities!.wakeWord;
    if (!wake.enabled) {
      throw StateError('后端未启用唤醒词能力');
    }
    final granted = await _audio.requestMicrophonePermission();
    if (!granted) {
      throw StateError('没有麦克风权限，无法启用唤醒词');
    }
    await _wakeWordDetector.initialize(
      WakeWordConfig(
        keyword: wake.keyword,
        score: wake.score,
        threshold: wake.threshold,
      ),
    );
    _wakeSubscription ??= _wakeWordDetector.detections.listen(
      _onWakeDetected,
      onError: _recordError,
    );
    _wakeAgentId = agentId;
    _wakeVoice = voice;
    _wakeThreadId = threadId;
    _wakeArmed = true;
    _wakeTriggered = false;
    _ensureAudioSubscriptions();
    _processingState = await _audio.start(AudioCaptureMode.standby);
    _setState(VoiceConnectionState.wakeListening);
  }

  Future<void> disableWakeWord() async {
    final hadWakeAudio = _wakeArmed || _microphoneSubscription != null;
    _wakeArmed = false;
    _wakeTriggered = false;
    _wakeWordDetector.reset();
    _preRoll.clear();
    _pendingWakeAudio.clear();
    _preRollBytes = 0;
    if (!isConnected) {
      if (hadWakeAudio) {
        await _audio.stop();
        await _cancelAudioSubscriptions();
      }
      _setState(VoiceConnectionState.disconnected);
    }
  }

  void _onWakeDetected(WakeDetection detection) {
    if (!_wakeArmed || _wakeTriggered || !isWakeListening) {
      return;
    }
    final agentId = _wakeAgentId;
    final voice = _wakeVoice;
    if (agentId == null || voice == null) {
      return;
    }
    _wakeTriggered = true;
    _pendingWakeAudio
      ..clear()
      ..addAll(_preRoll.map(Uint8List.fromList));
    unawaited(
      _connectFromWake(agentId: agentId, voice: voice, threadId: _wakeThreadId),
    );
  }

  Future<void> _connectFromWake({
    required String agentId,
    required String voice,
    required String? threadId,
  }) async {
    try {
      await _connect(
        agentId: agentId,
        voice: voice,
        threadId: threadId,
        wakeActivation: true,
      );
    } catch (_) {
      // _connect records and exposes the error before returning to standby.
    }
  }

  Future<void> _connect({
    required String agentId,
    required String voice,
    required String? threadId,
    required bool wakeActivation,
  }) async {
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
        activation: wakeActivation ? 'wake_word' : 'tap',
        wakeWord: wakeActivation ? _capabilities!.wakeWord.keyword : null,
        wakeEngine: wakeActivation ? 'sherpa-onnx-1.13.8' : null,
        preRollSamples: wakeActivation
            ? _pendingWakeAudio.fold<int>(
                0,
                (sum, item) => sum + item.length ~/ 2,
              )
            : null,
      );
      _wakeConfirmationPending = wakeActivation;
      final socket = await VoiceSocket.connect(
        _api.websocketUri(_session!.sessionId),
        headers: _api.websocketHeaders(),
      );
      _socket = socket;
      _readyCompleter = Completer<void>();
      _socketSubscription = socket.messages
          .asyncMap((message) async {
            if (message is VoiceSocketEventMessage) {
              await _handleEvent(message.event);
            } else if (message is VoiceSocketAudioMessage) {
              await _handleAudio(message.bytes);
            }
          })
          .listen(null, onError: _recordError);
      _ensureAudioSubscriptions();
      socket.sendJson(
        clientEvent('session.configure', <String, Object?>{
          'protocol_version': voiceProtocolVersion,
          'input_format': 'pcm16_16000_mono',
          'output_format': 'pcm16_24000_mono',
        }),
      );
      await _readyCompleter!.future.timeout(const Duration(seconds: 12));
      _processingState = await _audio.start(AudioCaptureMode.conversation);
      _metrics.reset();
      _acceptLiveAudio = true;
      if (wakeActivation) {
        for (final frame in _pendingWakeAudio) {
          _sendPcm(frame);
        }
        _pendingWakeAudio.clear();
      }
      _setState(VoiceConnectionState.listening);
    } catch (error) {
      _recordError(error);
      await _teardown(sendClose: false);
      rethrow;
    }
  }

  void _ensureAudioSubscriptions() {
    _microphoneSubscription ??= _audio.microphoneFrames.listen(
      _handleMicrophone,
      onError: _recordError,
    );
    _playbackSubscription ??= _audio.playbackEvents.listen(
      _handlePlaybackEvent,
      onError: _recordError,
    );
  }

  Future<void> _cancelAudioSubscriptions() async {
    await _microphoneSubscription?.cancel();
    await _playbackSubscription?.cancel();
    _microphoneSubscription = null;
    _playbackSubscription = null;
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
        if (_currentResponseId == null) {
          _setState(VoiceConnectionState.listening);
        }
      case 'transcript.partial':
        _partialTranscript = event['text'] as String? ?? '';
        notifyListeners();
      case 'transcript.final':
        final text = event['text'] as String? ?? '';
        _partialTranscript = '';
        if (_wakeConfirmationPending) {
          _pendingWakeTranscript = text.trim();
        } else if (text.trim().isNotEmpty) {
          _messages.add(ConversationEntry(role: 'human', text: text.trim()));
        }
        if (text.trim().isEmpty) {
          _setState(
            _currentResponseId == null
                ? VoiceConnectionState.listening
                : VoiceConnectionState.speaking,
          );
        } else {
          _setState(VoiceConnectionState.thinking);
        }
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
          if (_currentResponseId == responseId) {
            _currentResponseId = null;
          }
        }
        _speechHintPending = false;
        _speechFrames = 0;
        _setState(VoiceConnectionState.listening);
      case 'response.done':
        final shouldDrain =
            responseId != null &&
            !_invalidResponses.contains(responseId) &&
            shouldDrainResponseAudio(event);
        if (shouldDrain) {
          await _audio.completeResponse(responseId);
        } else {
          if (_currentResponseId == responseId) {
            _currentResponseId = null;
          }
          _setState(VoiceConnectionState.listening);
        }
      case 'playback.resume':
        if (responseId != null && !_invalidResponses.contains(responseId)) {
          _speechHintPending = false;
          _speechFrames = 0;
          await _audio.resume();
          _setState(VoiceConnectionState.speaking);
        }
      case 'wake.accepted':
        final transcript = _pendingWakeTranscript;
        final keyword = _capabilities?.wakeWord.keyword ?? '';
        final command = transcript != null && transcript.startsWith(keyword)
            ? transcript
                  .substring(keyword.length)
                  .replaceFirst(RegExp(r'^[\s，,。！？!?、]+'), '')
            : transcript;
        if (command != null &&
            command.isNotEmpty &&
            !_isNonActionableVoiceText(command)) {
          _messages.add(ConversationEntry(role: 'human', text: command));
        }
        _pendingWakeTranscript = null;
        _wakeConfirmationPending = false;
        _wakeTriggered = false;
      case 'wake.rejected':
        _pendingWakeTranscript = null;
        _wakeConfirmationPending = false;
        _error = null;
        unawaited(_teardown(sendClose: false));
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
        unawaited(_teardown(sendClose: false));
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
    if (bytes.isEmpty || bytes.length.isOdd) {
      return;
    }
    final levels = _measure(bytes);
    _metrics.add(bytes, levels);
    if (_wakeArmed && !_acceptLiveAudio) {
      if (!_wakeTriggered) {
        _wakeWordDetector.addPcm(bytes);
      }
      _appendPreRoll(bytes);
      if (_wakeTriggered) {
        _pendingWakeAudio.add(Uint8List.fromList(bytes));
      }
    }
    if (_acceptLiveAudio && isConnected) {
      _sendPcm(bytes);
      _maybeSendMetrics();
      _maybeInterrupt(levels.rmsDbfs);
    }
  }

  void _appendPreRoll(Uint8List bytes) {
    final copy = Uint8List.fromList(bytes);
    _preRoll.add(copy);
    _preRollBytes += copy.length;
    final maximum = ((_capabilities?.wakeWord.preRollMs ?? 1200) * 32).clamp(
      640,
      96000,
    );
    while (_preRollBytes > maximum && _preRoll.isNotEmpty) {
      _preRollBytes -= _preRoll.removeFirst().length;
    }
  }

  void _sendPcm(Uint8List bytes) {
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

  void _maybeInterrupt(double rmsDbfs) {
    final vad = _capabilities?.clientVad;
    if (vad == null ||
        !vad.enabled ||
        _state != VoiceConnectionState.speaking) {
      _speechFrames = 0;
      return;
    }
    _speechFrames = rmsDbfs >= vad.rmsDbfs ? _speechFrames + 1 : 0;
    if (_speechFrames >= vad.speechFrames && !_speechHintPending) {
      _speechHintPending = true;
      unawaited(speechHint());
    }
  }

  void _maybeSendMetrics() {
    final intervalSamples = (_capabilities?.audioMetricsSeconds ?? 5) * 16000;
    final report = _metrics.takeIfReady(intervalSamples);
    if (report == null || !isConnected) {
      return;
    }
    _socket!.sendJson(
      clientEvent('audio.metrics', <String, Object?>{
        ...report,
        'aec_enabled': _processingState?.aecEnabled ?? false,
        'noise_suppression_enabled':
            _processingState?.noiseSuppressionEnabled ?? false,
        'mode': _processingState?.mode.name ?? 'conversation',
      }),
    );
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
        if (_currentResponseId == responseId) {
          _currentResponseId = null;
        }
        _speechHintPending = false;
        _speechFrames = 0;
        _setState(VoiceConnectionState.listening);
    }
  }

  Future<void> _teardown({
    required bool sendClose,
    bool preserveSession = false,
  }) async {
    if (_tearingDown) return;
    _tearingDown = true;
    try {
      final socket = _socket;
      final oldSession = _session;
      _socket = null;
      _connectionId = null;
      _currentResponseId = null;
      _readyCompleter = null;
      _acceptLiveAudio = false;
      _speechHintPending = false;
      _speechFrames = 0;
      _pendingWakeTranscript = null;
      _wakeConfirmationPending = false;
      if (sendClose && socket != null) {
        socket.sendJson(clientEvent('session.close'));
      }
      await _socketSubscription?.cancel();
      _socketSubscription = null;
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
      if (_wakeArmed && !_disposed) {
        _wakeTriggered = false;
        _wakeWordDetector.reset();
        _processingState = await _audio.start(AudioCaptureMode.standby);
        _setState(VoiceConnectionState.wakeListening);
      } else {
        await _cancelAudioSubscriptions();
        _setState(VoiceConnectionState.disconnected);
      }
    } finally {
      _tearingDown = false;
    }
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
    _wakeArmed = false;
    unawaited(_teardown(sendClose: true));
    unawaited(_wakeSubscription?.cancel());
    unawaited(_wakeWordDetector.dispose());
    _api.close();
    super.dispose();
  }
}

bool _isNonActionableVoiceText(String text) {
  final normalized = text.replaceAll(RegExp(r'[\s，,。！？!?、]+'), '');
  return const <String>{
    '嗯',
    '嗯嗯',
    '呃',
    '额',
    '啊',
    '呢',
    '那',
  }.contains(normalized);
}

({double rmsDbfs, double peakDbfs, int clipped}) _measure(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var sumSquares = 0.0;
  var peak = 0;
  var clipped = 0;
  for (var offset = 0; offset < bytes.length; offset += 2) {
    final value = data.getInt16(offset, Endian.little).abs();
    sumSquares += value * value;
    peak = math.max(peak, value);
    if (value >= 32760) clipped++;
  }
  final samples = bytes.length ~/ 2;
  final rms = math.sqrt(sumSquares / samples) / 32768;
  final peakRatio = peak / 32768;
  return (
    rmsDbfs: rms > 0 ? 20 * math.log(rms) / math.ln10 : -120,
    peakDbfs: peakRatio > 0 ? 20 * math.log(peakRatio) / math.ln10 : -120,
    clipped: clipped,
  );
}

class _AudioMetricsAccumulator {
  int samples = 0;
  int frames = 0;
  int clipped = 0;
  double weightedRms = 0;
  double peakDbfs = -120;

  void add(
    Uint8List pcm,
    ({double rmsDbfs, double peakDbfs, int clipped}) levels,
  ) {
    final count = pcm.length ~/ 2;
    samples += count;
    frames++;
    clipped += levels.clipped;
    weightedRms += levels.rmsDbfs * count;
    peakDbfs = math.max(peakDbfs, levels.peakDbfs);
  }

  Map<String, Object>? takeIfReady(int threshold) {
    if (samples < threshold) return null;
    final result = <String, Object>{
      'frames': frames,
      'rms_dbfs': (weightedRms / samples).clamp(-120, 0),
      'peak_dbfs': peakDbfs.clamp(-120, 0),
      'clipped_samples': clipped,
    };
    reset();
    return result;
  }

  void reset() {
    samples = 0;
    frames = 0;
    clipped = 0;
    weightedRms = 0;
    peakDbfs = -120;
  }
}
