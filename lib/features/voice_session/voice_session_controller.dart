import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/api/execution_models.dart';
import '../../core/api/video_reference.dart';
import '../../core/api/voice_protocol.dart';
import '../../core/api/voice_socket.dart';
import '../../core/audio/audio_bridge.dart';
import '../../core/audio/wake_phrase.dart';
import '../../core/audio/wake_word_detector.dart';
import '../../core/config/app_config.dart';
import '../../core/memory/local_memory_store.dart';

enum VoiceConnectionState {
  disconnected,
  wakeListening,
  connecting,
  ready,
  listening,
  thinking,
  speaking,
}

enum DictationState { idle, recording, transcribing }

class ConversationEntry {
  const ConversationEntry({
    required this.role,
    required this.text,
    this.responseId,
    this.memoryStatus,
    this.execution,
    this.video,
    this.videoResults,
    this.isStreaming = false,
  });

  final String role;
  final String text;
  final String? responseId;
  final MemoryStatus? memoryStatus;
  final ExecutionSnapshot? execution;
  final VideoReference? video;
  final VideoResultPage? videoResults;
  final bool isStreaming;

  ConversationEntry copyWith({
    String? text,
    ExecutionSnapshot? execution,
    VideoReference? video,
    VideoResultPage? videoResults,
    bool? isStreaming,
  }) => ConversationEntry(
    role: role,
    text: text ?? this.text,
    responseId: responseId,
    memoryStatus: memoryStatus,
    execution: execution ?? this.execution,
    video: video ?? this.video,
    videoResults: videoResults ?? this.videoResults,
    isStreaming: isStreaming ?? this.isStreaming,
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
  bool _responseHasAudio = false;
  final Stopwatch _responseClock = Stopwatch();
  final Map<String, int> _responseLatencyMs = <String, int>{};
  String _partialTranscript = '';
  String? _error;
  VoiceConnectionState _state = VoiceConnectionState.disconnected;
  final Set<String> _invalidResponses = <String>{};
  final Map<String, int> _assistantIndexes = <String, int>{};
  final List<ConversationEntry> _messages = <ConversationEntry>[];
  ApprovalPrompt? _approval;
  bool _disposed = false;
  Timer? _backgroundTimer;
  bool _backgroundActive = true;
  bool _refreshing = false;
  bool _refreshAgain = false;
  int _recoveryEpoch = 0;
  String? _recoveryThread, _recoveryAgent;
  final Map<int, int> _videoPolls = {};
  final Set<String> _submittedConfirmations = {};
  String? executionRefreshError;
  int _refreshFailures = 0;
  LocalMemoryStore? _localMemory;
  String? localMemoryNotice;
  bool _usingLocalMemory = false;
  String? get localMemorySummary => !_usingLocalMemory || _localMemory == null
      ? null
      : '本机记忆 ${_localMemory!.entries.length} 条 · 待确认 ${_localMemory!.pending.length} 项 · 待整理 ${_localMemory!.queued} 项';

  void _memoryChanged() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _prepareLocalMemory() async {
    if (_capabilities?.localMemory != true || _config.userId.isEmpty) {
      _usingLocalMemory = false;
      localMemoryNotice = '当前后端未提供本机记忆协议，本次使用原有服务端记忆；升级后端后可使用本机 MD';
      return;
    }
    final store = LocalMemoryStore.forConfig(_config);
    await store.load();
    _localMemory?.removeListener(_memoryChanged);
    _localMemory = store;
    store.addListener(_memoryChanged);
    _usingLocalMemory = store.mode == 'local';
    if (_usingLocalMemory) unawaited(store.process(_api.extractLocalMemories));
  }

  bool canConfirmMemory(String? id) {
    final latest = _messages.reversed
        .map((item) => item.execution)
        .whereType<ExecutionSnapshot>()
        .firstOrNull;
    return isConnected &&
        id != null &&
        latest?.confirmation?.id == id &&
        !latest!.confirmation!.expired &&
        !_submittedConfirmations.contains(id);
  }

  void setBackgroundActive(bool active) {
    _backgroundActive = active;
    _backgroundTimer?.cancel();
    if (active) unawaited(refreshExecutionState());
  }

  void submitMemoryConfirmation(String id, bool approved) {
    if (!isConnected || !_submittedConfirmations.add(id)) return;
    final latest = _messages.reversed
        .map((item) => item.execution)
        .whereType<ExecutionSnapshot>()
        .firstOrNull;
    if (latest?.confirmation?.id != id || latest!.confirmation!.expired) {
      _submittedConfirmations.remove(id);
      return;
    }
    _socket!.sendJson(
      clientEvent('memory.confirm', {
        'confirmation_id': id,
        'approved': approved,
      }),
    );
    _setState(VoiceConnectionState.thinking);
  }

  void _mergeExecution(
    ExecutionSnapshot execution, {
    String? responseId,
    bool recovering = false,
  }) {
    final id = responseId ?? execution.responseId;
    final index = _messages.indexWhere(
      (item) =>
          item.execution?.runId == execution.runId ||
          (id != null && item.responseId == id),
    );
    final existing = index >= 0 ? _messages[index] : null;
    if (existing?.execution != null &&
        existing!.execution!.sequence > execution.sequence) {
      return;
    }
    final video = VideoReference.tryParse(execution.video);
    final results = VideoResultPage.tryParse(execution.video);
    if (index >= 0) {
      if (id != null) _assistantIndexes[id] = index;
      _messages[index] = existing!.copyWith(
        execution: execution,
        text: recovering && !existing.isStreaming && execution.text.isNotEmpty
            ? execution.text
            : null,
        video: existing.video == null ? video : null,
        videoResults: existing.videoResults == null ? results : null,
        isStreaming: existing.isStreaming,
      );
    } else {
      final target = _messages.length;
      _messages.add(
        ConversationEntry(
          role: 'ai',
          text: recovering ? execution.text : '',
          responseId: id,
          execution: execution,
          video: video,
          videoResults: results,
        ),
      );
      if (id != null) _assistantIndexes[id] = target;
    }
  }

  void _scheduleBackgroundRefresh() {
    _backgroundTimer?.cancel();
    if (_disposed || !_backgroundActive || _recoveryThread == null) return;
    final pending = _messages.any(
      (item) =>
          item.execution?.isRunning == true ||
          (item.execution?.confirmation != null &&
              !item.execution!.confirmation!.expired) ||
          (item.video != null &&
              item.video!.shouldPoll &&
              (_videoPolls[item.video!.recordId] ?? 0) < 120) ||
          item.videoResults?.items.any(
                (video) =>
                    video.shouldPoll &&
                    (_videoPolls[video.recordId] ?? 0) < 120,
              ) ==
              true,
    );
    if (pending || (executionRefreshError != null && _refreshFailures < 6)) {
      _backgroundTimer = Timer(
        const Duration(seconds: 10),
        () => unawaited(refreshExecutionState()),
      );
    }
  }

  Future<void> refreshExecutionState({bool reset = false}) async {
    if (reset) {
      _videoPolls.clear();
      _refreshFailures = 0;
    }
    final thread = _recoveryThread,
        agent = _recoveryAgent,
        epoch = _recoveryEpoch;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    if (_disposed || !_backgroundActive || thread == null || agent == null) {
      return;
    }
    _refreshing = true;
    try {
      try {
        final snapshots = await _api.executions(agent, thread);
        if (_disposed || !_backgroundActive || epoch != _recoveryEpoch) return;
        for (final snapshot in snapshots) {
          _mergeExecution(snapshot, recovering: true);
        }
        executionRefreshError = null;
        _refreshFailures = 0;
      } catch (_) {
        if (_disposed || !_backgroundActive || epoch != _recoveryEpoch) return;
        _refreshFailures++;
        executionRefreshError = '执行状态暂未同步，可稍后刷新核实';
      }
      final videos = <int, VideoReference>{};
      for (final item in _messages) {
        if (item.video case final video?) videos[video.recordId] = video;
        for (final video in item.videoResults?.items ?? <VideoReference>[]) {
          videos[video.recordId] = video;
        }
      }
      for (final video
          in videos.values.where((video) => video.shouldPoll).take(50)) {
        if ((_videoPolls[video.recordId] ?? 0) >= 120) continue;
        _videoPolls[video.recordId] = (_videoPolls[video.recordId] ?? 0) + 1;
        try {
          final data = await _api
              .requestJson('GET', '/videos/${video.recordId}')
              .timeout(const Duration(seconds: 20));
          if (_disposed || !_backgroundActive || epoch != _recoveryEpoch) {
            return;
          }
          final updated = VideoReference.tryParse({
            ...data,
            'record_id': data['id'],
          });
          if (updated == null) continue;
          for (var index = 0; index < _messages.length; index++) {
            final item = _messages[index];
            final page = item.videoResults;
            _messages[index] = item.copyWith(
              video: item.video?.recordId == updated.recordId ? updated : null,
              videoResults: page == null
                  ? null
                  : VideoResultPage(
                      items: page.items
                          .map(
                            (item) => item.recordId == updated.recordId
                                ? updated
                                : item,
                          )
                          .toList(),
                      total: page.total,
                      page: page.page,
                      totalPages: page.totalPages,
                    ),
            );
          }
        } catch (_) {
          if (_disposed || !_backgroundActive || epoch != _recoveryEpoch) {
            return;
          }
        }
      }
      if (!_disposed) notifyListeners();
    } finally {
      _refreshing = false;
      if (_refreshAgain && !_disposed && _backgroundActive) {
        _refreshAgain = false;
        unawaited(refreshExecutionState());
      } else {
        _scheduleBackgroundRefresh();
      }
    }
  }

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
  int _wakePreRollSamples = 0;
  AudioProcessingState? _processingState;
  final _AudioMetricsAccumulator _metrics = _AudioMetricsAccumulator();
  int _speechFrames = 0;
  bool _speechHintPending = false;
  Timer? _speechHintResumeTimer;
  String? _pausedHintResponseId;
  bool _tearingDown = false;
  int _wakeSetupEpoch = 0;
  bool _wakeConfirmationPending = false;
  String? _pendingWakeTranscript;
  String _inputMode = 'conversation';
  DictationState _dictationState = DictationState.idle;
  String _dictationText = '';
  Completer<String>? _dictationCompleter;

  String get inputMode => _inputMode;
  DictationState get dictationState => _dictationState;
  bool get isDictating => _dictationState != DictationState.idle;
  VoiceConnectionState get idleState => _inputMode == 'text'
      ? VoiceConnectionState.ready
      : VoiceConnectionState.listening;

  AppConfig get config => _config;
  VoiceConnectionState get state => _state;
  VoiceCapabilities? get capabilities => _capabilities;
  VoiceSession? get session => _session;
  String get partialTranscript => _partialTranscript;
  String? get error => _error;
  String? get currentResponseId => _currentResponseId;
  Map<String, int> get responseLatencyMs =>
      Map.unmodifiable(_responseLatencyMs);
  List<ConversationEntry> get messages => List.unmodifiable(_messages);
  ApprovalPrompt? get approval => _approval;
  bool get isConnected => _connectionId != null && _socket != null;
  bool get isWakeListening => _state == VoiceConnectionState.wakeListening;
  bool get wakeWordEnabled => _wakeArmed;
  bool get isWakeActivating => _wakeArmed && _wakeTriggered;
  AudioProcessingState? get audioProcessingState => _processingState;

  void updateConfig(AppConfig config) {
    if (isConnected || _wakeArmed) {
      throw StateError('请先断开当前语音会话');
    }
    _recoveryEpoch++;
    _backgroundTimer?.cancel();
    if (config.userId != _config.userId || config.baseUrl != _config.baseUrl) {
      clearConversation();
    }
    _api.close();
    _config = config;
    _api = AgentApiClient(config);
    _capabilities = null;
    _localMemory?.removeListener(_memoryChanged);
    _localMemory = null;
    _usingLocalMemory = false;
    localMemoryNotice = null;
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
      if (!value.hasCompatibleAudioFormats) {
        throw const ApiException(0, '后端音频格式与当前 App 不兼容，请升级 App');
      }
      if (!value.hasMatchingVoiceCatalog || value.voiceOptions.isEmpty) {
        throw const ApiException(503, '当前语音模型的音色配置不可用，请检查后端配置');
      }
      if (_wakeArmed && !_wakeTriggered && !isConnected) {
        await _wakeWordDetector.initialize(
          WakeWordConfig(
            keyword: value.wakeWord.keyword,
            score: value.wakeWord.score,
            threshold: value.wakeWord.threshold,
          ),
        );
      }
      _error = null;
    } catch (error) {
      _recordError(error);
      rethrow;
    } finally {
      if (!isConnected) {
        if (_wakeArmed && !_wakeTriggered) _wakeWordDetector.reset();
        _setState(
          _wakeArmed && !_wakeTriggered
              ? VoiceConnectionState.wakeListening
              : VoiceConnectionState.disconnected,
        );
      }
    }
  }

  Future<void> connect({
    required String agentId,
    required String voice,
    String? threadId,
    String inputMode = 'conversation',
  }) async {
    if (_state == VoiceConnectionState.connecting || _tearingDown) return;
    if (isConnected && _inputMode == inputMode) return;
    final selectedThread = threadId ?? _session?.threadId ?? _recoveryThread;
    if (inputMode != 'conversation' || isConnected) {
      await disableWakeWord();
      if (isConnected) await disconnect();
    }
    await _connect(
      agentId: agentId,
      voice: voice,
      threadId: selectedThread,
      wakeActivation: false,
      inputMode: inputMode,
    );
  }

  Future<void> startDictation({
    required String agentId,
    required String voice,
    String? threadId,
  }) async {
    if (isDictating) return;
    _dictationText = '';
    await connect(
      agentId: agentId,
      voice: voice,
      threadId: threadId,
      inputMode: 'transcription',
    );
    if (isConnected && _inputMode == 'transcription') {
      _dictationState = DictationState.recording;
      notifyListeners();
    }
  }

  Future<String> finishDictation() async {
    if (_dictationState != DictationState.recording || !isConnected) return '';
    _dictationState = DictationState.transcribing;
    _dictationCompleter = Completer<String>();
    _acceptLiveAudio = false;
    notifyListeners();
    try {
      await _audio.stop();
      _socket!.sendJson(clientEvent('input.commit'));
      return await _dictationCompleter!.future.timeout(
        const Duration(seconds: 20),
      );
    } catch (error) {
      _recordError(error is TimeoutException ? '转写超时，请重试或直接输入文字' : error);
      rethrow;
    } finally {
      await disconnect();
    }
  }

  Future<void> enableWakeWord({
    required String agentId,
    required String voice,
    String? threadId,
  }) async {
    if (isConnected) {
      throw StateError('请先结束当前语音会话');
    }
    final setupEpoch = ++_wakeSetupEpoch;
    _ensureConfigured();
    if (_capabilities == null) {
      await loadCapabilities();
    }
    if (setupEpoch != _wakeSetupEpoch || _disposed) return;
    final wake = _capabilities!.wakeWord;
    if (!wake.enabled) {
      throw StateError('后端未启用唤醒词能力');
    }
    final granted = await _audio.requestMicrophonePermission();
    if (setupEpoch != _wakeSetupEpoch || _disposed) return;
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
    if (setupEpoch != _wakeSetupEpoch || _disposed) return;
    _wakeSubscription ??= _wakeWordDetector.detections.listen(
      _onWakeDetected,
      onError: _recordError,
    );
    _wakeWordDetector.reset();
    _wakeAgentId = agentId;
    _wakeVoice = voice;
    _wakeThreadId = threadId;
    _wakeArmed = true;
    _wakeTriggered = false;
    _ensureAudioSubscriptions();
    _processingState = await _audio.start(AudioCaptureMode.standby);
    if (setupEpoch != _wakeSetupEpoch || _disposed) return;
    _setState(VoiceConnectionState.wakeListening);
  }

  Future<void> disableWakeWord() async {
    _wakeSetupEpoch++;
    final hadWakeAudio = _wakeArmed || _microphoneSubscription != null;
    _wakeArmed = false;
    _wakeTriggered = false;
    _wakeWordDetector.reset();
    _preRoll.clear();
    _pendingWakeAudio.clear();
    _preRollBytes = 0;
    _wakePreRollSamples = 0;
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
    _wakePreRollSamples = _preRollBytes ~/ 2;
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
    String inputMode = 'conversation',
  }) async {
    _ensureConfigured();
    _setState(VoiceConnectionState.connecting);
    _error = null;
    try {
      await loadCapabilities();
      _setState(VoiceConnectionState.connecting);
      final selectedVoice = _capabilities!.selectVoice(voice);
      if (selectedVoice == null) {
        throw const ApiException(503, '当前语音模型没有可用音色');
      }
      if (inputMode != 'conversation' &&
          !_capabilities!.inputModes.contains(inputMode)) {
        throw const ApiException(503, '当前后端不支持文字或听写模式，请更新服务');
      }
      if (inputMode != 'text') {
        final granted = await _audio.requestMicrophonePermission();
        if (!granted) throw StateError('没有麦克风权限，请允许录音或直接输入文字');
      }
      _inputMode = inputMode;
      await _prepareLocalMemory();
      _session = await _api.createVoiceSession(
        agentId: agentId,
        voice: selectedVoice,
        threadId: threadId,
        activation: wakeActivation ? 'wake_word' : 'tap',
        wakeWord: wakeActivation ? _capabilities!.wakeWord.keyword : null,
        wakeEngine: wakeActivation ? 'sherpa-onnx-1.13.8' : null,
        preRollSamples: wakeActivation ? _wakePreRollSamples : null,
        inputMode: inputMode,
        memoryMode: _capabilities!.localMemory
            ? (_usingLocalMemory ? 'local' : 'mem0')
            : null,
      );
      if (_recoveryThread != _session!.threadId) {
        _recoveryEpoch++;
        _videoPolls.clear();
      }
      _recoveryThread = _session!.threadId;
      _recoveryAgent = _session!.agentId;
      _submittedConfirmations.clear();
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
      if (threadId != null) unawaited(refreshExecutionState());
      _processingState = await _audio.start(
        inputMode == 'text'
            ? AudioCaptureMode.playback
            : AudioCaptureMode.conversation,
      );
      _metrics.reset();
      _acceptLiveAudio = inputMode != 'text';
      if (wakeActivation) {
        for (final frame in _pendingWakeAudio) {
          _sendPcm(frame);
        }
        _pendingWakeAudio.clear();
      }
      _setState(idleState);
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
    await connect(
      agentId: agentId,
      voice: voice,
      threadId: threadId,
      inputMode: previous.inputMode,
    );
  }

  void sendText(String text) {
    final normalized = text.trim();
    if (!isConnected || normalized.isEmpty || _inputMode == 'transcription') {
      return;
    }
    if (normalized.runes.length > 6000) {
      throw ArgumentError('消息最多 6000 个字符，请缩短后发送');
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
    _finishMessage(responseId);
    _clearSpeechHintPause();
    await _audio.cancel(responseId);
    _socket!.sendJson(
      clientEvent('response.cancel', <String, Object?>{
        'response_id': responseId,
      }),
    );
    _setState(idleState);
  }

  Future<void> speechHint({bool pausePlayback = true}) async {
    final responseId = _currentResponseId;
    if (!isConnected || responseId == null) {
      return;
    }
    if (pausePlayback) {
      await _audio.pause();
      _clearSpeechHintPause();
      _pausedHintResponseId = responseId;
      _speechHintResumeTimer = Timer(const Duration(seconds: 1), () {
        unawaited(
          _resumeSpeechHintPlayback(responseId).catchError(_recordError),
        );
      });
    }
    _socket?.sendJson(clientEvent('input.speech_hint'));
  }

  void _clearSpeechHintPause() {
    _speechHintResumeTimer?.cancel();
    _speechHintResumeTimer = null;
    _pausedHintResponseId = null;
  }

  Future<void> _resumeSpeechHintPlayback(String responseId) async {
    if (_pausedHintResponseId != responseId) return;
    _clearSpeechHintPause();
    if (isConnected &&
        responseId == _currentResponseId &&
        !_invalidResponses.contains(responseId)) {
      await _audio.resume();
    }
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

  void clearConversation() {
    if (isConnected) {
      throw StateError('请先结束当前语音会话');
    }
    _recoveryEpoch++;
    _backgroundTimer?.cancel();
    _recoveryThread = null;
    _recoveryAgent = null;
    _videoPolls.clear();
    _submittedConfirmations.clear();
    executionRefreshError = null;
    _refreshFailures = 0;
    _refreshAgain = false;
    _messages.clear();
    _assistantIndexes.clear();
    _invalidResponses.clear();
    _partialTranscript = '';
    _approval = null;
    _session = null;
    _error = null;
    notifyListeners();
  }

  Future<void> loadHistory(String agentId, String threadId) async {
    final epoch = ++_recoveryEpoch;
    final history = await _api.history(agentId, threadId);
    if (_disposed || !_backgroundActive || epoch != _recoveryEpoch) return;
    _assistantIndexes.clear();
    _submittedConfirmations.clear();
    _recoveryThread = threadId;
    _recoveryAgent = agentId;
    _messages
      ..clear()
      ..addAll(
        history.map(
          (item) => ConversationEntry(
            role: item.role,
            text: item.content,
            memoryStatus: item.memoryStatus,
            responseId: item.execution?.responseId,
            execution: item.execution,
            video: item.video,
            videoResults: item.videoResults,
          ),
        ),
      );
    notifyListeners();
    await refreshExecutionState();
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
          'agent.custom',
        }.contains(type)) {
      return;
    }
    switch (type) {
      case 'memory.context.request':
        final socket = _socket;
        if (!_usingLocalMemory || socket == null || responseId == null) break;
        try {
          final context = await _localMemory!.context(
            event['text'] as String? ?? '',
          );
          if (socket != _socket) break;
          socket.sendJson(
            clientEvent('memory.context', {
              'response_id': responseId,
              'context': context,
            }),
          );
        } catch (_) {
          localMemoryNotice = '本机记忆暂不可读取，本轮不会使用 Mem0 替代';
          if (socket == _socket) {
            socket.sendJson(
              clientEvent('memory.context', {
                'response_id': responseId,
                'context': <String, Object?>{},
              }),
            );
          }
          notifyListeners();
        }
      case 'memory.context.unavailable':
        localMemoryNotice = '本轮未及时取得本机记忆，回答可能缺少个人上下文';
        notifyListeners();
      case 'input.accepted':
        final store = _localMemory;
        if (!_usingLocalMemory ||
            store == null ||
            event['duplicate'] == true ||
            event['memory_eligible'] != true) {
          break;
        }
        try {
          await store.enqueue(
            sourceId: event['turn_id'] as String,
            text: event['text'] as String,
            threadId: _session?.threadId,
          );
          unawaited(store.process(_api.extractLocalMemories));
        } catch (_) {
          localMemoryNotice = '本次记忆任务未保存，请到本机记忆页核对';
          notifyListeners();
        }
      case 'session.ready':
        _connectionId = event['connection_id'] as String;
        _inputSequence = 0;
        _readyCompleter?.complete();
        _setState(VoiceConnectionState.ready);
      case 'input.started':
        if (_currentResponseId == null) {
          _setState(idleState);
        }
      case 'transcript.partial':
        if (_inputMode == 'transcription') {
          _partialTranscript =
              _dictationText + (event['text'] as String? ?? '');
          notifyListeners();
          break;
        }
        final text = event['text'] as String? ?? '';
        _partialTranscript = _isNonActionableVoiceText(text) ? '' : text;
        notifyListeners();
      case 'transcript.final':
        if (_inputMode == 'transcription') {
          _dictationText += event['text'] as String? ?? '';
          _partialTranscript = _dictationText;
          final completion = _dictationCompleter;
          if (completion != null && !completion.isCompleted) {
            completion.complete(_dictationText.trim());
          }
          notifyListeners();
          break;
        }
        final rawText = event['text'] as String? ?? '';
        final text = _isNonActionableVoiceText(rawText) ? '' : rawText;
        _partialTranscript = '';
        if (_wakeConfirmationPending) {
          if (text.trim().isNotEmpty) {
            _pendingWakeTranscript = text.trim();
          }
        } else if (text.trim().isNotEmpty) {
          _messages.add(ConversationEntry(role: 'human', text: text.trim()));
        }
        if (text.trim().isEmpty) {
          _setState(
            _currentResponseId == null
                ? idleState
                : _responseHasAudio
                ? VoiceConnectionState.speaking
                : VoiceConnectionState.thinking,
          );
        } else {
          _setState(VoiceConnectionState.thinking);
        }
      case 'response.started':
        _currentResponseId = responseId;
        _responseHasAudio = false;
        _responseLatencyMs.clear();
        _responseClock
          ..reset()
          ..start();
        if (responseId != null && _assistantIndexes.containsKey(responseId)) {
          final index = _assistantIndexes[responseId]!;
          _messages[index] = _messages[index].copyWith(isStreaming: true);
        } else if (responseId != null) {
          _assistantIndexes[responseId] = _messages.length;
          _messages.add(
            ConversationEntry(
              role: 'ai',
              text: '',
              responseId: responseId,
              isStreaming: true,
            ),
          );
        }
        _setState(VoiceConnectionState.thinking);
      case 'text.delta':
        _responseLatencyMs.putIfAbsent(
          'first_text_ms',
          () => _responseClock.elapsedMilliseconds,
        );
        if (responseId != null) {
          final index = _assistantIndexes[responseId];
          if (index != null && index < _messages.length) {
            _messages[index] = _messages[index].copyWith(
              text: '${_messages[index].text}${event['text'] as String? ?? ''}',
            );
          }
        }
        _setState(
          _responseHasAudio
              ? VoiceConnectionState.speaking
              : VoiceConnectionState.thinking,
        );
      case 'agent.custom':
        final data = event['data'];
        if (responseId == null || data is! Map) {
          break;
        }
        final execution = ExecutionSnapshot.tryParse(data);
        if (execution != null) {
          _mergeExecution(execution, responseId: responseId);
          notifyListeners();
          _scheduleBackgroundRefresh();
          break;
        }
        final video = data['type'] == 'video.task'
            ? VideoReference.tryParse(data['video'])
            : null;
        final videoResults = VideoResultPage.tryParse(data);
        if (video == null && videoResults == null) break;
        final index = _assistantIndexes[responseId];
        if (index != null && index < _messages.length) {
          _messages[index] = _messages[index].copyWith(
            video: video,
            videoResults: videoResults,
          );
        } else {
          _assistantIndexes[responseId] = _messages.length;
          _messages.add(
            ConversationEntry(
              role: 'ai',
              text: '',
              responseId: responseId,
              video: video,
              videoResults: videoResults,
            ),
          );
        }
        notifyListeners();
        _scheduleBackgroundRefresh();
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
          _finishMessage(responseId);
          if (_pausedHintResponseId == responseId) _clearSpeechHintPause();
          _invalidResponses.add(responseId);
          await _audio.cancel(responseId);
          if (_currentResponseId == responseId) {
            _currentResponseId = null;
          }
        }
        _speechHintPending = false;
        _speechFrames = 0;
        _setState(idleState);
      case 'response.done':
        _scheduleBackgroundRefresh();
        if (responseId != null) _finishMessage(responseId);
        final serverLatency = event['latency_ms'];
        if (serverLatency is Map) {
          for (final entry in serverLatency.entries) {
            if (entry.key is String && entry.value is num) {
              _responseLatencyMs['server_${entry.key}'] = (entry.value as num)
                  .toInt();
            }
          }
        }
        if (responseId == _currentResponseId && !_responseHasAudio) {
          _currentResponseId = null;
          _setState(idleState);
        }
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
          _setState(idleState);
        }
      case 'playback.resume':
        if (responseId != null && !_invalidResponses.contains(responseId)) {
          _speechHintPending = false;
          _speechFrames = 0;
          await _resumeSpeechHintPlayback(responseId);
          _setState(
            _responseHasAudio
                ? VoiceConnectionState.speaking
                : VoiceConnectionState.thinking,
          );
        }
      case 'wake.accepted':
        if (!_wakeConfirmationPending) break;
        final transcript = _pendingWakeTranscript;
        final keyword = _capabilities?.wakeWord.keyword ?? '';
        final command =
            event['command'] as String? ??
            (transcript == null ? null : stripWakePrefix(transcript, keyword));
        if (command != null &&
            command.isNotEmpty &&
            !_isNonActionableVoiceText(command)) {
          _messages.add(ConversationEntry(role: 'human', text: command));
        }
        _pendingWakeTranscript = null;
        _wakeConfirmationPending = false;
        _wakeTriggered = false;
        _partialTranscript = '';
        _setState(idleState);
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
        final dictation = _dictationCompleter;
        if (dictation != null && !dictation.isCompleted) {
          dictation.completeError(StateError('语音转写失败，请重试或直接输入文字'));
        }
        _recordError(switch (event['code']) {
          'tts_failed' => '本轮语音合成未完成，文字已保留，请重试',
          'agent_failed' => '本次回答未能完成，已保留你的输入，请检查服务后重试',
          'asr_failed' => '语音转写失败，请重试或直接输入文字',
          _ => event['code']?.toString() ?? '未知语音错误',
        });
      case 'session.closed':
      case 'socket.closed':
        unawaited(_teardown(sendClose: false, preserveSession: true));
    }
  }

  Future<void> _handleAudio(Uint8List bytes) async {
    try {
      final frame = decodeOutputAudioFrame(bytes);
      if (frame.connectionId != _connectionId ||
          _invalidResponses.contains(frame.responseId)) {
        return;
      }
      final receivedMs = _responseClock.elapsedMilliseconds;
      await _audio.enqueue(
        frame.pcm,
        responseId: frame.responseId,
        segmentIndex: frame.segmentIndex,
      );
      if (!_responseHasAudio && frame.responseId == _currentResponseId) {
        _responseHasAudio = true;
        _responseLatencyMs['first_audio_received_ms'] = receivedMs;
        _responseLatencyMs['native_enqueue_ms'] =
            _responseClock.elapsedMilliseconds - receivedMs;
        final firstTextMs = _responseLatencyMs['first_text_ms'];
        if (firstTextMs != null) {
          _responseLatencyMs['text_to_audio_ms'] = receivedMs - firstTextMs;
        }
        if (kDebugMode) {
          debugPrint(
            'Voice latency response_id=${frame.responseId} latency_ms=$_responseLatencyMs',
          );
        }
      }
      _setState(VoiceConnectionState.speaking);
    } catch (error) {
      _recordError(error);
    }
  }

  void _finishMessage(String responseId) {
    final index = _assistantIndexes[responseId];
    if (index != null &&
        index < _messages.length &&
        _messages[index].isStreaming) {
      _messages[index] = _messages[index].copyWith(isStreaming: false);
      if (!_disposed) notifyListeners();
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
    final maximum = ((_capabilities?.wakeWord.preRollMs ?? 4000) * 32).clamp(
      640,
      192000,
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
      unawaited(speechHint(pausePlayback: false));
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
      case 'playback.error':
        _recordError('手机音频播放失败，请重新连接语音会话');
        if (_currentResponseId == responseId) {
          unawaited(cancelCurrent());
        }
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
          _clearSpeechHintPause();
          _speechHintPending = false;
          _speechFrames = 0;
          _setState(idleState);
        }
    }
  }

  Future<void> _teardown({
    required bool sendClose,
    bool preserveSession = false,
  }) async {
    if (_tearingDown) return;
    _tearingDown = true;
    final dictation = _dictationCompleter;
    _dictationCompleter = null;
    if (dictation != null && !dictation.isCompleted) {
      dictation.completeError(StateError('语音转写已中断，请重试'));
    }
    _dictationState = DictationState.idle;
    _clearSpeechHintPause();
    try {
      for (final responseId in _assistantIndexes.keys) {
        _finishMessage(responseId);
      }
      final socket = _socket;
      final oldSession = _session;
      _socket = null;
      _connectionId = null;
      _currentResponseId = null;
      _responseHasAudio = false;
      _responseClock.stop();
      _readyCompleter = null;
      _acceptLiveAudio = false;
      _speechHintPending = false;
      _speechFrames = 0;
      _pendingWakeTranscript = null;
      _wakeConfirmationPending = false;
      _pendingWakeAudio.clear();
      _preRoll.clear();
      _preRollBytes = 0;
      _wakePreRollSamples = 0;
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
    _localMemory?.removeListener(_memoryChanged);
    _backgroundTimer?.cancel();
    _recoveryEpoch++;
    _wakeArmed = false;
    unawaited(_teardown(sendClose: true));
    unawaited(_wakeSubscription?.cancel());
    unawaited(_wakeWordDetector.dispose());
    _api.close();
    super.dispose();
  }
}

bool _isNonActionableVoiceText(String text) {
  final normalized = text.replaceAll(RegExp(r'[\p{P}\s]+', unicode: true), '');
  return normalized.isEmpty ||
      const <String>{'嗯', '嗯嗯', '呃', '额', '啊', '呢', '那'}.contains(normalized);
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
