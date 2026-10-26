import 'package:agent_voice_app/core/content/message_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

const base = 'http://127.0.0.1:8000';

void main() {
  test('accepts HTTP(S), Unicode, queries, www and explicit root relative resources', () {
    for (final value in [
      'https://example.com/a%20b.png?token=x%2Fy&v=2#part',
      'HTTPS://example.com/中文.gif',
      'http://127.0.0.1:8000/static/a.png',
      'https://[::1]:8000/media/a.webp',
      'www.example.com/a.pdf',
      '/static/表情.gif',
    ]) {
      expect(messageUri(value, baseUrl: base), isNotNull, reason: value);
    }
    expect(
      messageUri('/static/a.png', baseUrl: base).toString(),
      '$base/static/a.png',
    );
  });
  test('rejects unsafe, credentialed, malformed and ambiguous addresses', () {
    for (final value in [
      '',
      'javascript:alert(1)',
      'data:image/png;base64,aaa',
      'file:///etc/passwd',
      'intent://example',
      'ftp://example.com/a.png',
      'https://',
      'https://user:secret@example.com/a.png',
      '//other.example/a.png',
      'https://example.com/a b',
      'https://example.com/%zz',
      'https://example.com:99999/a',
      'https://example.com/\u202eevil',
      'relative.png',
    ]) {
      expect(messageUri(value, baseUrl: base), isNull, reason: value);
    }
  });
  test('detects Chinese-adjacent links, balanced parentheses and trailing punctuation', () {
    final nodes = md.Document(inlineSyntaxes: [MessageUrlSyntax()]).parseInline(
      '看看：https://example.com/a_(b)。还有 www.example.com/file.pdf，结束。',
    );
    final links = nodes
        .whereType<md.Element>()
        .where((n) => n.tag == 'a')
        .toList();
    expect(links.map((n) => n.attributes['href']), [
      'https://example.com/a_(b)',
      'www.example.com/file.pdf',
    ]);
  });
  test('deduplicates images, understands Markdown, extensionless static and signed URLs', () {
    final content = MessageContent('''
![笑脸](https://cdn.example/asset?name=smile)
https://cdn.example/a.GIF?token=x%2Fy
https://cdn.example/a.GIF?token=x%2Fy
/static/表情
https://cdn.example/users/1/files/abc
https://example.com/read.pdf
https://example.com/movie.mp4
''', baseUrl: base);
    expect(content.images.length, 4);
    expect(content.images.first.label, '笑脸');
    expect(content.images[1].uri.query, 'token=x%2Fy');
    expect(content.images[2].uri.host, '127.0.0.1');
  });
  test('does not treat code, invalid URLs or incomplete Markdown as image instructions', () {
    final content = MessageContent('''
`https://example.com/code.png`
```
![code](https://example.com/hidden.gif)
```
![bad](file:///secret.png)
![bad](https://user:pass@example.com/x.png)
![pending](https://example.com
''', baseUrl: base);
    expect(content.images, isEmpty);
  });
}
