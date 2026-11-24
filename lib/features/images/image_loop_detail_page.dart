import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/file_api.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editorial_widgets.dart';
import 'data/image_api.dart';
import 'data/image_asset_picker.dart';
import 'data/image_loop_models.dart';
import 'data/image_models.dart';
import 'image_create_page.dart';
import 'image_widgets.dart';

class ImageLoopDetailPage extends StatefulWidget {
  const ImageLoopDetailPage({
    super.key,
    required this.rootId,
    required this.api,
    required this.files,
    this.initialRoot,
    this.picker,
  });

  final int rootId;
  final ImageApi api;
  final FileApi files;
  final ImageTask? initialRoot;
  final StudioImagePicker? picker;

  @override
  State<ImageLoopDetailPage> createState() => _ImageLoopDetailPageState();
}

class _ImageLoopDetailPageState extends State<ImageLoopDetailPage>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  ImageLoopHistory? _history;
  ImageTask? _root;
  ImageLoopState? _loop;
  int? _selectedId;
  Timer? _poll;
  bool _fetching = false, _closing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _root = widget.initialRoot;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          ModalRoute.isCurrentOf(context) == true &&
          _loop?.shouldPoll == true) {
        unawaited(_refresh(quiet: true));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.isCurrentOf(context) == true) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (_fetching || _closing) return;
    _fetching = true;
    if (!quiet) setState(() => _error = null);
    try {
      final history = await widget.api.loopHistoryDetail(widget.rootId);
      if (!mounted) return;
      setState(() {
        _history = history;
        _root = history.root;
        _loop = history.loop;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 404 && _history == null && _root != null) {
        await _loadUnstartedLoop();
      } else {
        _showLoadError(error, quiet: quiet);
      }
    } catch (error) {
      _showLoadError(error, quiet: quiet);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _loadUnstartedLoop() async {
    try {
      final loop = await widget.api.loopState(widget.rootId);
      if (!mounted) return;
      setState(() {
        _loop = loop;
        _error = null;
      });
    } catch (error) {
      _showLoadError(error);
    }
  }

  void _showLoadError(Object error, {bool quiet = false}) {
    if (!mounted) return;
    final missing = error is ApiException && error.statusCode == 404;
    if (quiet && !missing) return;
    setState(() {
      if (missing) {
        _loop = null;
        _root = null;
        _history = null;
      }
      _error = missing ? '这条 LOOP 记录已不可用。' : imageError(error);
    });
  }

  Future<void> _edit(ImageTask source) async {
    final created = await Navigator.of(context).push<ImageTask>(
      MaterialPageRoute(
        builder: (_) => ImageCreatePage(
          api: widget.api,
          files: widget.files,
          source: source,
          picker: widget.picker,
          loopEdit: true,
        ),
      ),
    );
    if (!mounted) return;
    if (created != null) _selectedId = created.id;
    await _refresh();
    if (mounted && created != null && _scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _close(ImageLoopExit exit, ImageTask target) async {
    final accepting = exit == ImageLoopExit.accept;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(accepting ? '将这张图像定稿？' : '结束这次 LOOP？'),
        content: Text(
          accepting
              ? '将采用「${target.displayTitle}」（#${target.id}）作为定稿，并结束这次编辑。'
              : '结束后将无法继续编辑。已经提交的版本仍会处理。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: accepting
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
            child: Text(accepting ? '确认定稿' : '确认结束'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _closing = true;
      _error = null;
    });
    final closingFrom = accepting ? target.id : widget.rootId;
    Object? failure;
    try {
      final loop = await widget.api.closeLoop(closingFrom, exit);
      if (!mounted) return;
      setState(() {
        _loop = loop;
        if (accepting) _selectedId = target.id;
      });
    } catch (error) {
      failure = error;
    } finally {
      if (mounted) setState(() => _closing = false);
    }
    if (!mounted) return;
    await _refresh();
    if (!mounted || failure == null || _error != null) return;
    final verified = accepting
        ? _loop?.status == ImageLoopStatus.accepted &&
              _loop?.acceptedId == target.id
        : _loop?.status == ImageLoopStatus.stopped;
    if (!verified) setState(() => _error = imageError(failure!));
  }

  void _select(ImageTask? image) {
    setState(() => _selectedId = image?.id);
    if (!_scroll.hasClients || _scroll.offset == 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette(context);
    final root = _root;
    final loop = _loop;
    final versions = loop?.versions ?? const <ImageTask>[];
    final images = [?root, ...versions];
    final preview = _history?.previewImage ?? root;
    final selected =
        images.where((image) => image.id == _selectedId).firstOrNull ?? preview;
    final sourceId = selected?.id == root?.id ? null : selected?.sourceImageId;
    final source = images.where((image) => image.id == sourceId).firstOrNull;
    final busy = _fetching || _closing;
    final updatedAt = _history?.updatedAt;
    final canClose = loop != null && loop.usedEdits > 0 && loop.canClose;
    return Scaffold(
      appBar: AppBar(
        title: const Text('LOOP 详情'),
        actions: [
          IconButton(
            tooltip: '刷新 LOOP 详情',
            onPressed: busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (canClose && root != null)
            PopupMenuButton<ImageLoopExit>(
              tooltip: 'LOOP 操作',
              enabled: !busy,
              onSelected: (exit) => _close(exit, root),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: ImageLoopExit.stop,
                  child: Text(
                    '结束 LOOP',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: EditorialLayout(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  sliver: SliverList.list(
                    children: [
                      if (busy && loop == null)
                        const LinearProgressIndicator(minHeight: 2),
                      if (_error case final error?) ...[
                        ImageNotice(
                          text: error,
                          onRetry: busy ? null : _refresh,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (root != null && loop != null && selected != null) ...[
                        Text(
                          root.displayTitle,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DefaultTextStyle.merge(
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: palette.muted,
                          ),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              Text(
                                loop.usedEdits == 0
                                    ? '等待首次编辑'
                                    : loop.status.label,
                              ),
                              Text('已编辑 ${loop.usedEdits}/${loop.maxEdits} 次'),
                              if (updatedAt != null)
                                Text('更新于 ${imageStudioDate(updatedAt)}'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text('原始图像 #${root.id}'),
                              selected: selected.id == root.id,
                              onSelected: (value) {
                                if (value) _select(root);
                              },
                            ),
                            if (preview != null && preview.id != root.id)
                              ChoiceChip(
                                label: Text(
                                  loop.acceptedId == preview.id
                                      ? '定稿预览'
                                      : '历史预览',
                                ),
                                selected: selected.id == preview.id,
                                onSelected: (value) {
                                  if (value) _select(null);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if ((_history?.resultUriFor(selected) ??
                                selected.resultUri)
                            case final previewUri?)
                          ImageArtwork(
                            key: ValueKey(selected.id),
                            image: selected,
                            previewUri: previewUri,
                          )
                        else
                          EditorialPanel(
                            child: selected.status == ImageTaskStatus.succeeded
                                ? const Text('暂无可预览的图片')
                                : ImageStatusLine(status: selected.status),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          _versionLabel(selected, root.id),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        _VersionMetadata(
                          image: selected,
                          accepted: loop.acceptedId == selected.id,
                          sourceId: sourceId,
                          onSourceTap: source == null
                              ? null
                              : () => _select(source),
                        ),
                        if (selected.resultUri != null &&
                            (loop.canEdit || canClose)) ...[
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (loop.canEdit)
                                FilledButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => _edit(selected),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: Text(
                                    loop.usedEdits == 0 ? '开始 LOOP' : '继续编辑',
                                  ),
                                ),
                              if (canClose)
                                OutlinedButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => _close(
                                          ImageLoopExit.accept,
                                          selected,
                                        ),
                                  icon: const Icon(Icons.check_rounded),
                                  label: const Text('采用此版本'),
                                ),
                            ],
                          ),
                        ],
                        if (selected.prompt case final prompt?) ...[
                          const SizedBox(height: 24),
                          Text(
                            selected.id == root.id ? '画面描述' : '修改描述',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            prompt,
                            style: const TextStyle(height: 1.7),
                          ),
                        ],
                        const SizedBox(height: 28),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        Text('版本记录', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
                if (root != null && loop != null && selected != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                    sliver: SliverList.separated(
                      itemCount: images.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final image = images[index];
                        return _VersionRow(
                          key: ValueKey(image.id),
                          image: image,
                          rootId: root.id,
                          selected: image.id == selected.id,
                          accepted: image.id == loop.acceptedId,
                          onTap: () => _select(image),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _versionLabel(ImageTask image, int rootId) => image.id == rootId
    ? '初稿'
    : image.loopVersion == null
    ? '编辑版本'
    : '第 ${image.loopVersion} 版';

class _VersionMetadata extends StatelessWidget {
  const _VersionMetadata({
    required this.image,
    required this.accepted,
    this.sourceId,
    this.onSourceTap,
  });

  final ImageTask image;
  final bool accepted;
  final int? sourceId;
  final VoidCallback? onSourceTap;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: Theme.of(context).textTheme.bodySmall!
        .copyWith(color: AppPalette(context).muted),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('#${image.id}'),
        ImageStatusLine(status: image.status),
        if (accepted) const Text('定稿'),
        if (sourceId case final id?)
          if (onSourceTap case final open?)
            TextButton(
              onPressed: open,
              style: TextButton.styleFrom(
                textStyle: Theme.of(context).textTheme.bodySmall,
              ),
              child: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('编辑底图 #$id'),
                  const Icon(Icons.chevron_right_rounded, size: 16),
                ],
              ),
            )
          else
            Text('编辑底图 #$id'),
      ],
    ),
  );
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    super.key,
    required this.image,
    required this.rootId,
    required this.selected,
    required this.accepted,
    required this.onTap,
  });

  final ImageTask image;
  final int rootId;
  final bool selected, accepted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette(context);
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? palette.blush : palette.background,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox.square(
                    dimension: 52,
                    child: ImagePreview(
                      uri: image.resultUri,
                      label: image.displayTitle,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _versionLabel(image, rootId),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      _VersionMetadata(
                        image: image,
                        accepted: accepted,
                        sourceId: image.id == rootId
                            ? null
                            : image.sourceImageId,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_rounded : Icons.chevron_right_rounded,
                  color: palette.accentInk,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
