import 'package:flutter/material.dart';

import '../../core/api/api_models.dart';
import '../conversations/history_sheet.dart';
import 'voice_session_controller.dart';

class VoiceHomePage extends StatefulWidget {
  const VoiceHomePage({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });

  final VoiceSessionController controller;
  final Future<void> Function(BuildContext context) onOpenSettings;

  @override
  State<VoiceHomePage> createState() => _VoiceHomePageState();
}

class _VoiceHomePageState extends State<VoiceHomePage> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String? _agentId;
  String? _voice;
  String? _threadId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
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
    final voices = widget.controller.capabilities?.voices ?? const <String>[];
    if (voices.isEmpty) {
      return null;
    }
    return voices.contains(_voice) ? _voice : voices.first;
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
    try {
      await widget.controller.loadCapabilities();
    } catch (_) {
      // Error is displayed by the controller banner.
    }
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
    _agentId = thread.agentId;
    _threadId = thread.threadId;
    try {
      await widget.controller.loadHistory(thread.agentId, thread.threadId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Voice'),
        actions: [
          IconButton(
            tooltip: '历史会话',
            onPressed: connected ? null : _openHistory,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: '连接设置',
            onPressed: connected ? null : () => widget.onOpenSettings(context),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ConnectionPanel(
              state: controller.state,
              capabilities: capabilities,
              selectedAgent: agent,
              selectedVoice: voice,
              connected: connected,
              configured: controller.config.isComplete,
              threadId: _threadId,
              onAgentChanged: (value) => setState(() {
                _agentId = value;
                _threadId = null;
              }),
              onVoiceChanged: (value) => setState(() => _voice = value),
              onConnect:
                  controller.config.isComplete && capabilities?.enabled == true
                  ? _connect
                  : null,
              onDisconnect: controller.disconnect,
              onConfigure: () => widget.onOpenSettings(context),
              onReload: _reloadCapabilities,
            ),
            if (controller.error != null)
              MaterialBanner(
                content: Text(controller.error!),
                leading: const Icon(Icons.error_outline),
                actions: [
                  TextButton(
                    onPressed: controller.clearError,
                    child: const Text('关闭'),
                  ),
                ],
              ),
            Expanded(
              child: controller.messages.isEmpty
                  ? _EmptyConversation(configured: controller.config.isComplete)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      itemCount: controller.messages.length,
                      itemBuilder: (context, index) =>
                          _MessageBubble(entry: controller.messages[index]),
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
    final color = switch (state) {
      VoiceConnectionState.disconnected => Theme.of(
        context,
      ).colorScheme.outline,
      VoiceConnectionState.connecting => Colors.orange,
      VoiceConnectionState.ready ||
      VoiceConnectionState.listening => Colors.green,
      VoiceConnectionState.thinking => Colors.indigo,
      VoiceConnectionState.speaking => Colors.blue,
    };
    final label = switch (state) {
      VoiceConnectionState.disconnected => '未连接',
      VoiceConnectionState.connecting => '连接中',
      VoiceConnectionState.ready => '已就绪',
      VoiceConnectionState.listening => '正在聆听',
      VoiceConnectionState.thinking => '正在思考',
      VoiceConnectionState.speaking => '正在回答',
    };
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (threadId != null)
                  Flexible(
                    child: Text(
                      '线程 ${threadId!.substring(0, threadId!.length.clamp(0, 8))}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedAgent?.id,
                    decoration: const InputDecoration(
                      labelText: 'Agent',
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
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedVoice,
                    decoration: const InputDecoration(
                      labelText: '音色',
                      isDense: true,
                    ),
                    items: capabilities?.voices
                        .map(
                          (voice) => DropdownMenuItem(
                            value: voice,
                            child: Text(voice),
                          ),
                        )
                        .toList(),
                    onChanged: connected ? null : onVoiceChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (capabilities == null || !capabilities!.enabled)
                  TextButton.icon(
                    onPressed: onReload,
                    icon: const Icon(Icons.sync),
                    label: Text(capabilities == null ? '读取能力' : '重新检查'),
                  ),
                const Spacer(),
                if (!configured && !connected)
                  TextButton(onPressed: onConfigure, child: const Text('先配置')),
                FilledButton.icon(
                  onPressed: state == VoiceConnectionState.connecting
                      ? null
                      : connected
                      ? onDisconnect
                      : onConnect,
                  icon: Icon(connected ? Icons.link_off : Icons.mic),
                  label: Text(
                    connected
                        ? '结束会话'
                        : capabilities != null && !capabilities!.enabled
                        ? '语音未启用'
                        : '开始语音',
                  ),
                ),
              ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              configured ? Icons.multitrack_audio : Icons.settings_voice,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              configured ? '连接后直接说话' : '先配置后端地址与短期 Token',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              '麦克风会持续上传 AEC 处理后的 PCM；播放期间可直接插话或点击停止。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: '我要插话',
              onPressed: enabled ? onSpeechHint : null,
              icon: const Icon(Icons.record_voice_over),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: '也可以输入文字调试',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (isSpeaking)
              IconButton.filled(
                tooltip: '立即停止回答',
                onPressed: onStop,
                style: IconButton.styleFrom(backgroundColor: Colors.red),
                icon: const Icon(Icons.stop),
              )
            else
              IconButton.filled(
                tooltip: '发送文字',
                onPressed: enabled ? onSend : null,
                icon: const Icon(Icons.send),
              ),
          ],
        ),
      ),
    );
  }
}
