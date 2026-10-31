/// 메일 본문을 채팅 말풍선용으로 정리하는 유틸

/// HTML 메일을 텍스트로 변환 (인용 blockquote 제거)
String htmlToText(String html) {
  var s = html;
  s = s.replaceAll(
    RegExp(r'<(script|style|head)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true),
    '',
  );
  s = s.replaceAll(
    RegExp(r'<blockquote[^>]*>.*?</blockquote>', caseSensitive: false, dotAll: true),
    '',
  );
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</(p|div|tr|li|h[1-6])>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code == null ? '' : String.fromCharCode(code);
  });
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

final RegExp _origMsg = RegExp(
  r'^-{2,}\s*(Original Message|Forwarded message|Reply Message|원본 메시지|원본 메세지|전달된 메시지)',
  caseSensitive: false,
);
final RegExp _fromLine = RegExp(r'^(From|보낸\s*사람)\s*:', caseSensitive: false);
final RegExp _sentLine =
    RegExp(r'^(Sent|Date|보낸\s*날짜|보낸\s*시간|날짜)\s*:', caseSensitive: false);

bool _isQuoteStart(String t, String next) {
  if (t.isEmpty) return false;
  if (_origMsg.hasMatch(t)) return true;
  if (RegExp(r'^_{10,}$').hasMatch(t)) return true;
  // "On ... wrote:" (줄바꿈으로 두 줄이 되는 경우 포함)
  if (t.startsWith('On ') && (t.endsWith('wrote:') || next.endsWith('wrote:'))) {
    return true;
  }
  // "2026년 1월 1일 (월) 오전 10:00, 홍길동 <a@b.com>님이 작성:"
  if (t.endsWith('작성:') || t.contains('님이 작성')) return true;
  // Outlook 헤더 블록
  if (_fromLine.hasMatch(t) && _sentLine.hasMatch(next)) return true;
  return false;
}

/// 답장 메일에 딸려 오는 인용문·서명을 잘라내고 새로 쓴 부분만 남긴다.
/// 결과가 비면 원문을 그대로 돌려준다.
String stripQuoted(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final t = line.trim();
    final next = i + 1 < lines.length ? lines[i + 1].trim() : '';
    if (_isQuoteStart(t, next)) break;
    if (t == '--') break; // 서명 구분선
    if (t.startsWith('>')) continue;
    out.add(line);
  }
  final s = out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return s.isEmpty ? raw.trim() : s;
}

/// HTML 메일을 화면에 표시하기 좋게 정리한다 (스크립트·스타일·인용문 제거).
/// 표시할 내용이 없거나 너무 크면 null.
String? sanitizeHtml(String html) {
  var s = html;
  final body = RegExp(r'<body[^>]*>(.*)</body>', caseSensitive: false, dotAll: true)
      .firstMatch(s);
  if (body != null) s = body.group(1)!;
  s = s.replaceAll(
    RegExp(r'<(script|style|head|title|iframe|object|embed|form)[^>]*>.*?</\1>',
        caseSensitive: false, dotAll: true),
    '',
  );
  s = s.replaceAll(RegExp(r'<(meta|link|input|base)[^>]*>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  s = s.replaceAll(
    RegExp(r'<blockquote[^>]*>.*?</blockquote>', caseSensitive: false, dotAll: true),
    '',
  );
  s = s.replaceAll(
    RegExp(r'<div[^>]*class="gmail_attr"[^>]*>.*?</div>', caseSensitive: false, dotAll: true),
    '',
  );
  s = s.replaceAll(RegExp(r'<img[^>]*src="cid:[^"]*"[^>]*>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'\son[a-z]+="[^"]*"', caseSensitive: false), '');
  s = s.trim();
  if (s.isEmpty || s.length > 400000) return null;
  if (htmlToText(s).isEmpty && !RegExp(r'<img', caseSensitive: false).hasMatch(s)) {
    return null;
  }
  return s;
}

// ---------------------------------------------------------------- HTML 메일

final RegExp _imgTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final RegExp _remoteSrc = RegExp(r'''src\s*=\s*["']?\s*https?:''', caseSensitive: false);

/// 원격(http/https) 이미지가 들어 있는지
bool hasRemoteImages(String html) =>
    _imgTag.allMatches(html).any((m) => _remoteSrc.hasMatch(m.group(0)!));

/// 원격 이미지를 [이미지] 표시로 바꿔 차단 (추적 이미지 방지)
String blockRemoteImages(String html) => html.replaceAllMapped(
      _imgTag,
      (m) => _remoteSrc.hasMatch(m.group(0)!) ? '<span>[이미지]</span>' : m.group(0)!,
    );
