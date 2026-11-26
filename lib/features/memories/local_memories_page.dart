import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/memory/local_memory.dart';
import '../../core/memory/local_memory_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editorial_widgets.dart';
import '../conversations/chat_record_widgets.dart';
import 'memory_widgets.dart';

const _layers = [
  (
    title: '语义记忆',
    description: '当前的事实与偏好',
    categories: ['profile', 'person', 'project'],
  ),
  (title: '情景记忆', description: '过去发生的事', categories: ['episode']),
  (title: '程序记忆', description: '可反复使用的流程', categories: ['procedure']),
];

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
  bool _loading = false, _busy = false;
  String? _error;
  String _query = '', _category = 'all';

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? LocalMemoryStore.forConfig(widget.config);
    _api = widget.api ?? AgentApiClient(widget.config);
    _store.addListener(_changed);
    if (!_store.isLoaded) unawaited(_load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _store.load();
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取手机上的记忆文件，请重试。');
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
          () => _error = switch (error) {
            StateError(:final message) => message,
            FormatException(:final message) => message,
            _ => '操作未完成，请核对后重试',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(
    String title,
    String message, {
    bool destructive = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          scrollable: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    )
                  : null,
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
          title: Text(entry == null ? '添加记忆' : '编辑记忆'),
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
                if (category == 'procedure')
                  const Text(imageReviewFirstText)
                else
                  TextField(
                    controller: editor,
                    onChanged: (_) => setDialogState(() {}),
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
              onPressed:
                  category == 'procedure' || editor.text.trim().isNotEmpty
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
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
        if (action == 'delete' || action == 'clear') '历史对话会保留。',
      ].join('\n\n'),
      destructive: action == 'delete' || action == 'clear',
    );
    if (accepted && mounted) {
      await _run(() => _store.review(proposal['id'] as String, true));
    }
  }

  Future<void> _forget(DeviceMemoryEntry entry) async {
    if (await _confirm(
          '忘记这条信息',
          '将从这部手机删除这条记忆，并取消当前待整理内容。历史对话会保留。',
          destructive: true,
        ) &&
        mounted) {
      await _run(() => _store.delete(entry));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = _store.isLoaded && !_busy;
    final palette = AppPalette(context);
    final muted = TextStyle(color: palette.muted, fontSize: 13, height: 1.6);
    final entries =
        _store.entries
            .where((entry) => entry.text.toLowerCase().contains(_query))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final groups = [
      for (final layer in _layers)
        if (_category == 'all' ||
            _category == layer.title ||
            layer.categories.contains(_category))
          (
            layer: layer,
            items: entries
                .where(
                  (entry) =>
                      layer.categories.contains(entry.category) &&
                      (_category == 'all' ||
                          _category == layer.title ||
                          _category == entry.category),
                )
                .toList(),
          ),
    ];
    final hasMatches = groups.any((group) => group.items.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: const Text('长期记忆'),
        actions: [
          IconButton(
            tooltip: '添加记忆',
            onPressed: canManage ? () => _edit() : null,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '记忆管理',
            enabled: canManage,
            onSelected: (value) async {
              if (value == 'export') await _export();
              if (value == 'import') await _import();
              if (value == 'clear' &&
                  await _confirm(
                    '清空长期记忆',
                    '将清空这部手机上的全部记忆和待整理内容，无法撤销。历史对话会保留。',
                    destructive: true,
                  ) &&
                  mounted) {
                await _run(_store.clear);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Text('复制 Markdown 备份'),
              ),
              const PopupMenuItem(value: 'import', child: Text('导入 Markdown')),
              PopupMenuItem(
                value: 'clear',
                child: Text(
                  '清空长期记忆',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RecordLayout(
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              sliver: SliverList.list(
                children: [
                  const EditorialHeading(
                    eyebrow: '',
                    title: '留在身边',
                    subtitle: '事实、经历与常用流程，保存在这部手机。',
                  ),
                  if (_store.isLoaded) ...[
                    const SizedBox(height: 12),
                    Text('${_store.entries.length} 条已保存记忆', style: muted),
                  ],
                  const SizedBox(height: 20),
                  if (_loading) const MemoryLoading(),
                  if (_error case final message?) ...[
                    MemoryNotice(message: message, error: true),
                    const SizedBox(height: 12),
                    if (!_store.isLoaded)
                      OutlinedButton(
                        onPressed: _load,
                        child: const Text('重新读取文件'),
                      ),
                  ],
                  if (_store.isLoaded) ...[
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 16),
                      title: const Text('记忆设置'),
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('自动整理新记忆'),
                          subtitle: const Text('关闭会取消待整理内容和候选，已保存记忆会保留。'),
                          value: _store.automatic,
                          onChanged: canManage
                              ? (value) => _run(
                                  () => _store.configure(automatic: value),
                                )
                              : null,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('回答时使用长期记忆'),
                          value: _store.useMemory,
                          onChanged: canManage
                              ? (value) => _run(
                                  () => _store.configure(useMemory: value),
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '正文保存在手机的 MEMORY.md。对话时发送相关参考，整理时发送该条输入。记忆没有云备份，可通过右上角菜单复制 Markdown 备份。',
                          style: muted,
                        ),
                      ],
                    ),
                    const Divider(),
                    if (_store.pending.isNotEmpty ||
                        _store.queued > 0 ||
                        _store.error != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        '待整理',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_store.pending.length} 项待确认 · ${_store.queued} 项待提炼',
                        style: muted,
                      ),
                      if (_store.error case final message?) ...[
                        const SizedBox(height: 8),
                        MemoryNotice(message: message, error: true),
                      ],
                      if (_store.queued > 0 || _store.error != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: canManage
                                ? () => _run(() async {
                                    final capabilities = await _api
                                        .capabilities();
                                    if (!capabilities.localMemory) {
                                      throw StateError('当前服务不支持整理手机上的长期记忆。');
                                    }
                                    await _store.process(
                                      _api.extractLocalMemories,
                                      version: capabilities.localMemoryVersion,
                                    );
                                  })
                                : null,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('重试整理'),
                          ),
                        ),
                      for (final proposal in _store.pending)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: EditorialPanel(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  switch (proposal['action']) {
                                    'clear' => '清空全部记忆',
                                    'delete' => '删除记忆',
                                    'update' => '修改记忆',
                                    _ => '新增记忆',
                                  },
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                if ((proposal['text'] as String? ?? '')
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  SelectableText(proposal['text'] as String),
                                ],
                                const SizedBox(height: 8),
                                Text(
                                  '来源：${proposal['source_text']}',
                                  style: muted,
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: canManage
                                          ? () => _review(proposal)
                                          : null,
                                      child: const Text('查看并确认'),
                                    ),
                                    TextButton(
                                      onPressed: canManage
                                          ? () => _run(
                                              () => _store.review(
                                                proposal['id'] as String,
                                                false,
                                              ),
                                            )
                                          : null,
                                      child: const Text('忽略候选'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 20),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: '搜索记忆',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '查看分类'),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('全部记忆'),
                        ),
                        for (final layer in _layers) ...[
                          DropdownMenuItem(
                            value: layer.title,
                            child: Text(layer.title),
                          ),
                          if (layer.categories.length > 1)
                            for (final category in layer.categories)
                              DropdownMenuItem(
                                value: category,
                                child: Text(memoryCategoryLabels[category]!),
                              ),
                        ],
                      ],
                      onChanged: (value) => setState(() => _category = value!),
                    ),
                    if (!hasMatches)
                      RecordStatus(
                        icon: Icons.bookmark_border_rounded,
                        title: _category == 'all' && _query.isEmpty
                            ? '还没有记忆'
                            : '没有匹配的记忆',
                        description: _category == 'all' && _query.isEmpty
                            ? '可以手动添加，也可以在聊过之后回来看看。'
                            : '试试其他关键词或分类。',
                      ),
                  ],
                ],
              ),
            ),
            if (_store.isLoaded &&
                (hasMatches || (_query.isEmpty && _category == 'all')))
              for (final group in groups)
                if (group.items.isNotEmpty ||
                    (_query.isEmpty && _category == 'all'))
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      group.layer.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  Text('${group.items.length} 条', style: muted),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(group.layer.description, style: muted),
                              const SizedBox(height: 12),
                              const Divider(),
                            ],
                          ),
                        ),
                        SliverList.builder(
                          itemCount: group.items.length,
                          itemBuilder: (context, index) {
                            final entry = group.items[index];
                            return _MemoryEntry(
                              key: ValueKey(entry.id),
                              entry: entry,
                              onEdit: canManage ? () => _edit(entry) : null,
                              onForget: canManage ? () => _forget(entry) : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _MemoryEntry extends StatelessWidget {
  const _MemoryEntry({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.onForget,
  });

  final DeviceMemoryEntry entry;
  final VoidCallback? onEdit;
  final VoidCallback? onForget;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette(context);
    final metadata = TextStyle(color: palette.muted, fontSize: 12, height: 1.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          memoryCategoryLabels[entry.category]!,
          style: metadata.copyWith(
            color: palette.accentInk,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          entry.text,
          style: const TextStyle(fontSize: 16, height: 1.65),
        ),
        const SizedBox(height: 8),
        if (entry.eventAt case final occurredAt?)
          Text('发生于 ${memoryDateLabel(occurredAt)}', style: metadata),
        Text(
          '更新于 ${memoryDateLabel(entry.updatedAt)} · 第 ${entry.version} 版',
          style: metadata,
        ),
        if (entry.sourceText != null ||
            entry.threadId != null ||
            entry.sourceTime != null)
          ExpansionTile(
            key: PageStorageKey('source-${entry.id}'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            expandedAlignment: Alignment.centerLeft,
            title: const Text('查看来源'),
            children: [
              if (entry.sourceText case final source?) SelectableText(source),
              if (entry.threadId case final thread?)
                SelectableText('来源对话：$thread', style: metadata),
              if (entry.sourceTime case final time?)
                Text('来源时间：${memoryDateLabel(time)}', style: metadata),
            ],
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('编辑'),
            ),
            TextButton.icon(
              onPressed: onForget,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('忘记'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Divider(),
      ],
    );
  }
}
