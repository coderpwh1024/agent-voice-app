import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import 'message_content.dart';
import 'message_image_loader.dart';

Future<void> openMessageLink(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // The same copy fallback applies when no browser can handle the link.
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('暂时无法打开链接，可以复制后查看'),
      action: SnackBarAction(
        label: '复制链接',
        onPressed: () => _copy(context, uri),
      ),
    ),
  );
}

Future<void> _copy(BuildContext context, Uri uri) async {
  await Clipboard.setData(ClipboardData(text: uri.toString()));
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('链接已复制')));
  }
}

class MessageContentView extends StatefulWidget {
  const MessageContentView({
    super.key,
    required this.text,
    required this.baseUrl,
    this.style,
    this.isStreaming = false,
  });
  final String text, baseUrl;
  final TextStyle? style;
  final bool isStreaming;
  @override
  State<MessageContentView> createState() => _MessageContentViewState();
}

class _MessageContentViewState extends State<MessageContentView> {
  late MessageContent _content;
  bool _showAll = false;
  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(MessageContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.baseUrl != widget.baseUrl) {
      _parse();
    }
  }

  void _parse() =>
      _content = MessageContent(widget.text, baseUrl: widget.baseUrl);

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(context);
    final body =
        widget.style ??
        Theme.of(context).textTheme.bodyMedium!
            .copyWith(color: p.ink, height: 1.7);
    final images = _showAll ? _content.images : _content.images.take(3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkdownBody(
          data: widget.text,
          selectable: true,
          softLineBreak: true,
          fitContent: true,
          inlineSyntaxes: [MessageUrlSyntax(), md.EmojiSyntax()],
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: body,
            a: body.copyWith(
              color: p.ink,
              decoration: TextDecoration.underline,
              decorationColor: p.accentInk,
            ),
            strong: body.copyWith(fontWeight: FontWeight.w600),
            h1: body.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
            h2: body.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
            h3: body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
            blockSpacing: 10,
            listIndent: 20,
            blockquote: body.copyWith(color: p.muted),
            blockquoteDecoration: BoxDecoration(
              color: p.blush,
              border: Border(left: BorderSide(color: p.border, width: 2)),
            ),
            code: body.copyWith(
              fontFamily: 'monospace',
              fontSize: 13,
              backgroundColor: p.blush,
            ),
            codeblockDecoration: BoxDecoration(
              color: p.blush,
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          onTapLink: (text, href, title) {
            final uri = messageUri(href, baseUrl: widget.baseUrl);
            if (uri != null) openMessageLink(context, uri);
          },
          imageBuilder: (uri, title, alt) {
            final url = messageUri(uri.toString(), baseUrl: widget.baseUrl);
            return Text(
              url == null
                  ? (alt?.isNotEmpty == true ? alt! : '图片地址不可用')
                  : (alt?.isNotEmpty == true ? alt! : '图片'),
              style: body.copyWith(color: p.muted),
            );
          },
        ),
        if (_content.images.isNotEmpty && widget.isStreaming)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '回复完成后显示图片',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          )
        else ...[
          for (final resource in images)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: MessageImageTile(
                key: ValueKey(resource.uri.toString()),
                resource: resource,
              ),
            ),
          if (!_showAll && _content.images.length > 3)
            TextButton.icon(
              onPressed: () => setState(() => _showAll = true),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text('查看其余 ${_content.images.length - 3} 张图片'),
            ),
        ],
      ],
    );
  }
}

class MessageImageTile extends StatefulWidget {
  const MessageImageTile({super.key, required this.resource});
  final MessageResource resource;
  @override
  State<MessageImageTile> createState() => _MessageImageTileState();
}

class _MessageImageTileState extends State<MessageImageTile> {
  final _loader = MessageImageLoader();
  late Future<Uint8List> _image;
  @override
  void initState() {
    super.initState();
    _image = _load();
  }

  @override
  void didUpdateWidget(MessageImageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource.uri != widget.resource.uri) {
      _loader.close();
      _image = _load();
    }
  }

  @override
  void dispose() {
    _loader.close();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _image = _load();
    });
  }

  Future<Uint8List> _load() {
    final image = _loader.load(widget.resource.uri);
    // A fast failure can precede the frame that attaches FutureBuilder's listener.
    image.ignore();
    return image;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(context);
    final uri = widget.resource.uri;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FutureBuilder<Uint8List>(
            future: _image,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
                  decoration: BoxDecoration(
                    color: p.blush,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.image_not_supported_outlined,
                            size: 20,
                            color: p.muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '图片暂不可用，仍可打开链接查看',
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 12,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('重新加载'),
                      ),
                    ],
                  ),
                );
              }
              final bytes = snapshot.data;
              if (bytes == null) {
                return SizedBox(
                  height: 128,
                  child: Center(
                    child: Semantics(
                      label: '正在加载图片',
                      child: const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                );
              }
              return Semantics(
                button: true,
                label: '放大图片：${widget.resource.label}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => _MessageImagePage(
                        resource: widget.resource,
                        bytes: bytes,
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: 48,
                        maxHeight: String.fromCharCodes(bytes.take(3)) == 'GIF'
                            ? 144
                            : 240,
                      ),
                      child: TickerMode(
                        enabled: !MediaQuery.disableAnimationsOf(context),
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                          cacheWidth: 768,
                          semanticLabel: widget.resource.label,
                          errorBuilder: (_, _, _) => const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('无法预览此图片，请打开链接查看'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          _ResourceLink(uri: uri),
        ],
      ),
    );
  }
}

class _ResourceLink extends StatelessWidget {
  const _ResourceLink({required this.uri});
  final Uri uri;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: TextButton(
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
          onPressed: () => openMessageLink(context, uri),
          child: Text(
            uri.toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppPalette(context).muted,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: '复制图片链接',
        onPressed: () => _copy(context, uri),
        icon: const Icon(Icons.copy_outlined, size: 18),
      ),
    ],
  );
}

class _MessageImagePage extends StatelessWidget {
  const _MessageImagePage({required this.resource, required this.bytes});
  final MessageResource resource;
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette(context);
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('图片预览')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                minScale: .5,
                maxScale: 5,
                child: Center(
                  child: TickerMode(
                    enabled: !MediaQuery.disableAnimationsOf(context),
                    child: Image.memory(
                      bytes,
                      cacheWidth: 1600,
                      fit: BoxFit.contain,
                      semanticLabel: resource.label,
                      errorBuilder: (_, _, _) => const Text('无法预览此图片，请打开原图查看'),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 100),
                child: SingleChildScrollView(
                  child: SelectableText(
                    resource.uri.toString(),
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.7),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _copy(context, resource.uri),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('复制链接'),
                  ),
                  TextButton.icon(
                    onPressed: () => openMessageLink(context, resource.uri),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('打开原图'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
