import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/memory_models.dart';
import '../../core/theme/editorial_widgets.dart';
import '../conversations/chat_record_widgets.dart';
import 'memory_history_page.dart';
import 'memory_widgets.dart';

class MemoryDetailPage extends StatefulWidget {
  const MemoryDetailPage({
    super.key,
    required this.api,
    required this.memoryId,
  });
  final AgentApiClient api;
  final String memoryId;

  @override
  State<MemoryDetailPage> createState() => _MemoryDetailPageState();
}

class _MemoryDetailPageState extends State<MemoryDetailPage> {
  MemoryRecord? _record;
  bool _loading = true;
  bool _writing = false;
  bool _changed = false;
  bool _deleted = false;
  bool _needsReview = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_writing || _deleted) return;
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final record = await widget.api.memory(widget.memoryId);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _record = record;
        _needsReview = false;
      });
    } catch (error) {
      if (mounted && requestId == _requestId) {
        setState(() {
          _error = memoryErrorMessage(error);
          _record = null;
        });
      }
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final record = _record;
    if (record == null || _writing || _needsReview) return;
    final updated = await Navigator.of(context).push<MemoryRecord>(
      MaterialPageRoute(
        builder: (_) => MemoryEditPage(api: widget.api, record: record),
      ),
    );
    if (!mounted) return;
    _changed = true;
    if (updated != null) {
      setState(() {
        _record = updated;
        _changed = true;
      });
    }
    await _load();
  }

  Future<void> _delete() async {
    if (_writing || _record == null || _needsReview) return;
    if (!await confirmMemoryDeletion(context, all: false) || !mounted) return;
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      await widget.api.deleteMemory(widget.memoryId);
      if (!mounted) return;
      setState(() {
        _deleted = true;
        _changed = true;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这条长期记忆已删除')));
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = memoryErrorMessage(error, writing: true);
          _needsReview = memoryWriteUncertain(error);
        });
      }
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  void _leave() {
    if (!_writing) Navigator.of(context).pop(_changed || _needsReview);
  }

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    final record = _record;
    final canWrite =
        record != null && !_loading && !_writing && !_needsReview && !_deleted;
    return PopScope<bool>(
      canPop: !_writing && !_changed && !_needsReview,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: BackButton(onPressed: _writing ? null : _leave),
          title: const Text('记忆详情'),
          backgroundColor: palette.background,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: '刷新记忆详情',
              onPressed: _loading || _writing || _deleted ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: RecordLayout(
          child: RefreshIndicator.adaptive(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              children: [
                const RecordHero(
                  eyebrow: 'YOUR MEMORY, YOUR WORDS',
                  title: '让记忆，更准确。',
                  description: '生活在变化，你也可以更新助手记住的事。',
                  icon: Icons.auto_awesome_outlined,
                ),
                const SizedBox(height: 22),
                if (_loading || _writing) const MemoryLoading(),
                if (_error != null) ...[
                  MemoryNotice(message: _error!, error: true),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loading || _writing ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('刷新核对当前状态'),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_deleted) ...[
                  const MemoryNotice(
                    message: '这条记忆已删除。它不会再作为长期记忆使用，你仍可以查看它的变更历史。',
                  ),
                  const SizedBox(height: 16),
                ],
                if (record != null && !_loading) ...[
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _deleted ? '删除前的内容' : '小美记住了',
                          style: TextStyle(
                            color: palette.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SelectableText(
                          record.memory,
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 19,
                            height: 1.8,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            RecordTag(label: recordAgentName(record.agentId)),
                            RecordTag(label: _deleted ? '已删除' : '长期记忆'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '创建于 ${memoryDateLabel(record.createdAt)}\n更新于 ${memoryDateLabel(record.updatedAt)}',
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 12,
                            height: 1.8,
                          ),
                        ),
                        if (record.metadata['source_thread_id'] is String) ...[
                          const SizedBox(height: 12),
                          Text(
                            '来源：聊天中提炼的记忆',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!_deleted)
                    FilledButton.icon(
                      onPressed: canWrite ? _edit : null,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('编辑记忆'),
                    ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: _writing
                      ? null
                      : () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => MemoryHistoryPage(
                              api: widget.api,
                              memoryId: widget.memoryId,
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('查看变更历史'),
                ),
                if (!_deleted && record != null) ...[
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: canWrite ? _delete : null,
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                    label: const Text('删除这条记忆'),
                  ),
                ],
                if (_deleted) ...[
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _leave, child: const Text('返回记忆列表')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MemoryEditPage extends StatefulWidget {
  const MemoryEditPage({super.key, required this.api, required this.record});
  final AgentApiClient api;
  final MemoryRecord record;

  @override
  State<MemoryEditPage> createState() => _MemoryEditPageState();
}

class _MemoryEditPageState extends State<MemoryEditPage> {
  late final TextEditingController _text;
  bool _saving = false;
  bool _needsReview = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.record.memory)
      ..addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _text.removeListener(_changed);
    _text.dispose();
    super.dispose();
  }

  bool get _dirty => _text.text.trim() != widget.record.memory.trim();

  Future<void> _leave() async {
    if (_saving) return;
    if (_dirty && !_needsReview) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('放弃这次修改？'),
          content: const Text('尚未保存的内容会丢失。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃修改'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (_saving ||
        _needsReview ||
        !_dirty ||
        text.isEmpty ||
        text.runes.length > 6000) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final record = await widget.api.updateMemory(widget.record.id, text);
      if (mounted) Navigator.pop(context, record);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = memoryErrorMessage(error, writing: true);
          _needsReview = memoryWriteUncertain(error);
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    final count = _text.text.trim().runes.length;
    return PopScope<MemoryRecord>(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          title: const Text('编辑记忆'),
          backgroundColor: palette.background,
          leading: BackButton(onPressed: _leave),
        ),
        body: RecordLayout(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              const EditorialHeading(
                eyebrow: 'THE MEMORY DESK',
                title: '写下现在的你',
                subtitle: '保持具体、准确。保存后，小美将使用更新后的记忆。',
              ),
              const SizedBox(height: 24),
              TextField(
                key: const ValueKey('memory-editor'),
                controller: _text,
                enabled: !_saving && !_needsReview,
                minLines: 6,
                maxLines: 14,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: palette.ink, height: 1.7),
                decoration: InputDecoration(
                  labelText: '记忆内容',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: palette.surface,
                  errorText: count == 0
                      ? '请填写记忆内容'
                      : count > 6000
                      ? '最多支持 6000 个字符'
                      : null,
                  counterText: '$count / 6000',
                ),
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[
                MemoryNotice(message: _error!, error: true),
                const SizedBox(height: 16),
              ],
              if (_needsReview)
                OutlinedButton(
                  onPressed: _leave,
                  child: const Text('返回并核对当前状态'),
                )
              else
                FilledButton.icon(
                  onPressed: _saving || !_dirty || count == 0 || count > 6000
                      ? null
                      : _save,
                  icon: _saving
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.background,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? '正在保存…' : '保存修改'),
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
