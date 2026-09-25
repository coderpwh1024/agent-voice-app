import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_models.dart';
import '../../core/audio/audio_bridge.dart';
import '../conversations/history_sheet.dart';
import '../profile/profile_avatar.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    _scheduleDefaultWake();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    _text.dispose();
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
    setState(() {});
    _scheduleDefaultWake();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && widget.controller.messages.isNotEmpty) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  AgentCapability? get _selectedAgent {
    final agents =
        widget.controller.capabilities?.agents ?? const <AgentCapability>[];
    if (agents.isEmpty) {
      return null;
    }
    final id = _agentId;
    return agents.where((agent) => agent.id == id).firstOrNull ??
        agents.where((agent) => agent.id == 'chatbot').firstOrNull ??
        agents.first;
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
    if (_enablingDefaultWake ||
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
    await widget.onOpenProfile(context);
    if (!mounted) return;
    _defaultWakeAttempted = false;
    _scheduleDefaultWake();
  }

  Future<void> _openSettings() async {
    await widget.onOpenSettings(context);
    if (!mounted) return;
    _defaultWakeAttempted = false;
    _scheduleDefaultWake();
  }

  Future<void> _openHistory() async {
    final agent = _selectedAgent;
    if (agent == null || widget.controller.isConnected) {
      return;
    }
    try {
      final threads = await widget.controller.threads(agent.id);
      if (!mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: false,
        builder: (_) => HistorySheet(
          threads: threads,
          onSelected: (thread) => _selectThread(thread),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
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
    final value = _text.text;
    _text.clear();
    widget.controller.sendText(value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final capabilities = controller.capabilities;
    final connected = controller.isConnected;
    final agent = _selectedAgent;
    final voice = _selectedVoice;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xff171412) : const Color(0xfffbf8f4),
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Agent Voice'),
            SizedBox(height: 2),
            Text(
              'YOUR EVERYDAY AI COMPANION',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
                color: Color(0xffa8877c),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '历史会话',
            onPressed: connected ? null : _openHistory,
            icon: const Icon(Icons.history_rounded),
            style: IconButton.styleFrom(
              backgroundColor: dark
                  ? const Color(0xff272220)
                  : const Color(0xfffffdfb),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: '个人主页',
            onPressed: connected ? null : _openProfile,
            icon: ProfileAvatar(
              nickname: widget.user.nickname,
              imageUrl: widget.user.imageUrl,
              size: 34,
              ring: false,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xff171412), Color(0xff201b18)]
                : const [Color(0xfffbf8f4), Color(0xfffffcfa)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _ConnectionPanel(
                        state: controller.state,
                        capabilities: capabilities,
                        selectedAgent: agent,
                        selectedVoice: voice,
                        connected: connected,
                        processingState: controller.audioProcessingState,
                        configured: controller.config.isComplete,
                        threadId: _threadId,
                        onAgentChanged: _changeAgent,
                        onVoiceChanged: _changeVoice,
                        onConnect:
                            controller.config.isComplete &&
                                capabilities?.enabled == true
                            ? _connect
                            : null,
                        onDisconnect: controller.disconnect,
                        onConfigure: _openSettings,
                        onReload: _reloadCapabilities,
                      ),
                    ),
                    if (controller.error != null)
                      SliverToBoxAdapter(
                        child: MaterialBanner(
                          content: Text(controller.error!),
                          leading: const Icon(Icons.error_outline),
                          actions: [
                            TextButton(
                              onPressed: _retryDefaultWake,
                              child: const Text('重试'),
                            ),
                            TextButton(
                              onPressed: controller.clearError,
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      ),
                    if (controller.messages.isEmpty)
                      SliverToBoxAdapter(
                        child: _EmptyConversation(
                          configured: controller.config.isComplete,
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _MessageBubble(
                              entry: controller.messages[index],
                            ),
                            childCount: controller.messages.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (controller.partialTranscript.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.graphic_eq, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          controller.partialTranscript,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (controller.approval != null)
                _ApprovalCard(
                  prompt: controller.approval!,
                  onSubmit: controller.submitApproval,
                ),
              _Composer(
                controller: _text,
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
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.state,
    required this.capabilities,
    required this.selectedAgent,
    required this.selectedVoice,
    required this.connected,
    required this.processingState,
    required this.configured,
    required this.threadId,
    required this.onAgentChanged,
    required this.onVoiceChanged,
    required this.onConnect,
    required this.onDisconnect,
    required this.onConfigure,
    required this.onReload,
  });

  final VoiceConnectionState state;
  final VoiceCapabilities? capabilities;
  final AgentCapability? selectedAgent;
  final String? selectedVoice;
  final bool connected;
  final AudioProcessingState? processingState;
  final bool configured;
  final String? threadId;
  final ValueChanged<String?> onAgentChanged;
  final ValueChanged<String?> onVoiceChanged;
  final VoidCallback? onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onConfigure;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final keyword = capabilities?.wakeWord.keyword ?? '小美';
    final statusColor = switch (state) {
      VoiceConnectionState.disconnected => const Color(0xffad958c),
      VoiceConnectionState.wakeListening => const Color(0xff5f9b83),
      VoiceConnectionState.connecting => const Color(0xffdc9a58),
      VoiceConnectionState.ready ||
      VoiceConnectionState.listening => const Color(0xff5f9b83),
      VoiceConnectionState.thinking => const Color(0xff8c7fc4),
      VoiceConnectionState.speaking => const Color(0xffd87568),
    };
    final statusLabel = switch (state) {
      VoiceConnectionState.disconnected =>
        capabilities == null ? '正在准备' : '等待启用',
      VoiceConnectionState.wakeListening => '小美正在等你',
      VoiceConnectionState.connecting => '正在靠近你',
      VoiceConnectionState.ready => '已经准备好',
      VoiceConnectionState.listening => '正在认真听',
      VoiceConnectionState.thinking => '正在想一想',
      VoiceConnectionState.speaking => '正在为你回答',
    };
    final selectedVoiceOption = capabilities?.voiceOption(selectedVoice);
    final heroText = dark ? const Color(0xfffff8f2) : const Color(0xff4b302a);
    final heroMuted = dark ? const Color(0xffdbc4bb) : const Color(0xff8b675e);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xff3a2824), Color(0xff241e2e)]
                  : const [Color(0xffffe9df), Color(0xfff3e8ff)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xffd88b78)
                    .withValues(alpha: dark ? 0.08 : 0.16),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                right: -44,
                top: -52,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: dark ? 0.04 : 0.34),
                  ),
                ),
              ),
              Positioned(
                left: -30,
                bottom: -68,
                child: Container(
                  width: 138,
                  height: 138,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xffef9e8a).withValues(alpha: 0.12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _StatusPill(
                          label: statusLabel,
                          color: statusColor,
                          dark: dark,
                        ),
                        const Spacer(),
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 15,
                          color: heroMuted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '离线唤醒',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: heroMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _VoiceOrb(state: state, color: statusColor, dark: dark),
                    const SizedBox(height: 13),
                    Text(
                      '嗨，我是小美',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: heroText,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: '直接说 '),
                          TextSpan(
                            text: '“$keyword”',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const TextSpan(text: '，我就会回应你'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: heroMuted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
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
              Row(
                children: [
                  Text(
                    '对话偏好',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (threadId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xfff5eee9),
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
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: DropdownButtonFormField<String>(
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
                                agent.id,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: connected ? null : onAgentChanged,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedVoice,
                      decoration: const InputDecoration(
                        labelText: '音色',
                        prefixIcon: Icon(
                          Icons.spatial_audio_off_rounded,
                          size: 19,
                        ),
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
                  ),
                ],
              ),
              if (selectedVoiceOption != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    connected
                        ? '当前音色：${selectedVoiceOption.displayName}；结束会话后可更换'
                        : selectedVoiceOption.description.isEmpty
                        ? '选择音色后，点击“开始语音”即可试听'
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
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: state == VoiceConnectionState.connecting
                      ? null
                      : connected
                      ? onDisconnect
                      : onConnect,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xffd87568),
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(
                    connected ? Icons.stop_circle_outlined : Icons.mic_rounded,
                  ),
                  label: Text(
                    connected
                        ? '结束当前对话'
                        : capabilities != null && !capabilities!.enabled
                        ? '语音服务暂不可用'
                        : '现在开始说话',
                  ),
                ),
              ),
              if (capabilities == null || !capabilities!.enabled || !configured)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (capabilities == null || !capabilities!.enabled)
                        TextButton.icon(
                          onPressed: onReload,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            capabilities == null ? '重新读取能力' : '重新检查服务',
                          ),
                        ),
                      if (!configured && !connected)
                        TextButton.icon(
                          onPressed: onConfigure,
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text('配置服务'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
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
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: dark ? const Color(0xfffff8f2) : const Color(0xff60443d),
              fontWeight: FontWeight.w700,
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
              configured ? '叫一声“小美”，或者点上方按钮开始对话' : '配置服务后，小美会在首页默认等待你的呼唤',
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
  const _MessageBubble({required this.entry});

  final ConversationEntry entry;

  @override
  Widget build(BuildContext context) {
    final human = entry.role == 'human';
    final color = human
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return Align(
      alignment: human ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(human ? 18 : 4),
            bottomRight: Radius.circular(human ? 4 : 18),
          ),
        ),
        child: Text(entry.text.isEmpty ? '…' : entry.text),
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
        child: Row(
          children: [
            const Icon(Icons.approval_outlined),
            const SizedBox(width: 12),
            Expanded(child: Text(prompt.value?.toString() ?? '需要业务确认')),
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
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.isSpeaking,
    required this.onSend,
    required this.onStop,
    required this.onSpeechHint,
  });

  final TextEditingController controller;
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
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
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
