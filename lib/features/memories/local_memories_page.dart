import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/memory/local_memory.dart';
import '../../core/memory/local_memory_store.dart';
import '../conversations/chat_record_widgets.dart';
import 'memories_page.dart';
import 'memory_widgets.dart';

class LocalMemoriesPage extends StatefulWidget {
  const LocalMemoriesPage({
    super.key,
    required this.config,
    this.store,
    this.api,
  });

  final AppConfig config;
  final LocalMemoryStore? store;
  final AgentApiClient? api;

  @override
  State<LocalMemoriesPage> createState() => _LocalMemoriesPageState();
}

class _LocalMemoriesPageState extends State<LocalMemoriesPage> {
  late final LocalMemoryStore _store;
  late final AgentApiClient _api;
  bool _loading = true, _busy = false;
  String? _error;
  String _query = '', _category = 'all';

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? LocalMemoryStore.forConfig(widget.config);
    _api = widget.api ?? AgentApiClient(widget.config);
    _store.addListener(_changed);
    _loading = !_store.isLoaded;
    if (_loading) unawaited(_load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      await _store.load();
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取本机记忆文件，请重试。原文件不会被覆盖。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError || error is FormatException
              ? error.toString()
              : '操作未完成，请核对后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _edit([DeviceMemoryEntry? entry]) async {
    final editor = TextEditingController(text: entry?.text ?? '');
    var category = entry?.category ?? 'profile';
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(entry == null ? '添加本机记忆' : '编辑本机记忆'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '分类'),
                  items: memoryCategories
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(memoryCategoryLabels[value]!),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => category = value!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: editor,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: '记忆内容',
                    hintText: '例如：日常回答尽量简短。',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (editor.text.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('保存到手机'),
            ),
          ],
        ),
      ),
    );
    final saved = await Navigator.of(context, rootNavigator: true).push(route);
    final text = editor.text;
    await route.completed;
    editor.dispose();
    if (saved == true && mounted) {
      await _run(() => _store.save(text, category, previous: entry));
    }
  }

  Future<void> _import() async {
    final editor = TextEditingController();
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入 Markdown'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('粘贴此前导出的完整文件。确认后替换本机有效记忆，并取消尚未完成的整理与候选。'),
              const SizedBox(height: 12),
              TextField(
                controller: editor,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'Markdown 内容'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认替换'),
          ),
        ],
      ),
    );
    final accepted = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    final markdown = editor.text;
    await route.completed;
    editor.dispose();
    if (accepted == true && mounted) {
      await _run(() => _store.importMarkdown(markdown));
    }
  }

  Future<void> _export() => _run(() async {
    if (!await _confirm(
      '复制记忆备份',
      '将记忆正文与来源复制为 Markdown。剪贴板可能被其他应用读取，请妥善保存后及时清除。',
    )) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: await _store.exportMarkdown()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Markdown 已复制，请粘贴到你选择的安全位置备份')),
      );
    }
  });

  Future<void> _review(Map<String, dynamic> proposal) async {
    final action = proposal['action'] as String;
    final target = _store.entries
        .where((entry) => entry.id == proposal['target_id'])
        .firstOrNull;
    final label = switch (action) {
      'clear' => '清空全部记忆',
      'delete' => '删除记忆',
      'update' => '修改记忆',
      _ => '保存记忆',
    };
    final accepted = await _confirm(
      label,
      [
        if (target != null) '当前：${target.text}',
        if (action == 'clear') '将清空当前全部 ${_store.entries.length} 条本机记忆。',
        if ((proposal['text'] as String? ?? '').isNotEmpty)
          '内容：${proposal['text']}',
        '来源：${proposal['source_text']}',
        '只处理本机记忆，聊天记录和 Mem0 备选数据保持各自的管理方式。',
      ].join('\n\n'),
    );
    if (accepted && mounted) {
      await _run(() => _store.review(proposal['id'] as String, true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries =
        _store.entries
            .where(
              (entry) =>
                  (_category == 'all' || entry.category == _category) &&
                  entry.text.toLowerCase().contains(_query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Scaffold(
      appBar: AppBar(
        title: const Text('本机记忆'),
        actions: [
          IconButton(
            tooltip: '添加记忆',
            onPressed: _busy || _loading || _error != null
                ? null
                : () => _edit(),
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '本机记忆管理',
            enabled: !_busy && !_loading && _error == null,
            onSelected: (value) async {
              if (value == 'export') await _export();
              if (value == 'import') await _import();
              if (value == 'clear' &&
                  await _confirm('清空本机记忆', '将清空本机全部记忆和待整理内容，无法撤销。建议先导出备份。')) {
                await _run(_store.clear);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('复制 Markdown 备份')),
              PopupMenuItem(value: 'import', child: Text('导入 Markdown')),
              PopupMenuItem(value: 'clear', child: Text('清空本机记忆')),
            ],
          ),
        ],
      ),
      body: RecordLayout(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            RecordHero(
              eyebrow: 'MEMORY · ON YOUR DEVICE',
              title: '记忆，留在你身边。',
              description:
                  '正文保存在手机的 MEMORY.md。\n聊天时仅提供筛选后的参考，整理新记忆时会将该条输入发送给服务端模型。',
              icon: Icons.bookmark_border_rounded,
              stats: [
                '${_store.entries.length} 条记忆',
                '${_store.pending.length} 项待确认',
                '${_store.queued} 项待整理',
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '本机文件按账号与服务地址隔离，未开启云端备份。卸载或丢失手机可能丢失记忆，请定期导出。聊天记录仍按服务端原有规则保存。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            if (_loading) const MemoryLoading(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              MemoryNotice(message: _error!, error: true),
              TextButton(onPressed: _load, child: const Text('重新读取文件')),
            ],
            if (!_loading && _error == null) ...[
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _store.mode,
                decoration: const InputDecoration(labelText: '下次连接使用的记忆方案'),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 'local',
                    child: Text('本机 Markdown（首选）'),
                  ),
                  DropdownMenuItem(value: 'mem0', child: Text('服务端 Mem0（备选）')),
                ],
                onChanged: _busy
                    ? null
                    : (value) => _run(() => _store.configure(mode: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动整理新记忆'),
                subtitle: const Text('关闭会取消待整理内容和候选，保留已保存记忆'),
                value: _store.automatic,
                onChanged: _busy
                    ? null
                    : (value) => _run(() => _store.configure(automatic: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('回答时使用本机记忆'),
                value: _store.useMemory,
                onChanged: _busy
                    ? null
                    : (value) => _run(() => _store.configure(useMemory: value)),
              ),
              if (_store.error != null)
                MemoryNotice(message: _store.error!, error: true),
              if (_store.queued > 0 || _store.error != null)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _store.process(_api.extractLocalMemories),
                        ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试整理'),
                ),
              for (final proposal in _store.pending)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '待确认',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            proposal['action'] == 'clear'
                                ? '清空全部本机记忆'
                                : (proposal['text'] as String? ?? '').isEmpty
                                ? '删除选中的记忆'
                                : proposal['text'] as String,
                          ),
                          const SizedBox(height: 8),
                          Text('来源：${proposal['source_text']}'),
                          Wrap(
                            spacing: 12,
                            children: [
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _review(proposal),
                                child: const Text('查看并确认'),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                        () => _store.review(
                                          proposal['id'] as String,
                                          false,
                                        ),
                                      ),
                                child: const Text('忽略候选'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              TextField(
                decoration: const InputDecoration(
                  labelText: '搜索本机记忆',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '分类'),
                items: ['all', ...memoryCategories]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(memoryCategoryLabels[value] ?? '全部'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _category = value!),
              ),
              const SizedBox(height: 16),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('这里还没有匹配的记忆。可以手动添加，也可以在聊天后回来查看。'),
                ),
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            memoryCategoryLabels[entry.category]!,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            entry.text,
                            style: const TextStyle(fontSize: 16, height: 1.65),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '更新于 ${memoryDateLabel(entry.updatedAt)} · 第 ${entry.version} 版',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (entry.sourceText != null) ...[
                            const SizedBox(height: 10),
                            SelectableText('原文证据：${entry.sourceText}'),
                          ],
                          if (entry.threadId != null)
                            SelectableText(
                              '来源对话：${entry.threadId}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (entry.sourceTime != null)
                            Text(
                              '来源时间：${memoryDateLabel(entry.sourceTime!)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          Wrap(
                            spacing: 12,
                            children: [
                              TextButton.icon(
                                onPressed: _busy ? null : () => _edit(entry),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('编辑'),
                              ),
                              TextButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (await _confirm(
                                          '忘记这条信息',
                                          '将从本机记忆移除，并取消当前待整理内容，防止旧任务重新写回。历史对话仍保留。',
                                        )) {
                                          await _run(
                                            () => _store.delete(entry),
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('忘记'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => MemoriesPage(config: widget.config),
                      ),
                    ),
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('管理 Mem0 备选记忆'),
            ),
          ],
        ),
      ),
    );
  }
}
