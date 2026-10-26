import 'package:markdown/markdown.dart' as md;

Uri? messageUri(String? value, {required String baseUrl}) {
  if (value == null) return null;
  final raw = value.trim();
  if (raw.isEmpty ||
      RegExp(r'[\s\x00-\x1f\x7f\\<>\u202a-\u202e\u2066-\u2069]')
          .hasMatch(raw) ||
      RegExp(r'%(?![a-fA-F0-9]{2})').hasMatch(raw)) {
    return null;
  }
  try {
    var uri = Uri.parse(raw.startsWith('www.') ? 'https://$raw' : raw);
    if (!uri.hasScheme) {
      if (!raw.startsWith('/') || raw.startsWith('//')) return null;
      uri = Uri.parse(baseUrl).resolveUri(uri);
    }
    if (!{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port < 1 ||
        uri.port > 65535) {
      return null;
    }
    if (!uri.host.contains(':')) {
      final host = uri.host.replaceFirst(RegExp(r'\.$'), '');
      if (host.length > 253 ||
          host
              .split('.')
              .any(
                (label) =>
                    label.isEmpty ||
                    label.runes.length > 63 ||
                    !RegExp(
                      r'^[\p{L}\p{N}](?:[\p{L}\p{N}-]*[\p{L}\p{N}])?$',
                      unicode: true,
                    ).hasMatch(label),
              )) {
        return null;
      }
    }
    return uri;
  } on FormatException {
    return null;
  }
}

class MessageUrlSyntax extends md.InlineSyntax {
  MessageUrlSyntax()
    : super(
        r'''(?:https?://|www\.)[^\s<>"\[\]{}，。！？；、（）【】“”‘’]+|/(?:static|assets|media|files)/[^\s<>"\[\]{}，。！？；、（）【】“”‘’]+''',
        caseSensitive: false,
      );
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    var text = match[0]!;
    while (text.isNotEmpty &&
        (RegExp(r'[.,;:!?]$').hasMatch(text) ||
            (text.endsWith(')') &&
                ')'.allMatches(text).length > '('.allMatches(text).length))) {
      text = text.substring(0, text.length - 1);
    }
    if (text.isEmpty) return false;
    parser.addNode(md.Element.text('a', text)..attributes['href'] = text);
    if (text.length < match[0]!.length) {
      parser.addNode(md.Text(match[0]!.substring(text.length)));
    }
    return true;
  }
}

class MessageResource {
  const MessageResource(this.uri, this.label);
  final Uri uri;
  final String label;
}

class MessageContent {
  MessageContent(String text, {required String baseUrl}) {
    final nodes = md.Document(
      inlineSyntaxes: [MessageUrlSyntax(), md.EmojiSyntax()],
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parseLines(text.split('\n'));
    final found = <String, MessageResource>{};
    void visit(md.Node node) {
      if (node is! md.Element || node.tag == 'code' || node.tag == 'pre') {
        return;
      }
      final image = node.tag == 'img';
      if (image || node.tag == 'a') {
        final uri = messageUri(
          node.attributes[image ? 'src' : 'href'],
          baseUrl: baseUrl,
        );
        if (uri != null && (image || _looksLikeImage(uri))) {
          found.putIfAbsent(
            uri.toString(),
            () => MessageResource(
              uri,
              image ? node.attributes['alt'] ?? '图片' : '图片',
            ),
          );
        }
      }
      for (final child in node.children ?? <md.Node>[]) {
        visit(child);
      }
    }

    for (final node in nodes) {
      visit(node);
    }
    images = List.unmodifiable(found.values);
  }
  late final List<MessageResource> images;

  static bool _looksLikeImage(Uri uri) {
    final path = uri.path.toLowerCase();
    if (RegExp(
      r'\.(?:jpe?g|png|gif|webp|bmp|wbmp|avif|heic|heif|svg|tiff?|ico)$',
    ).hasMatch(path)) {
      return true;
    }
    if (RegExp(r'\.[a-z0-9]{1,8}$').hasMatch(path)) return false;
    return RegExp(r'^/(?:static|assets|media)/|^/users/[^/]+/files/')
        .hasMatch(path);
  }
}
