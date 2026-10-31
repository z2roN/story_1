import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../text_utils.dart' show blockRemoteImages, hasRemoteImages;
import 'thread_list_screen.dart' show formatClock;

bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

const int _maxTotalBytes = 20 * 1024 * 1024;
const _imageExt = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];

bool _isImage(String name) {
  final i = name.lastIndexOf('.');
  return i >= 0 && _imageExt.contains(name.substring(i + 1).toLowerCase());
}

/// 메일 한 건(제목)을 메신저 대화방처럼 보여주는 화면
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.store, required this.threadKey});

  final Store store;
  final String threadKey;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final List<PlatformFile> _files = [];

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.markRead(widget.threadKey);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickFiles() async {
    try {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (res == null) return;
      final next = [..._files];
      for (final f in res.files) {
        if (f.path != null) next.add(f);
      }
      final total = next.fold<int>(0, (n, f) => n + f.size);
      if (total > _maxTotalBytes) {
        _toast('첨부파일은 합계 20MB까지 보낼 수 있습니다 (메일 서버 제한)');
        return;
      }
      setState(() {
        _files
          ..clear()
          ..addAll(next);
      });
    } catch (e) {
      _toast('파일을 선택할 수 없습니다: $e');
    }
  }

  void _send(ChatThread thread) {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _files.isEmpty) return;
    final acc = store.accountById(thread.last.accountId);
    if (acc == null) {
      _toast('이 대화의 메일 계정이 삭제되어 보낼 수 없습니다');
      return;
    }
    String? replyTo;
    for (final m in thread.messages.reversed) {
      if (!m.mine && m.messageId != null) {
        replyTo = m.messageId;
        break;
      }
    }
    final title = normalizeSubject(thread.last.subject);
    final subject = title.isEmpty ? '' : 'Re: $title';
    final paths = _files.map((f) => f.path!).toList();
    _ctrl.clear();
    setState(_files.clear);
    store.send(
      acc: acc,
      to: thread.last.counterpart,
      subject: subject,
      text: text,
      inReplyTo: replyTo,
      filePaths: paths,
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final thread = store.threadByKey(widget.threadKey);
        if (thread == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('대화를 찾을 수 없습니다')),
          );
        }
        if (thread.unread > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) store.markRead(widget.threadKey);
          });
        }
        final msgs = thread.messages.reversed.toList(); // reverse 리스트용
        return Scaffold(
          body: Column(
            children: [
              GradientHeader(
                leading: const HeaderBackButton(),
                title: Row(
                  children: [
                    Avatar(name: thread.counterpartLabel, size: 36, ring: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            thread.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${thread.counterpartLabel} · ${thread.last.counterpart}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                      children: [
                  Expanded(
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs[i];
                        final older = i + 1 < msgs.length ? msgs[i + 1] : null;
                        final newer = i > 0 ? msgs[i - 1] : null;
                        final newDay = older == null || !_sameDay(older.date, m.date);
                        final groupStart = older == null || newDay || older.mine != m.mine;
                        final groupEnd = newer == null ||
                            newer.mine != m.mine ||
                            !_sameMinute(newer.date, m.date);
                        return Column(
                          children: [
                            if (newDay) _DatePill(m.date),
                            _Message(
                              msg: m,
                              name: thread.counterpartLabel,
                              groupStart: groupStart,
                              showTime: groupEnd,
                              onRetry: () => store.retry(m),
                              onToast: _toast,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  _composer(thread),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _sameMinute(DateTime a, DateTime b) =>
      _sameDay(a, b) && a.hour == b.hour && a.minute == b.minute;

  Widget _composer(ChatThread thread) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF181B22) : Colors.white,
        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.5))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final f in _files)
                      InputChip(
                        avatar: const Icon(Icons.attach_file, size: 16),
                        label: Text('${f.name} (${formatSize(f.size)})',
                            style: const TextStyle(fontSize: 12)),
                        onDeleted: () => setState(() => _files.remove(f)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _RoundTint(
                  icon: Icons.add,
                  tooltip: '파일 첨부',
                  onPressed: _pickFiles,
                ),
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (_isDesktop &&
                          event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.isShiftPressed) {
                        // 한글 조합 중에는 전송하지 않음
                        final composing = _ctrl.value.composing;
                        if (composing.isValid && !composing.isCollapsed) {
                          return KeyEventResult.ignored;
                        }
                        _send(thread);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: _isDesktop ? '메시지 입력 (Enter 전송 · Shift+Enter 줄바꿈)' : '메시지 입력',
                        fillColor: dark ? const Color(0xFF242833) : const Color(0xFFF1F2F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SendButton(
                  enabled: _ctrl.text.trim().isNotEmpty || _files.isNotEmpty,
                  onPressed: () => _send(thread),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill(this.date);

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const wd = ['월', '화', '수', '목', '금', '토', '일'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: cs.onSurface.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${DateFormat('yyyy년 M월 d일').format(date)} ${wd[date.weekday - 1]}요일',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.msg,
    required this.name,
    required this.groupStart,
    required this.showTime,
    required this.onRetry,
    required this.onToast,
  });

  final ChatMessage msg;
  final String name;
  final bool groupStart;
  final bool showTime;
  final VoidCallback onRetry;
  final void Function(String) onToast;

  Future<void> _openLink(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !['http', 'https', 'mailto'].contains(uri.scheme)) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      onToast('링크를 열 수 없습니다');
    }
  }

  Future<void> _open(Attachment a) async {
    if (!File(a.path).existsSync()) {
      onToast('파일을 찾을 수 없습니다: ${a.name}');
      return;
    }
    final r = await OpenFilex.open(a.path);
    if (r.type != ResultType.done) {
      onToast('파일을 열 수 없습니다 (${r.message})');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mine = msg.mine;
    final bubbleColor =
        mine ? kBrand : (dark ? const Color(0xFF242833) : Colors.white);
    final fg = mine ? Colors.white : cs.onSurface;
    final isHtml = !mine && msg.html != null;
    final screenW = MediaQuery.of(context).size.width;
    final maxW = isHtml
        ? (screenW * 0.86).clamp(240.0, 700.0)
        : (screenW * 0.72).clamp(200.0, 560.0);

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isHtml)
            _HtmlCard(html: msg.html!, onLink: _openLink)
          else if (msg.text.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: mine ? null : bubbleColor,
                gradient: mine ? kBrandGradient : null,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine || !showTime ? 18 : 5),
                  bottomRight: Radius.circular(mine && showTime ? 5 : 18),
                ),
                boxShadow: mine
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(dark ? 0 : 0.05),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              child: SelectableText(
                msg.text,
                style: TextStyle(color: fg, fontSize: 14.5, height: 1.35),
              ),
            ),
          for (final a in msg.attachments)
            Padding(
              padding: EdgeInsets.only(top: (msg.text.isNotEmpty || isHtml) ? 4 : 0),
              child: _attachment(context, a, bubbleColor, fg),
            ),
        ],
      ),
    );

    final timeText = Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
      child: Text(
        msg.mine && msg.status == SendStatus.sending ? '전송 중' : formatClock(msg.date),
        style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
      ),
    );

    final avatarSlot = SizedBox(
      width: 36,
      child: groupStart ? Avatar(name: name, size: 30) : null,
    );

    return Padding(
      padding: EdgeInsets.only(top: groupStart ? 8 : 2),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!mine && groupStart)
            Padding(
              padding: const EdgeInsets.only(left: 36, bottom: 3),
              child: Text(name, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          Row(
            mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine) avatarSlot,
              if (mine && showTime) timeText,
              Flexible(child: bubble),
              if (!mine && showTime) timeText,
            ],
          ),
          if (mine && msg.status == SendStatus.failed)
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 4),
              child: InkWell(
                onTap: onRetry,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error, size: 14, color: cs.error),
                    const SizedBox(width: 4),
                    Text('전송 실패 · 눌러서 다시 보내기',
                        style: TextStyle(fontSize: 12, color: cs.error)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _attachment(BuildContext context, Attachment a, Color bubbleColor, Color fg) {
    if (_isImage(a.name) && File(a.path).existsSync()) {
      return GestureDetector(
        onTap: () => _open(a),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            File(a.path),
            width: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fileCard(a, bubbleColor, fg),
          ),
        ),
      );
    }
    return GestureDetector(onTap: () => _open(a), child: _fileCard(a, bubbleColor, fg));
  }

  Widget _fileCard(Attachment a, Color bubbleColor, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, color: fg, size: 26),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
                Text(
                  formatSize(a.size),
                  style: TextStyle(color: fg.withOpacity(0.7), fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 작은 둥근 보조 버튼 (연한 색)
class _RoundTint extends StatelessWidget {
  const _RoundTint({required this.icon, required this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: kBrand.withOpacity(0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.add, size: 20, color: kBrand),
          ),
        ),
      ),
    );
  }
}

/// 보내기 버튼 (36px 그라데이션 원)
class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '보내기',
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: enabled ? kBrandGradient : null,
          color: enabled ? null : Colors.grey.withOpacity(0.35),
          shape: BoxShape.circle,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onPressed : null,
            child: const Icon(Icons.arrow_upward, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// HTML 메일: 흰 배경 카드 안에 HTML로 표시. 원격 이미지는 기본 차단(추적 방지), 눌러서 보기
class _HtmlCard extends StatefulWidget {
  const _HtmlCard({required this.html, required this.onLink});

  final String html;
  final Future<void> Function(String?) onLink;

  @override
  State<_HtmlCard> createState() => _HtmlCardState();
}

class _HtmlCardState extends State<_HtmlCard> {
  bool _showImages = false;

  @override
  Widget build(BuildContext context) {
    final remote = hasRemoteImages(widget.html);
    final data = (_showImages || !remote) ? widget.html : blockRemoteImages(widget.html);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRect(
            child: HtmlWidget(
              data,
              textStyle: const TextStyle(fontSize: 14, color: Colors.black87),
              customStylesBuilder: (element) =>
                  element.localName == 'a' ? {'color': '#4B55E0'} : null,
              onTapUrl: (url) async {
                await widget.onLink(url);
                return true;
              },
            ),
          ),
          if (remote && !_showImages)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InkWell(
                onTap: () => setState(() => _showImages = true),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, size: 15, color: kBrand),
                    SizedBox(width: 5),
                    Text(
                      '원격 이미지가 차단되었습니다 · 눌러서 보기',
                      style: TextStyle(fontSize: 12, color: kBrand),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
