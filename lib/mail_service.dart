import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'text_utils.dart';

/// POP3 / IMAP 수신, SMTP 발송
class MailService {
  static bool isGmail(Account acc) {
    final h = acc.inHost.toLowerCase();
    final e = acc.email.trim().toLowerCase();
    return h.contains('gmail.com') ||
        h.contains('googlemail.com') ||
        e.endsWith('@gmail.com') ||
        e.endsWith('@googlemail.com');
  }

  /// 로그인에 쓸 비밀번호. Gmail 앱 비밀번호는 "abcd efgh ijkl mnop"처럼 공백이 섞여 보이므로
  /// 공백을 모두 제거한다. 그 외 서비스는 줄바꿈만 제거한다.
  static String _pw(Account acc) => isGmail(acc)
      ? acc.password.replaceAll(RegExp(r'[\s\u00A0]'), '')
      : acc.password.replaceAll(RegExp(r'[\r\n]'), '');

  /// 오류를 사용자가 이해할 수 있는 안내문으로 바꾼다.
  static String explain(Object e, Account acc) {
    final raw = e.toString();
    final low = raw.toLowerCase();
    final gmail = isGmail(acc);
    final short = raw.length > 200 ? '${raw.substring(0, 200)}...' : raw;
    String msg;
    if (low.contains('application-specific') ||
        low.contains('app password') ||
        low.contains('web login required') ||
        low.contains('webalert')) {
      msg = 'Gmail은 일반 비밀번호로 연결할 수 없습니다. Google 계정에서 2단계 인증을 켜고 '
          '"앱 비밀번호"(16자리)를 만들어 비밀번호 칸에 입력하세요.';
    } else if (low.contains('authenticationfailed') ||
        low.contains('invalid credentials') ||
        low.contains('authentication failed') ||
        low.contains('login failed') ||
        low.contains('username and password not accepted') ||
        low.contains('535') ||
        low.contains('auth')) {
      msg = gmail
          ? 'Gmail 로그인 실패: ① 일반 비밀번호가 아니라 "앱 비밀번호"를 입력했는지 ② Gmail 설정 > '
              '전달 및 POP/IMAP에서 IMAP(또는 POP)을 "사용"으로 켰는지 확인하세요. '
              '회사/학교(Google Workspace) 계정은 관리자가 막아 두었을 수 있습니다.'
          : '로그인 실패: 이메일/비밀번호(또는 앱 비밀번호)와, 메일 서비스 설정에서 POP3/IMAP 사용을 '
              '켰는지 확인하세요.';
    } else if (low.contains('timeout') || low.contains('timed out')) {
      msg = '서버에 연결할 수 없습니다(시간 초과). 서버 주소·포트·SSL 설정과 인터넷 연결을 확인하세요.';
    } else if (low.contains('failed host lookup') || low.contains('socketexception')) {
      msg = '서버 주소를 찾을 수 없거나 네트워크가 연결되어 있지 않습니다. 서버 주소와 인터넷 연결을 확인하세요.';
    } else if (low.contains('handshake') || low.contains('certificate') || low.contains('tls')) {
      msg = 'SSL/TLS 연결에 실패했습니다. 포트와 SSL 사용 설정이 서버와 맞는지 확인하세요 '
          '(IMAP 993 / POP3 995 / SMTP 465는 SSL 켜기, 587은 SSL 끄고 STARTTLS).';
    } else {
      return short;
    }
    return '$msg\n(자세한 내용: $short)';
  }

  static const Duration _timeout = Duration(seconds: 20);

  /// 한 번에 가져올 최대 메일 수 (처음 연결 시 오래된 메일은 건너뜀)
  static const int _maxFetch = 60;

  static const String _initKey = '__init__';

  // ------------------------------------------------------------------ 수신

  /// 새 메시지를 가져온다. [seen]은 POP3 UIDL 및 최초 동기화 표시용으로 갱신된다.
  /// 최초 동기화 때 가져온 메일은 모두 "읽음"으로 처리한다.
  static Future<List<ChatMessage>> fetch(
    Account acc,
    Set<String> seen,
    Set<String> known,
  ) async {
    final first = !seen.contains(_initKey);
    final result = acc.protocol == 'pop3'
        ? await _fetchPop(acc, seen, first, known)
        : await _fetchImap(acc, first, known);
    seen.add(_initKey);
    return result;
  }

  static Future<List<ChatMessage>> _fetchImap(
    Account acc,
    bool first,
    Set<String> known,
  ) async {
    final client = ImapClient(isLogEnabled: false);
    final out = <ChatMessage>[];
    try {
      await client.connectToServer(
        acc.inHost,
        acc.inPort,
        isSecure: acc.inSecure,
        timeout: _timeout,
      );
      if (!acc.inSecure) {
        try {
          await client.startTls();
        } catch (_) {}
      }
      await client.login(acc.username, _pw(acc));

      Mailbox? sent;
      try {
        final boxes = await client.listMailboxes();
        for (final b in boxes) {
          if (b.isSent) {
            sent = b;
            break;
          }
        }
      } catch (_) {}

      final inbox = await client.selectInbox();
      if (inbox.messagesExists > 0) {
        out.addAll(await _imapRecent(client, acc, first, known));
      }
      if (sent != null) {
        final box = await client.selectMailbox(sent);
        if (box.messagesExists > 0) {
          out.addAll(await _imapRecent(client, acc, first, known));
        }
      }
    } finally {
      try {
        await client.logout();
      } catch (_) {}
      try {
        await client.disconnect();
      } catch (_) {}
    }
    return out;
  }

  static Future<List<ChatMessage>> _imapRecent(
    ImapClient client,
    Account acc,
    bool first,
    Set<String> known,
  ) async {
    final res = await client.fetchRecentMessages(
      messageCount: _maxFetch,
      criteria: '(FLAGS BODY.PEEK[])',
    );
    final out = <ChatMessage>[];
    for (final m in res.messages) {
      final cm = await _convert(acc, m,
          read: first || m.isSeen, fallbackId: 'uid-${m.uid}', known: known);
      if (cm != null) out.add(cm);
    }
    return out;
  }

  static Future<List<ChatMessage>> _fetchPop(
    Account acc,
    Set<String> seen,
    bool first,
    Set<String> known,
  ) async {
    final client = PopClient(isLogEnabled: false);
    final out = <ChatMessage>[];
    try {
      await client.connectToServer(
        acc.inHost,
        acc.inPort,
        isSecure: acc.inSecure,
        timeout: _timeout,
      );
      if (!acc.inSecure) {
        try {
          await client.startTls();
        } catch (_) {}
      }
      await client.login(acc.username, _pw(acc));

      final list = await client.uidList();
      final fresh = list.where((l) => l.uid != null && !seen.contains(l.uid)).toList();
      var toGet = fresh;
      if (fresh.length > _maxFetch) {
        toGet = fresh.sublist(fresh.length - _maxFetch);
        for (final l in fresh.sublist(0, fresh.length - _maxFetch)) {
          seen.add(l.uid!);
        }
      }
      for (final l in toGet) {
        final msg = await client.retrieve(l.id!);
        final cm = await _convert(acc, msg,
            read: first, fallbackId: 'uidl-${l.uid}', known: known);
        seen.add(l.uid!);
        if (cm != null) out.add(cm);
      }
    } finally {
      try {
        await client.quit();
      } catch (_) {}
      try {
        await client.disconnect();
      } catch (_) {}
    }
    return out;
  }

  static Future<ChatMessage?> _convert(
    Account acc,
    MimeMessage m, {
    required bool read,
    required String fallbackId,
    required Set<String> known,
  }) async {
    final mid = m.getHeaderValue('message-id')?.trim();
    final hasMid = mid != null && mid.isNotEmpty;
    final id = '${acc.id}|${hasMid ? mid : fallbackId}';
    // 이미 저장된 메일은 다시 해석/저장하지 않음
    if (known.contains(id)) return null;

    final fromList = m.from ?? const <MailAddress>[];
    final fromAddr = fromList.isNotEmpty ? fromList.first.email.toLowerCase() : '';
    final mine = fromAddr.isNotEmpty && fromAddr == acc.email.trim().toLowerCase();

    var counterpart = '';
    var name = '';
    if (mine) {
      final to = m.to;
      if (to != null && to.isNotEmpty) counterpart = to.first.email.toLowerCase();
    } else {
      counterpart = fromAddr;
      if (fromList.isNotEmpty) name = fromList.first.personalName ?? '';
    }
    if (counterpart.isEmpty) return null;

    final date = m.decodeDate() ?? DateTime.now();
    var body = m.decodeTextPlainPart() ?? '';
    final rawHtml = m.decodeTextHtmlPart();
    if (body.trim().isEmpty && rawHtml != null) body = htmlToText(rawHtml);
    body = body.trim().isEmpty ? '' : stripQuoted(body);
    // HTML 파트가 있으면 HTML로도 보관해서 화면에 HTML로 표시 (내가 보낸 메일 제외)
    final html = (!mine && rawHtml != null && rawHtml.trim().isNotEmpty)
        ? sanitizeHtml(rawHtml)
        : null;

    final atts = await _saveAttachments(m, id);
    if (body.isEmpty && atts.isEmpty) body = '(내용 없음)';

    return ChatMessage(
      id: id,
      accountId: acc.id,
      messageId: hasMid ? mid : null,
      subject: m.decodeSubject() ?? '',
      counterpart: counterpart,
      counterpartName: name,
      mine: mine,
      date: date,
      text: body,
      read: mine ? true : read,
      attachments: atts,
      html: html,
    );
  }

  static String safeFileName(String name) {
    final s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    return s.isEmpty ? 'file' : s;
  }

  static Future<Directory> attachmentDir(String msgId) async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(
      '${base.path}${Platform.pathSeparator}attachments'
      '${Platform.pathSeparator}${msgId.hashCode.toUnsigned(32).toRadixString(16)}'
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
    );
    await d.create(recursive: true);
    return d;
  }

  /// 메일에 붙은 첨부파일을 앱 폴더에 저장한다.
  static Future<List<Attachment>> _saveAttachments(MimeMessage m, String msgId) async {
    final out = <Attachment>[];
    try {
      final infos = m.findContentInfo(disposition: ContentDisposition.attachment);
      if (infos.isEmpty) return out;
      final dir = await attachmentDir(msgId);
      final used = <String>{};
      for (var i = 0; i < infos.length; i++) {
        final info = infos[i];
        final part = m.getPart(info.fetchId);
        final data = part?.decodeContentBinary();
        if (data == null) continue;
        var name = safeFileName(info.fileName ?? 'attachment-${i + 1}');
        if (!used.add(name)) name = '${i + 1}_$name';
        final f = File('${dir.path}${Platform.pathSeparator}$name');
        await f.writeAsBytes(data);
        out.add(Attachment(name: name, path: f.path, size: data.length));
      }
    } catch (_) {}
    return out;
  }

  // ------------------------------------------------------------------ 발송

  static Future<SmtpClient> _smtpOpen(Account acc) async {
    final domain = acc.email.contains('@') ? acc.email.split('@').last : 'localhost';
    final c = SmtpClient(domain, isLogEnabled: false);
    await c.connectToServer(
      acc.smtpHost,
      acc.smtpPort,
      isSecure: acc.smtpSecure,
      timeout: _timeout,
    );
    await c.ehlo();
    if (!acc.smtpSecure) {
      await c.startTls();
    }
    try {
      await c.authenticate(acc.username, _pw(acc), AuthMechanism.plain);
    } catch (_) {
      await c.authenticate(acc.username, _pw(acc), AuthMechanism.login);
    }
    return c;
  }

  static Future<void> send(
    Account acc, {
    required String to,
    required String subject,
    required String text,
    String? messageId,
    String? inReplyTo,
    List<Attachment> attachments = const [],
  }) async {
    final builder = MessageBuilder();
    builder.from = [MailAddress(null, acc.email)];
    builder.to = [MailAddress(null, to)];
    builder.subject = subject;
    builder.addText(text);
    if (messageId != null) builder.setHeader('Message-ID', messageId);
    if (inReplyTo != null) {
      builder.setHeader('In-Reply-To', inReplyTo);
      builder.setHeader('References', inReplyTo);
    }
    for (final a in attachments) {
      await builder.addFile(File(a.path), MediaType.guessFromFileName(a.name));
    }
    final msg = builder.buildMimeMessage();

    final c = await _smtpOpen(acc);
    try {
      await c.sendMessage(msg);
    } finally {
      try {
        await c.quit();
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------------ 연결 테스트

  /// 수신·발송 서버에 로그인해 본다. 실패하면 예외를 던진다.
  static Future<void> testConnection(Account acc) async {
    if (acc.protocol == 'pop3') {
      final c = PopClient(isLogEnabled: false);
      try {
        await c.connectToServer(acc.inHost, acc.inPort,
            isSecure: acc.inSecure, timeout: _timeout);
        if (!acc.inSecure) {
          try {
            await c.startTls();
          } catch (_) {}
        }
        await c.login(acc.username, _pw(acc));
      } finally {
        try {
          await c.quit();
        } catch (_) {}
        try {
          await c.disconnect();
        } catch (_) {}
      }
    } else {
      final c = ImapClient(isLogEnabled: false);
      try {
        await c.connectToServer(acc.inHost, acc.inPort,
            isSecure: acc.inSecure, timeout: _timeout);
        if (!acc.inSecure) {
          try {
            await c.startTls();
          } catch (_) {}
        }
        await c.login(acc.username, _pw(acc));
      } finally {
        try {
          await c.logout();
        } catch (_) {}
        try {
          await c.disconnect();
        } catch (_) {}
      }
    }

    final s = await _smtpOpen(acc);
    try {
      await s.quit();
    } catch (_) {}
  }
}
