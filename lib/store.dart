import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'mail_service.dart';
import 'models.dart';
import 'vault.dart';

const int kMaxAccounts = 10;

class Store extends ChangeNotifier {
  Store(this.vault);

  final Vault vault;
  final List<Account> accounts = [];
  final List<ChatMessage> messages = [];

  /// POP3: 이미 가져온 UIDL 목록 (계정id -> uid 집합)
  final Map<String, Set<String>> seenUids = {};

  /// 계정별 마지막 동기화 오류
  final Map<String, String> errors = {};

  bool syncing = false;
  Timer? _timer;
  Directory get _dir => vault.dir;

  // ---------------------------------------------------------------- 저장/로드

  Future<void> load() async {
    accounts.clear();
    messages.clear();
    seenUids.clear();
    errors.clear();
    final a = await _read('accounts');
    if (a is List) {
      accounts.addAll(a.map((e) => Account.fromJson(e as Map<String, dynamic>)));
    }
    final m = await _read('messages');
    if (m is List) {
      messages.addAll(m.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)));
    }
    final s = await _read('seen');
    if (s is Map) {
      s.forEach((k, v) => seenUids[k as String] = Set<String>.from(v as List));
    }
    notifyListeners();
  }

  /// 잠금: 메모리의 데이터와 자동 동기화를 정리
  void unload() {
    _timer?.cancel();
    accounts.clear();
    messages.clear();
    seenUids.clear();
    errors.clear();
  }

  String _path(String name, String ext) =>
      '${_dir.path}${Platform.pathSeparator}$name.$ext';

  Future<dynamic> _read(String name) async {
    try {
      final enc = File(_path(name, 'enc'));
      if (await enc.exists()) {
        final clear = await vault.decryptBytes(await enc.readAsBytes());
        return jsonDecode(utf8.decode(clear));
      }
      // 이전 버전(암호화 이전)의 평문 파일이 있으면 암호화해서 옮긴다
      final plain = File(_path(name, 'json'));
      if (await plain.exists()) {
        final data = jsonDecode(await plain.readAsString());
        await _write(name, data);
        await plain.delete();
        return data;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _write(String name, Object data) async {
    final f = File(_path(name, 'enc'));
    final tmp = File('${f.path}.tmp');
    final enc = await vault.encryptBytes(utf8.encode(jsonEncode(data)));
    await tmp.writeAsBytes(enc);
    await tmp.rename(f.path);
  }

  Future<void> _saveAccounts() =>
      _write('accounts', accounts.map((e) => e.toJson()).toList());
  Future<void> _saveMessages() =>
      _write('messages', messages.map((e) => e.toJson()).toList());
  Future<void> _saveSeen() =>
      _write('seen', seenUids.map((k, v) => MapEntry(k, v.toList())));

  // ---------------------------------------------------------------- 계정

  Account? accountById(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> saveAccount(Account acc) async {
    final i = accounts.indexWhere((a) => a.id == acc.id);
    if (i >= 0) {
      accounts[i] = acc;
    } else {
      accounts.add(acc);
    }
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> deleteAccount(String id) async {
    accounts.removeWhere((a) => a.id == id);
    messages.removeWhere((m) => m.accountId == id);
    seenUids.remove(id);
    errors.remove(id);
    await _saveAccounts();
    await _saveMessages();
    await _saveSeen();
    notifyListeners();
  }

  // ---------------------------------------------------------------- 대화

  List<ChatThread> get threads {
    final map = <String, List<ChatMessage>>{};
    for (final m in messages) {
      map.putIfAbsent(m.threadKey, () => []).add(m);
    }
    final list = map.entries.map((e) {
      e.value.sort((a, b) => a.date.compareTo(b.date));
      return ChatThread(e.key, e.value);
    }).toList()
      ..sort((a, b) => b.last.date.compareTo(a.last.date));
    return list;
  }

  ChatThread? threadByKey(String key) {
    final list = messages.where((m) => m.threadKey == key).toList();
    if (list.isEmpty) return null;
    list.sort((a, b) => a.date.compareTo(b.date));
    return ChatThread(key, list);
  }

  Future<void> markRead(String threadKey) async {
    var changed = false;
    for (final m in messages) {
      if (m.threadKey == threadKey && !m.mine && !m.read) {
        m.read = true;
        changed = true;
      }
    }
    if (changed) {
      await _saveMessages();
      notifyListeners();
    }
  }

  /// 받은 메일을 모두 읽음 처리
  Future<void> markAllRead() async {
    var changed = false;
    for (final m in messages) {
      if (!m.mine && !m.read) {
        m.read = true;
        changed = true;
      }
    }
    if (changed) {
      await _saveMessages();
      notifyListeners();
    }
  }

  /// 받은 메일을 지우고 서버에서 처음부터 다시 받는다 (이 앱에서 보낸 메일은 유지)
  Future<void> refetchAll() async {
    messages.removeWhere((m) => !m.mine);
    seenUids.clear();
    await _saveMessages();
    await _saveSeen();
    notifyListeners();
    await syncAll();
  }

  Future<void> deleteThread(String threadKey) async {
    messages.removeWhere((m) => m.threadKey == threadKey);
    await _saveMessages();
    notifyListeners();
  }

  /// 새 메시지 추가. 이미 있으면(같은 id, 또는 내가 방금 보낸 글의 서버 사본) false.
  bool _addIfNew(ChatMessage msg) {
    if (messages.any((m) => m.id == msg.id)) return false;
    if (msg.mine) {
      final dup = messages.any((m) =>
          m.mine &&
          m.accountId == msg.accountId &&
          m.counterpart == msg.counterpart &&
          m.text.trim() == msg.text.trim() &&
          m.attachments.map((a) => a.name).join('|') ==
              msg.attachments.map((a) => a.name).join('|') &&
          m.date.difference(msg.date).abs() < const Duration(minutes: 10));
      if (dup) return false;
    }
    messages.add(msg);
    return true;
  }

  // ---------------------------------------------------------------- 동기화

  void startAutoSync([Duration every = const Duration(seconds: 60)]) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => syncAll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> syncAll() async {
    if (syncing || accounts.isEmpty) return;
    syncing = true;
    notifyListeners();
    var anyNew = false;
    for (final acc in List<Account>.of(accounts)) {
      try {
        final seen = seenUids.putIfAbsent(acc.id, () => <String>{});
        final known = messages.map((m) => m.id).toSet();
        final incoming = await MailService.fetch(acc, seen, known);
        for (final m in incoming) {
          if (_addIfNew(m)) anyNew = true;
        }
        errors.remove(acc.id);
      } catch (e) {
        errors[acc.id] = MailService.explain(e, acc);
      }
    }
    try {
      if (anyNew) await _saveMessages();
      await _saveSeen();
    } catch (_) {}
    syncing = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 전송

  /// 메시지를 로컬에 먼저 "전송 중"으로 넣고, 발송 결과로 상태를 갱신한다.
  Future<void> send({
    required Account acc,
    required String to,
    required String subject,
    required String text,
    String? inReplyTo,
    List<String> filePaths = const [],
  }) async {
    final domain = acc.email.contains('@') ? acc.email.split('@').last : 'localhost';
    final mid = '<${DateTime.now().microsecondsSinceEpoch}.${acc.id.hashCode.abs()}@$domain>';
    // 첨부파일은 앱 폴더로 복사해 둔다 (재전송·원본 이동 대비)
    final atts = <Attachment>[];
    if (filePaths.isNotEmpty) {
      final dir = await MailService.attachmentDir(mid);
      for (final p in filePaths) {
        try {
          final src = File(p);
          final name = MailService.safeFileName(p.split(RegExp(r'[\\/]')).last);
          final dst = await src.copy('${dir.path}${Platform.pathSeparator}$name');
          atts.add(Attachment(name: name, path: dst.path, size: await dst.length()));
        } catch (_) {}
      }
    }
    final msg = ChatMessage(
      id: '${acc.id}|$mid',
      accountId: acc.id,
      messageId: mid,
      subject: subject,
      counterpart: to.toLowerCase(),
      counterpartName: '',
      mine: true,
      date: DateTime.now(),
      text: text,
      status: SendStatus.sending,
      attachments: atts,
    );
    messages.add(msg);
    notifyListeners();
    await _deliver(msg, acc, inReplyTo);
  }

  Future<void> retry(ChatMessage msg) async {
    final acc = accountById(msg.accountId);
    if (acc == null) return;
    // 같은 스레드에서 이 메시지보다 앞선 상대 메일의 Message-ID
    String? reply;
    final t = threadByKey(msg.threadKey);
    if (t != null) {
      for (final m in t.messages.reversed) {
        if (!m.mine && m.messageId != null && m.date.isBefore(msg.date)) {
          reply = m.messageId;
          break;
        }
      }
    }
    msg.status = SendStatus.sending;
    notifyListeners();
    await _deliver(msg, acc, reply);
  }

  Future<void> _deliver(ChatMessage msg, Account acc, String? inReplyTo) async {
    try {
      await MailService.send(
        acc,
        to: msg.counterpart,
        subject: msg.subject,
        text: msg.text,
        messageId: msg.messageId,
        inReplyTo: inReplyTo,
        attachments: msg.attachments,
      );
      msg.status = SendStatus.sent;
    } catch (e) {
      msg.status = SendStatus.failed;
      errors[acc.id] = '전송 실패: ${MailService.explain(e, acc)}';
    }
    await _saveMessages();
    notifyListeners();
  }
}
