class Account {
  Account({
    required this.id,
    required this.label,
    required this.email,
    required this.username,
    required this.password,
    required this.protocol,
    required this.inHost,
    required this.inPort,
    required this.inSecure,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecure,
  });

  final String id;
  String label;
  String email;
  String username;
  String password;

  /// 'imap' 또는 'pop3'
  String protocol;
  String inHost;
  int inPort;

  /// true = SSL/TLS 직접 접속(993/995), false = 암호화 없음
  bool inSecure;
  String smtpHost;
  int smtpPort;

  /// true = SSL(465), false = STARTTLS(587)
  bool smtpSecure;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'email': email,
        'username': username,
        'password': password,
        'protocol': protocol,
        'inHost': inHost,
        'inPort': inPort,
        'inSecure': inSecure,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'smtpSecure': smtpSecure,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        label: j['label'] as String? ?? '',
        email: j['email'] as String,
        username: j['username'] as String? ?? j['email'] as String,
        password: j['password'] as String? ?? '',
        protocol: j['protocol'] as String? ?? 'imap',
        inHost: j['inHost'] as String? ?? '',
        inPort: j['inPort'] as int? ?? 993,
        inSecure: j['inSecure'] as bool? ?? true,
        smtpHost: j['smtpHost'] as String? ?? '',
        smtpPort: j['smtpPort'] as int? ?? 465,
        smtpSecure: j['smtpSecure'] as bool? ?? true,
      );
}

enum SendStatus { sent, sending, failed }

/// 첨부파일 (앱 폴더에 저장된 사본)
class Attachment {
  Attachment({required this.name, required this.path, required this.size});

  final String name;
  final String path;
  final int size;

  Map<String, dynamic> toJson() => {'name': name, 'path': path, 'size': size};

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        name: j['name'] as String? ?? 'file',
        path: j['path'] as String? ?? '',
        size: j['size'] as int? ?? 0,
      );
}

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.accountId,
    required this.messageId,
    required this.subject,
    required this.counterpart,
    required this.counterpartName,
    required this.mine,
    required this.date,
    required this.text,
    this.status = SendStatus.sent,
    this.read = true,
    this.attachments = const [],
    this.html,
  });

  /// 저장소 내 고유 키 (계정id|Message-ID)
  final String id;
  final String accountId;
  final String? messageId;
  final String subject;

  /// 대화 상대 주소 (소문자)
  final String counterpart;
  final String counterpartName;
  final bool mine;
  final DateTime date;
  final String text;
  SendStatus status;
  bool read;
  final List<Attachment> attachments;

  /// HTML 메일 본문(정리된 것). 없으면 text를 그대로 표시
  final String? html;

  String get threadKey => '${normalizeSubject(subject).toLowerCase()}|$counterpart';

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'messageId': messageId,
        'subject': subject,
        'counterpart': counterpart,
        'counterpartName': counterpartName,
        'mine': mine,
        'date': date.millisecondsSinceEpoch,
        'text': text,
        'status': status.name,
        'read': read,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'html': html,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        accountId: j['accountId'] as String,
        messageId: j['messageId'] as String?,
        subject: j['subject'] as String? ?? '',
        counterpart: j['counterpart'] as String? ?? '',
        counterpartName: j['counterpartName'] as String? ?? '',
        mine: j['mine'] as bool? ?? false,
        date: DateTime.fromMillisecondsSinceEpoch(j['date'] as int),
        text: j['text'] as String? ?? '',
        status: SendStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => SendStatus.sent,
        ),
        read: j['read'] as bool? ?? true,
        attachments: ((j['attachments'] as List?) ?? const [])
            .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
            .toList(),
        html: j['html'] as String?,
      );
}

/// 목록에 보여줄 대화(= 같은 제목 + 같은 상대)
class ChatThread {
  ChatThread(this.key, this.messages);

  final String key;

  /// 오래된 순
  final List<ChatMessage> messages;

  ChatMessage get last => messages.last;
  String get title {
    final s = normalizeSubject(messages.last.subject);
    return s.isEmpty ? '(제목 없음)' : s;
  }

  String get counterpartLabel {
    for (final m in messages.reversed) {
      if (!m.mine && m.counterpartName.isNotEmpty) return m.counterpartName;
    }
    return last.counterpart;
  }

  int get unread => messages.where((m) => !m.mine && !m.read).length;
}

final RegExp _prefix = RegExp(
  r'^\s*((re|fwd?|답장|회신|전달|답변)\s*(\[\d+\])?\s*:\s*)+',
  caseSensitive: false,
);

String normalizeSubject(String s) => s.replaceFirst(_prefix, '').trim();
