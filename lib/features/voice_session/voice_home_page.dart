import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/api/api_models.dart';
import '../../core/api/video_reference.dart';
import '../../core/config/app_config.dart';
import '../../core/audio/audio_bridge.dart';
import '../conversations/personal_library_page.dart';
import '../conversations/chat_record_widgets.dart';
import '../profile/profile_avatar.dart';
import '../videos/video_studio_page.dart';
import '../videos/video_message_card.dart';
import 'voice_session_controller.dart';

class VoiceHomePage extends StatefulWidget {
  const VoiceHomePage({
    super.key,
    required this.controller,
    required this.user,
    required this.onOpenProfile,
    required this.onOpenSettings,
  });

  final VoiceSessionController controller;
  final AuthUser user;
  final Future<void> Function(BuildContext context) onOpenProfile;
  final Future<void> Function(BuildContext context) onOpenSettings;

  @override
  State<VoiceHomePage> createState() => _VoiceHomePageState();
}

class _VoiceHomePageState extends State<VoiceHomePage>
    with WidgetsBindingObserver {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String? _agentId;
  String? _voice;
  String? _threadId;
  bool _enablingDefaultWake = false;
  bool _defaultWakeAttempted = false;
  bool _browsingHistory = false;
  bool _followingLatest = true;
  bool _showBackToTop = false;
  bool _awayFromLatest = false;
  bool _hasNewContent = false;
  bool _followScheduled = false;
  bool _scrollingToStart = false;
  int _newMessageCount = 0;
  late int _lastMessageCount;
  ConversationEntry? _lastEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastMessageCount = widget.controller.messages.length;
    _lastEntry = widget.controller.messages.lastOrNull;
    _scroll.addListener(_scrollChanged);
    widget.controller.addListener(_changed);
    _scheduleFollowLatest();
    _scheduleDefaultWake();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    _text.dispose();
    _scroll.removeListener(_scrollChanged);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _defaultWakeAttempted = false;
      _scheduleDefaultWake();
      return;
    }
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) &&
        widget.controller.wakeWordEnabled &&
        !widget.controller.isConnected) {
      _defaultWakeAttempted = false;
      unawaited(widget.controller.disableWakeWord());
    }
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    final session = widget.controller.session;
    if (session != null &&
        (_threadId == null || _threadId == session.threadId)) {
      _agentId = session.agentId;
      _threadId = session.threadId;
    }
    final messages = widget.controller.messages;
    final changed =
        messages.length != _lastMessageCount ||
        messages.lastOrNull != _lastEntry;
    if (messages.isEmpty) {
      _followingLatest = true;
      _newMessageCount = 0;
      _hasNewContent = false;
    } else if (changed && !_followingLatest) {
      _newMessageCount += (messages.length - _lastMessageCount).clamp(
        0,
        messages.length,
      );
      _hasNewContent = true;
    }
    _lastMessageCount = messages.length;
    _lastEntry = messages.lastOrNull;
    setState(() {});
    _scheduleDefaultWake();
    if (changed) _scheduleFollowLatest();
  }

  void _scrollChanged() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final showTop = position.pixels > 240;
    final away = position.extentAfter > 80;
    final cleared =
        position.extentAfter <= 24 &&
        !_scrollingToStart &&
        (_hasNewContent || _newMessageCount > 0);
    if (position.extentAfter <= 24 && !_scrollingToStart) {
      _followingLatest = true;
      _newMessageCount = 0;
      _hasNewContent = false;
    }
    if (showTop != _showBackToTop || away != _awayFromLatest || cleared) {
      setState(() {
        _showBackToTop = showTop;
        _awayFromLatest = away;
      });
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.forward) {
      _followingLatest = false;
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _followingLatest = notification.metrics.extentAfter <= 24;
    }
    return false;
  }

  void _scheduleFollowLatest() {
    if (_followScheduled) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      if (_followingLatest &&
          widget.controller.messages.isNotEmpty &&
          _scroll.position.extentAfter > 0.5) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
      _scrollChanged();
    });
  }

  Future<void> _jumpToStart() async {
    if (!_scroll.hasClients) return;
    _followingLatest = false;
    _scrollingToStart = true;
    await _scrollTo(0);
    _scrollingToStart = false;
  }

  Future<void> _jumpToLatest() async {
    if (!_scroll.hasClients) return;
    _followingLatest = true;
    setState(() {
      _newMessageCount = 0;
      _hasNewContent = false;
    });
    await _scrollTo(_scroll.position.maxScrollExtent);
    _scheduleFollowLatest();
  }

  Future<void> _scrollTo(double offset) async {
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(offset);
    } else {
      await _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _showPreferences() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refresh) => ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '让对话更合心意',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭对话偏好',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                _ConversationPreferences(
                  capabilities: widget.controller.capabilities,
                  selectedAgent: _selectedAgent,
                  selectedVoice: _selectedVoice,
                  connected: widget.controller.isConnected,
                  processingState: widget.controller.audioProcessingState,
                  threadId: _threadId,
                  onAgentChanged: (value) async {
                    await _changeAgent(value);
                    if (sheetContext.mounted) refresh(() {});
                  },
                  onVoiceChanged: (value) async {
                    await _changeVoice(value);
                    if (sheetContext.mounted) refresh(() {});
                  },
                  onConfigure: () {
                    Navigator.pop(sheetContext);
                    _openSettings();
                  },
                  onReload: _reloadCapabilities,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AgentCapability? get _selectedAgent {
    return widget.controller.capabilities?.selectAgent(
      _agentId,
      hasExistingThread: _threadId != null,
    );
  }

  String? get _selectedVoice {
    final capabilities = widget.controller.capabilities;
    final voices = capabilities?.voices ?? const <String>[];
    if (voices.isEmpty) {
      return null;
    }
    return voices.contains(_voice)
        ? _voice
        : capabilities?.defaultVoice ?? voices.first;
  }

  Future<void> _connect() async {
    final agent = _selectedAgent;
    final voice = _selectedVoice;
    if (agent == null || voice == null) {
      await _reloadCapabilities();
      return;
    }
    try {
      await widget.controller.connect(
        agentId: agent.id,
        voice: voice,
        threadId: _threadId,
      );
      _threadId = widget.controller.session?.threadId;
    } catch (_) {
      // Error is displayed by the controller banner.
    }
  }

  Future<void> _reloadCapabilities() async {
    _defaultWakeAttempted = false;
    try {
      await widget.controller.loadCapabilities();
      _scheduleDefaultWake();
    } catch (_) {
      // Error is displayed by the controller banner.
    }
  }

  void _scheduleDefaultWake() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_enableDefaultWakeIfReady());
      }
    });
  }

  Future<void> _enableDefaultWakeIfReady() async {
    final controller = widget.controller;
    final agent = _selectedAgent;
    final voice = _selectedVoice;
    final capabilities = controller.capabilities;
    if (_browsingHistory ||
        _enablingDefaultWake ||
        _defaultWakeAttempted ||
        controller.isConnected ||
        controller.wakeWordEnabled ||
        !controller.config.isComplete ||
        capabilities?.enabled != true ||
        capabilities?.wakeWord.enabled != true ||
        agent == null ||
        voice == null) {
      return;
    }
    _defaultWakeAttempted = true;
    _enablingDefaultWake = true;
    try {
      await controller.enableWakeWord(
        agentId: agent.id,
        voice: voice,
        threadId: _threadId,
      );
    } catch (_) {
      // Error is displayed by the controller banner.
    } finally {
      _enablingDefaultWake = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _changeAgent(String? value) async {
    if (value == null || value == _selectedAgent?.id) {
      return;
    }
    await widget.controller.disableWakeWord();
    if (!mounted) return;
    setState(() {
      _agentId = value;
      _threadId = null;
      _defaultWakeAttempted = false;
    });
    widget.controller.clearConversation();
    _scheduleDefaultWake();
  }

  Future<void> _changeVoice(String? value) async {
    if (value == null || value == _selectedVoice) {
      return;
    }
    await widget.controller.disableWakeWord();
    if (!mounted) return;
    setState(() {
      _voice = value;
      _defaultWakeAttempted = false;
    });
    _scheduleDefaultWake();
  }

  Future<void> _openProfile() async {
    if (_browsingHistory) return;
    _browsingHistory = true;
    try {
      await widget.onOpenProfile(context);
    } finally {
      _browsingHistory = false;
      if (mounted) {
        _defaultWakeAttempted = false;
        _scheduleDefaultWake();
      }
    }
  }

  Future<void> _openSettings() async {
    await widget.onOpenSettings(context);
    if (!mounted) return;
    _defaultWakeAttempted = false;
    _scheduleDefaultWake();
  }

  Future<void> _openConversationVideo(VideoReference video, bool play) async {
    final controller = widget.controller;
    if (_browsingHistory) return;
    if (controller.state == VoiceConnectionState.connecting ||
        controller.isWakeActivating) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('语音正在连接，请稍后查看影片')));
      return;
    }
    final previous = controller.isConnected ? controller.session : null;
    final config = controller.config;
    var mediaReleased = false;
    _browsingHistory = true;
    try {
      await controller.disableWakeWord();
      await controller.disconnect();
      if (!mounted) return;
      await openConversationVideo(context, config, video, play: play);
      mediaReleased = true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('暂时无法打开影片：$error')));
      }
    } finally {
      if (mounted) {
        final foreground =
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
        if (mediaReleased &&
            previous != null &&
            foreground &&
            controller.config == config) {
          try {
            await controller.connect(
              agentId: previous.agentId,
              voice: previous.voice,
              threadId: previous.threadId,
            );
          } catch (_) {
            // The controller displays connection errors and retains the conversation.
          }
        }
        _browsingHistory = false;
        _defaultWakeAttempted = false;
        if (mediaReleased && foreground) _scheduleDefaultWake();
      }
    }
  }

  Future<void> _openVideos() async {
    if (_browsingHistory || widget.controller.isConnected) return;
    _browsingHistory = true;
    try {
      await widget.controller.disableWakeWord();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => VideoStudioPage(config: widget.controller.config),
        ),
      );
    } finally {
      _browsingHistory = false;
      if (mounted) {
        _defaultWakeAttempted = false;
        _scheduleDefaultWake();
      }
    }
  }

  Future<void> _openHistory() async {
    if (_browsingHistory || widget.controller.isConnected) {
      return;
    }
    _browsingHistory = true;
    try {
      await widget.controller.disableWakeWord();
      if (!mounted) return;
      final thread = await Navigator.of(context).push<ThreadSummary>(
        MaterialPageRoute(
          builder: (_) => PersonalLibraryPage(
            config: widget.controller.config,
            agents: widget.controller.capabilities?.agents ?? const [],
            initialAgentId:
                _selectedAgent?.id ??
                _agentId ??
                widget.controller.capabilities?.defaultAgentId ??
                'chatbot',
          ),
        ),
      );
      if (mounted && thread != null) await _selectThread(thread);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      _browsingHistory = false;
      if (mounted) {
        _defaultWakeAttempted = false;
        _scheduleDefaultWake();
      }
    }
  }

  Future<void> _selectThread(ThreadSummary thread) async {
    await widget.controller.disableWakeWord();
    if (!mounted) return;
    setState(() {
      _agentId = thread.agentId;
      _threadId = thread.threadId;
      _defaultWakeAttempted = false;
    });
    _followingLatest = true;
    try {
      await widget.controller.loadHistory(thread.agentId, thread.threadId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      _scheduleDefaultWake();
    }
  }

  void _retryDefaultWake() {
    widget.controller.clearError();
    _defaultWakeAttempted = false;
    _scheduleDefaultWake();
  }

  void _sendText() {
    if (!widget.controller.isConnected || _text.text.trim().isEmpty) {
      return;
    }
    _followingLatest = true;
    final value = _text.text;
    _text.clear();
    widget.controller.sendText(value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final capabilities = controller.capabilities;
    final connected = controller.isConnected;
    final messages = controller.messages;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final status = controller.isWakeActivating
        ? (connected ? '听到了，正在确认' : '听到了，正在连接')
        : _statusLabel(controller.state, capabilities);
    final color = _statusColor(controller.state);
    return Scaffold(
      backgroundColor: dark ? const Color(0xff171412) : const Color(0xfffbf8f4),
      appBar: AppBar(
        toolbarHeight:
            72 + (MediaQuery.textScalerOf(context).scale(16) - 16).clamp(0, 24),
        titleSpacing: 16,
        title: Semantics(
          button: true,
          label:
              '对话偏好，${recordAgentName(_selectedAgent?.id ?? 'chatbot')}，$status',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _showPreferences,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recordAgentName(_selectedAgent?.id ?? 'chatbot'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '视频工作室',
            onPressed: connected ? null : _openVideos,
            icon: const Icon(Icons.movie_creation_outlined),
          ),
          IconButton(
            tooltip: '对话偏好',
            onPressed: _showPreferences,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: '记忆与对话',
            onPressed: connected ? null : _openHistory,
            icon: const Icon(Icons.collections_bookmark_outlined),
          ),
          IconButton(
            tooltip: '个人主页',
            onPressed: connected ? null : _openProfile,
            icon: ProfileAvatar(
              nickname: widget.user.nickname,
              imageUrl: widget.user.imageUrl,
              size: 32,
              ring: false,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: NotificationListener<ScrollMetricsNotification>(
                          onNotification: (_) {
                            _scheduleFollowLatest();
                            return false;
                          },
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _onScrollNotification,
                            child: Scrollbar(
                              controller: _scroll,
                              child: CustomScrollView(
                                key: const ValueKey('conversation-scroll'),
                                controller: _scroll,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                slivers: [
                                  if (controller.error != null)
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          8,
                                          16,
                                          0,
                                        ),
                                        child: Material(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .errorContainer,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              14,
                                              10,
                                              8,
                                              6,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  controller.error!,
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onErrorContainer,
                                                  ),
                                                ),
                                                Wrap(
                                                  children: [
                                                    TextButton(
                                                      onPressed:
                                                          _retryDefaultWake,
                                                      child: const Text('重试'),
                                                    ),
                                                    TextButton(
                                                      onPressed: _openSettings,
                                                      child: const Text('服务设置'),
                                                    ),
                                                    TextButton(
                                                      onPressed:
                                                          controller.clearError,
                                                      child: const Text('关闭'),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (messages.isEmpty) ...[
                                    SliverToBoxAdapter(
                                      child: _WelcomeCard(
                                        state: controller.state,
                                        status: status,
                                      ),
                                    ),
                                    SliverToBoxAdapter(
                                      child: _EmptyConversation(
                                        configured:
                                            controller.config.isComplete,
                                      ),
                                    ),
                                  ] else ...[
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 20,
                                        ),
                                        child: Text(
                                          '每一句，都值得被听见',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                    ),
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        16,
                                      ),
                                      sliver: SliverList.builder(
                                        itemCount: messages.length,
                                        itemBuilder: (context, index) =>
                                            _MessageBubble(
                                              entry: messages[index],
                                              config: controller.config,
                                              onOpenVideo:
                                                  _openConversationVideo,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_showBackToTop && messages.isNotEmpty)
                        Positioned(
                          top: 10,
                          right: 12,
                          child: _ScrollShortcut(
                            label: '回到顶部',
                            icon: Icons.vertical_align_top_rounded,
                            onPressed: _jumpToStart,
                          ),
                        ),
                      if (_awayFromLatest && messages.isNotEmpty)
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: _ScrollShortcut(
                            label: _newMessageCount > 0
                                ? '$_newMessageCount 条新消息'
                                : _hasNewContent
                                ? '有新内容'
                                : '最新消息',
                            icon: Icons.arrow_downward_rounded,
                            onPressed: _jumpToLatest,
                            emphasized: _hasNewContent,
                          ),
                        ),
                    ],
                  ),
                ),
                if (controller.partialTranscript.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: availableHeight * 0.10,
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.graphic_eq, size: 18, color: color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              controller.partialTranscript,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: color),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (controller.approval != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: availableHeight * 0.18,
                    ),
                    child: SingleChildScrollView(
                      child: _ApprovalCard(
                        prompt: controller.approval!,
                        onSubmit: controller.submitApproval,
                      ),
                    ),
                  ),
                _VoiceControls(
                  state: controller.state,
                  connected: connected,
                  status: status,
                  compact: keyboardOpen,
                  voiceName: capabilities
                      ?.voiceOption(_selectedVoice)
                      ?.displayName,
                  onPressed: controller.state == VoiceConnectionState.connecting
                      ? null
                      : connected
                      ? controller.disconnect
                      : !controller.config.isComplete
                      ? _openSettings
                      : capabilities?.enabled == true
                      ? _connect
                      : _reloadCapabilities,
                  configured: controller.config.isComplete,
                  available: capabilities?.enabled == true,
                ),
                _Composer(
                  controller: _text,
                  maxLines: keyboardOpen ? (availableHeight < 420 ? 1 : 2) : 4,
                  enabled: connected,
                  isSpeaking: controller.state == VoiceConnectionState.speaking,
                  onSend: _sendText,
                  onStop: controller.cancelCurrent,
                  onSpeechHint: controller.speechHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _statusColor(VoiceConnectionState state) => switch (state) {
  VoiceConnectionState.disconnected => const Color(0xff90746b),
  VoiceConnectionState.wakeListening ||
  VoiceConnectionState.ready ||
  VoiceConnectionState.listening => const Color(0xff4b836c),
  VoiceConnectionState.connecting => const Color(0xffa36d30),
  VoiceConnectionState.thinking => const Color(0xff8974b3),
  VoiceConnectionState.speaking => const Color(0xffb75d56),
};

String _statusLabel(
  VoiceConnectionState state,
  VoiceCapabilities? capabilities,
) => switch (state) {
  VoiceConnectionState.disconnected => capabilities == null ? '等待连接' : '随时聊一聊',
  VoiceConnectionState.wakeListening => '说“小美小美”唤醒我',
  VoiceConnectionState.connecting => '正在连接',
  VoiceConnectionState.ready => '已经准备好',
  VoiceConnectionState.listening => '正在认真听',
  VoiceConnectionState.thinking => '正在想一想',
  VoiceConnectionState.speaking => '正在为你回答',
};

class _ScrollShortcut extends StatelessWidget {
  const _ScrollShortcut({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 3,
    shadowColor: Colors.black.withValues(alpha: 0.12),
    color: emphasized
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _VoiceControls extends StatelessWidget {
  const _VoiceControls({
    required this.state,
    required this.connected,
    required this.status,
    required this.compact,
    required this.voiceName,
    required this.onPressed,
    required this.configured,
    required this.available,
  });
  final VoiceConnectionState state;
  final bool connected;
  final String status;
  final bool compact;
  final String? voiceName;
  final VoidCallback? onPressed;
  final bool configured;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = connected
        ? '结束对话'
        : !configured
        ? '配置服务'
        : !available
        ? '连接服务'
        : '现在开始说话';
    final button = FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: connected
            ? theme.colorScheme.surfaceContainerHighest
            : const Color(0xffb85f56),
        foregroundColor: connected ? theme.colorScheme.onSurface : Colors.white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      icon: Icon(connected ? Icons.stop_rounded : Icons.mic_rounded, size: 20),
      label: Text(label, textAlign: TextAlign.center),
    );
    return Container(
      key: const ValueKey('voice-controls'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (compact) {
            return Align(alignment: Alignment.centerRight, child: button);
          }
          final caption = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                connected ? status : '语音陪伴',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                connected ? voiceName ?? '正在对话中' : '喊“小美，小美”，我在这里',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 350 &&
              MediaQuery.textScalerOf(context).scale(14) > 19) {
            return SizedBox(width: double.infinity, child: button);
          }
          return Row(
            children: [
              Expanded(child: caption),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.state, required this.status});
  final VoiceConnectionState state;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xff3a2824), Color(0xff241e2e)]
              : const [Color(0xffffe9df), Color(0xfff3e8ff)],
        ),
      ),
      child: Column(
        children: [
          _VoiceOrb(state: state, color: _statusColor(state), dark: dark),
          const SizedBox(height: 20),
          Text(
            '嗨，我是小美',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '生活的碎片、突然的灵感，都可以说给我听。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 16),
          _StatusPill(label: status, color: _statusColor(state), dark: dark),
        ],
      ),
    );
  }
}

class _ConversationPreferences extends StatelessWidget {
  const _ConversationPreferences({
    required this.capabilities,
    required this.selectedAgent,
    required this.selectedVoice,
    required this.connected,
    required this.processingState,
    required this.threadId,
    required this.onAgentChanged,
    required this.onVoiceChanged,
    required this.onConfigure,
    required this.onReload,
  });
  final VoiceCapabilities? capabilities;
  final AgentCapability? selectedAgent;
  final String? selectedVoice;
  final bool connected;
  final AudioProcessingState? processingState;
  final String? threadId;
  final ValueChanged<String?> onAgentChanged;
  final ValueChanged<String?> onVoiceChanged;
  final VoidCallback onConfigure;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final selectedVoiceOption = capabilities?.voiceOption(selectedVoice);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: dark ? const Color(0xff25211f) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: dark ? const Color(0xff3b3430) : const Color(0xffeee5df),
        ),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '对话偏好',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (threadId != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '继续上次对话',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xff8b675e),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 13),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selectedAgent?.id,
                decoration: const InputDecoration(
                  labelText: '助手',
                  prefixIcon: Icon(Icons.auto_awesome_rounded, size: 19),
                  isDense: true,
                ),
                items: capabilities?.agents
                    .map(
                      (agent) => DropdownMenuItem(
                        value: agent.id,
                        child: Text(
                          recordAgentName(agent.id),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: connected ? null : onAgentChanged,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('${capabilities?.ttsModel}:$selectedVoice'),
                isExpanded: true,
                initialValue: selectedVoice,
                decoration: const InputDecoration(
                  labelText: '音色',
                  prefixIcon: Icon(Icons.spatial_audio_off_rounded, size: 19),
                  isDense: true,
                ),
                items: capabilities?.voiceOptions
                    .map(
                      (voice) => DropdownMenuItem<String>(
                        value: voice.id,
                        child: Text(
                          voice.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: connected ? null : onVoiceChanged,
              ),
            ],
          ),
          if (selectedAgent?.id == 'mem0-chatbot') ...[
            const SizedBox(height: 8),
            Text(
              'Mem0 记忆状态可在聊天记录中查看',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (selectedVoiceOption != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                connected
                    ? '当前音色：${selectedVoiceOption.displayName}；结束会话后可更换'
                    : selectedVoiceOption.description.isEmpty
                    ? '选择音色后，点击“现在开始说话”即可体验'
                    : selectedVoiceOption.description,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
          if (processingState != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _FeatureChip(
                  icon: Icons.noise_control_off_rounded,
                  label: processingState!.noiseSuppressionEnabled
                      ? '智能降噪'
                      : '降噪不可用',
                ),
                const SizedBox(width: 8),
                _FeatureChip(
                  icon: Icons.hearing_rounded,
                  label: processingState!.aecEnabled
                      ? '回声消除'
                      : processingState!.aecAvailable
                      ? '对话时回声消除'
                      : '回声消除不可用',
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (capabilities == null || !capabilities!.enabled)
                  TextButton.icon(
                    onPressed: onReload,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(capabilities == null ? '重新读取能力' : '重新检查服务'),
                  ),
                TextButton.icon(
                  onPressed: connected ? null : onConfigure,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('服务设置'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.dark,
  });

  final String label;
  final Color color;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: dark ? const Color(0xfffff8f2) : const Color(0xff60443d),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceOrb extends StatelessWidget {
  const _VoiceOrb({
    required this.state,
    required this.color,
    required this.dark,
  });

  final VoiceConnectionState state;
  final Color color;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final active = state != VoiceConnectionState.disconnected;
    return Container(
      width: 90,
      height: 90,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: dark ? 0.08 : 0.54),
        border: Border.all(color: Colors.white.withValues(alpha: 0.56)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: active
                ? [const Color(0xffef9b89), color]
                : const [Color(0xffd9c5bd), Color(0xffad958c)],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.28),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          state == VoiceConnectionState.thinking
              ? Icons.auto_awesome_rounded
              : state == VoiceConnectionState.speaking
              ? Icons.graphic_eq_rounded
              : Icons.mic_rounded,
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff332d2a)
              : const Color(0xfff8f2ee),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: const Color(0xffb96f61)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              configured ? '今天想聊点什么？' : '还差一步，就能认识小美',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              configured ? '喊“小美，小美”，或点下方按钮开始对话' : '配置服务后，小美会在首页默认等待你的呼唤',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            if (configured) ...[
              const SizedBox(height: 13),
              const Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PromptChip(icon: Icons.wb_sunny_outlined, label: '帮我规划今天'),
                  _PromptChip(
                    icon: Icons.lightbulb_outline_rounded,
                    label: '给我一个灵感',
                  ),
                  _PromptChip(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: '陪我聊一会儿',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xff2b2623) : const Color(0xfffff8f3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark ? const Color(0xff403835) : const Color(0xffeee1da),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xffc47869)),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.entry,
    required this.config,
    required this.onOpenVideo,
  });

  final ConversationEntry entry;
  final AppConfig config;
  final Future<void> Function(VideoReference video, bool play) onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final human = entry.role == 'human';
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: human ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: (constraints.maxWidth * 0.88).clamp(0, 560),
          ),
          margin: EdgeInsets.only(top: human ? 8 : 0, bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: human
                ? null
                : dark
                ? const Color(0xff292422)
                : Colors.white,
            gradient: human
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? const [Color(0xff67454b), Color(0xff503b50)]
                        : const [Color(0xfff9e1da), Color(0xfff0def0)],
                  )
                : null,
            border: human
                ? null
                : Border.all(
                    color: dark
                        ? const Color(0xff3b3330)
                        : const Color(0xffeee5df),
                  ),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(human ? 22 : 6),
              bottomRight: Radius.circular(human ? 6 : 22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                entry.text.isEmpty
                    ? (entry.video == null ? '…' : '这是为你找到的视频。')
                    : entry.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                  color: dark
                      ? const Color(0xfffaf1ed)
                      : const Color(0xff493a35),
                ),
              ),
              if (!human && entry.memoryStatus != null)
                MemoryStatusNote(status: entry.memoryStatus!),
              if (!human && entry.video != null)
                VideoMessageCard(
                  video: entry.video!,
                  config: config,
                  onOpen: (play) => onOpenVideo(entry.video!, play),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.prompt, required this.onSubmit});

  final ApprovalPrompt prompt;
  final ValueChanged<Object?> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.approval_outlined),
                const SizedBox(width: 12),
                Expanded(child: Text(prompt.value?.toString() ?? '需要业务确认')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => onSubmit(false),
                  child: const Text('拒绝'),
                ),
                FilledButton(
                  onPressed: () => onSubmit(true),
                  child: const Text('同意'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.maxLines,
    required this.enabled,
    required this.isSpeaking,
    required this.onSend,
    required this.onStop,
    required this.onSpeechHint,
  });

  final TextEditingController controller;
  final int maxLines;
  final bool enabled;
  final bool isSpeaking;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onSpeechHint;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xff292421)
                : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xff413936)
                  : const Color(0xffeadfd9),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: '我要插话',
                onPressed: enabled ? onSpeechHint : null,
                icon: const Icon(Icons.record_voice_over_rounded),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: maxLines,
                  textInputAction: TextInputAction.send,
                  onSubmitted: enabled ? (_) => onSend() : null,
                  decoration: const InputDecoration(
                    hintText: '也可以写下想说的话…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (isSpeaking)
                IconButton.filled(
                  tooltip: '立即停止回答',
                  onPressed: onStop,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xffd65f58),
                  ),
                  icon: const Icon(Icons.stop_rounded),
                )
              else
                IconButton.filled(
                  tooltip: '发送文字',
                  onPressed: enabled ? onSend : null,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xffd87568),
                  ),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
