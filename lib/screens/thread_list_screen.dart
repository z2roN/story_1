import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../version.dart';
import '../widgets.dart';
import 'account_screens.dart';
import 'chat_screen.dart';
import 'new_message_screen.dart';

/// 오전/오후 h:mm (로케일 데이터 초기화 없이 사용)
String formatClock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${d.hour < 12 ? '오전' : '오후'} $h:$m';
}

String formatListTime(DateTime d) {
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return formatClock(d);
  }
  if (d.year == now.year) return DateFormat('M월 d일').format(d);
  return DateFormat('yy.M.d').format(d);
}

String _preview(ChatMessage m) {
  if (m.text.trim().isNotEmpty) return m.text.replaceAll('\n', ' ');
  if (m.attachments.isNotEmpty) return '📎 ${m.attachments.first.name}';
  return '';
}

enum _View { byAccount, all }

/// 메일 제목 목록 (메인 화면). 계정별 / 전체 보기
class ThreadListScreen extends StatefulWidget {
  const ThreadListScreen({super.key, required this.store, required this.onLock});

  final Store store;
  final Future<void> Function() onLock;

  @override
  State<ThreadListScreen> createState() => _ThreadListScreenState();
}

class _ThreadListScreenState extends State<ThreadListScreen> with WidgetsBindingObserver {
  Store get store => widget.store;
  _View _view = _View.byAccount;
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) store.syncAll();
  }

  Future<void> _confirmDelete(ChatThread t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('대화 삭제'),
        content: Text('"${t.title}" 대화를 이 앱에서 삭제할까요?\n(메일 서버의 메일은 지워지지 않습니다)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) await store.deleteThread(t.key);
  }

  void _showError(Account acc) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('동기화 오류'),
        content: SingleChildScrollView(child: Text(store.errors[acc.id] ?? '')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('닫기'))],
      ),
    );
  }

  Future<void> _confirmRefetch() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('메일 다시 받기'),
        content: const Text(
          '받은 메일을 앱에서 지우고 서버에서 처음부터 다시 받아옵니다.\n'
          '(이전에 받은 메일도 HTML 형태로 다시 표시됩니다. 서버의 메일은 지워지지 않으며, 다시 받은 메일은 모두 읽음으로 표시됩니다.)',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('다시 받기')),
        ],
      ),
    );
    if (ok == true) store.refetchAll();
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(
          children: [
            const MailChatLogo(size: 32),
            const SizedBox(width: 10),
            Text('메일챗 v$kAppVersion'),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('업데이트 내역', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final r in kChangelog) ...[
                  Text('v${r.version}  ·  ${r.date}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  for (final n in r.notes)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Text('• $n', style: const TextStyle(fontSize: 12.5)),
                    ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('닫기'))],
      ),
    );
  }

  void _openAccounts() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AccountsScreen(store: store)),
      );

  void _openNew() {
    if (store.accounts.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AccountEditScreen(store: store)),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewMessageScreen(store: store)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final q = _search.text.trim().toLowerCase();
        var threads = store.threads;
        if (q.isNotEmpty) {
          threads = threads
              .where((t) =>
                  t.title.toLowerCase().contains(q) ||
                  t.counterpartLabel.toLowerCase().contains(q) ||
                  t.last.counterpart.contains(q) ||
                  t.messages.any((m) => m.text.toLowerCase().contains(q)))
              .toList();
        }
        return Scaffold(
          floatingActionButton: _fab(),
          body: Column(
            children: [
              _header(context),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _body(context, threads, q.isNotEmpty),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _fab() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: kBrandGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: kBrand.withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _openNew,
          child: const Tooltip(
            message: '새 메일',
            child: Icon(Icons.edit_outlined, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final unread = store.threads.fold<int>(0, (n, t) => n + t.unread);
    if (_searching) {
      return GradientHeader(
        title: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 20, color: Colors.black54),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: '제목, 보낸 사람, 내용 검색',
                    hintStyle: TextStyle(color: Colors.black45, fontSize: 14),
                    border: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          HeaderTextButton(
            label: '닫기',
            onPressed: () => setState(() {
              _searching = false;
              _search.clear();
            }),
          ),
        ],
      );
    }
    return GradientHeader(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const MailChatLogo(size: 28),
          ),
          const SizedBox(width: 10),
          const Text(
            '메일챗',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 6),
          const Text(
            'v$kAppVersion',
            style: TextStyle(fontSize: 11, color: Colors.white70),
          ),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$unread',
                style: const TextStyle(
                  color: kBrand,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        HeaderIconButton(
          icon: Icons.search,
          tooltip: '검색',
          onPressed: () => setState(() => _searching = true),
        ),
        store.syncing
            ? const SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                ),
              )
            : HeaderIconButton(
                icon: Icons.refresh,
                tooltip: '새로고침',
                onPressed: store.syncAll,
              ),
        PopupMenuButton<String>(
          tooltip: '메뉴',
          offset: const Offset(0, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (v) {
            switch (v) {
              case 'new':
                _openNew();
              case 'accounts':
                _openAccounts();
              case 'readall':
                store.markAllRead();
              case 'refetch':
                _confirmRefetch();
              case 'about':
                _showAbout();
              case 'lock':
                widget.onLock();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'new', child: Text('새 메일 쓰기')),
            PopupMenuItem(value: 'readall', child: Text('모두 읽음 처리')),
            PopupMenuItem(value: 'accounts', child: Text('메일 계정 관리')),
            PopupMenuItem(value: 'refetch', child: Text('메일 다시 받기')),
            PopupMenuItem(value: 'about', child: Text('버전 정보 (v$kAppVersion)')),
            PopupMenuItem(value: 'lock', child: Text('잠금 (로그아웃)')),
          ],
          child: const HeaderIconButton(icon: Icons.more_vert),
        ),
      ],
      bottom: store.accounts.isEmpty || _searching ? null : _viewToggle(),
    );
  }

  Widget _viewToggle() {
    Widget pill(String label, _View v) {
      final on = _view == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _view = v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: on ? kBrand : Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          pill('계정별', _View.byAccount),
          pill('전체 (최신순)', _View.all),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, List<ChatThread> threads, bool searching) {
    final cs = Theme.of(context).colorScheme;
    if (store.accounts.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(
              color: cardColor(context),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MailChatLogo(size: 64),
                const SizedBox(height: 14),
                const Text(
                  '메일 계정을 연결해 보세요',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  '받은 메일이 대화처럼 보이고,\n입력하면 바로 답장이 전송됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 1; i < kMailPresets.length; i++)
                      ProviderTile(
                        name: kMailPresets[i].name,
                        letter: kMailPresets[i].letter,
                        color: kMailPresets[i].color,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AccountEditScreen(store: store, initialPreset: i),
                          ),
                        ),
                      ),
                    ProviderTile(
                      name: '직접 입력',
                      letter: '',
                      icon: Icons.tune,
                      color: kMailPresets[0].color,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AccountEditScreen(store: store),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '사용하는 메일 서비스를 선택하세요',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final children = <Widget>[];
    if (_view == _View.all) {
      if (threads.isEmpty) children.add(_empty(searching));
      for (final t in threads) {
        children.add(_row(context, t, showAccount: true));
      }
    } else {
      for (final acc in store.accounts) {
        final list = threads.where((t) => t.last.accountId == acc.id).toList();
        if (searching && list.isEmpty) continue;
        children.add(_sectionHeader(context, acc, list));
        if (list.isEmpty) {
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text('대화 없음', style: TextStyle(color: cs.onSurfaceVariant)),
          ));
        }
        for (final t in list) {
          children.add(_row(context, t));
        }
      }
      if (searching && children.isEmpty) children.add(_empty(true));
    }
    children.add(const SizedBox(height: 80));

    return RefreshIndicator(
      onRefresh: store.syncAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: children,
      ),
    );
  }

  Widget _empty(bool searching) => Padding(
        padding: const EdgeInsets.all(48),
        child: Center(child: Text(searching ? '검색 결과가 없습니다' : '아직 메일이 없습니다')),
      );

  Widget _sectionHeader(BuildContext context, Account acc, List<ChatThread> list) {
    final cs = Theme.of(context).colorScheme;
    final color = accountColor(store, acc.id);
    final unread = list.fold<int>(0, (n, t) => n + t.unread);
    final hasError = store.errors.containsKey(acc.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              acc.label.isEmpty ? acc.email : acc.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
          ),
          if (acc.label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                acc.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
          const SizedBox(width: 6),
          // 읽지 않은 메일이 있을 때만 신규 표시 (모두 읽었으면 아무것도 표시하지 않음)
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                'N $unread',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: cs.onPrimary,
                ),
              ),
            ),
          const Spacer(),
          if (hasError)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '동기화 오류',
              icon: Icon(Icons.error_outline, size: 20, color: cs.error),
              onPressed: () => _showError(acc),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ChatThread t, {bool showAccount = false}) {
    final cs = Theme.of(context).colorScheme;
    final unread = t.unread;
    final last = t.last;
    final acc = store.accountById(last.accountId);
    return InkWell(
      onTap: () {
        // 열자마자 읽음 처리해서 목록의 신규 표시를 바로 지운다
        store.markRead(t.key);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatScreen(store: store, threadKey: t.key)),
        );
      },
      onLongPress: () => _confirmDelete(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Avatar(name: t.counterpartLabel),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (showAccount && acc != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: accountColor(store, acc.id),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatListTime(last.date),
                        style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${t.counterpartLabel} · ${last.mine ? '나: ' : ''}${_preview(last)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                      ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 20),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unread',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: cs.onPrimary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
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
