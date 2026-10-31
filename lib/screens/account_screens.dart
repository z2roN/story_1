import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../mail_service.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

/// 메일 서비스 프리셋
class MailPreset {
  const MailPreset(this.name, this.letter, this.color, this.imap, this.pop, this.smtp,
      this.smtpPort, this.smtpSecure, this.hint);

  final String name;
  final String letter;
  final Color color;
  final String imap;
  final String pop;
  final String smtp;
  final int smtpPort;
  final bool smtpSecure;
  final String hint;
}

const kMailPresets = <MailPreset>[
  MailPreset('직접 입력', '', Color(0xFF868E96), '', '', '', 465, true, ''),
  MailPreset('Gmail', 'G', Color(0xFFE5484D), 'imap.gmail.com', 'pop.gmail.com',
      'smtp.gmail.com', 465, true,
      'Google 계정에서 2단계 인증을 켠 뒤 "앱 비밀번호"를 만들어 입력하세요.'),
  MailPreset('네이버', 'N', Color(0xFF03C75A), 'imap.naver.com', 'pop.naver.com',
      'smtp.naver.com', 465, true,
      '네이버 메일 설정 > POP3/IMAP 설정에서 "사용함"으로 바꿔야 합니다. 2단계 인증을 쓰면 애플리케이션 비밀번호를 입력하세요.'),
  MailPreset('다음/카카오', 'D', Color(0xFF3B82F6), 'imap.daum.net', 'pop.daum.net',
      'smtp.daum.net', 465, true, '다음 메일 환경설정에서 IMAP/POP3 사용을 켜야 합니다.'),
];

int _stdPort(String protocol, bool secure) =>
    protocol == 'pop3' ? (secure ? 995 : 110) : (secure ? 993 : 143);

/// 메일 계정 목록 (최대 10개)
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.store});

  final Store store;

  void _add(BuildContext context) {
    if (store.accounts.length >= kMaxAccounts) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계정은 최대 10개까지 추가할 수 있습니다')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AccountEditScreen(store: store)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          body: Column(
            children: [
              GradientHeader(
                leading: const HeaderBackButton(),
                title: Row(
                  children: [
                    const Text('메일 계정',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Text('${store.accounts.length}/$kMaxAccounts',
                        style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  ],
                ),
                actions: [
                  HeaderTextButton(
                    label: '추가',
                    icon: Icons.add,
                    onPressed: () => _add(context),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: store.accounts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('등록된 계정이 없습니다',
                                    style: TextStyle(color: cs.onSurfaceVariant)),
                                const SizedBox(height: 12),
                                GradientButton(
                                  label: '계정 추가',
                                  icon: Icons.add,
                                  expand: false,
                                  onPressed: () => _add(context),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            children: [
                              for (final a in store.accounts) _card(context, a),
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

  Widget _card(BuildContext context, Account a) {
    final cs = Theme.of(context).colorScheme;
    final color = accountColor(store, a.id);
    final err = store.errors[a.id];
    final name = a.label.isEmpty ? a.email : a.label;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AccountEditScreen(store: store, account: a)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text(
                  name.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(a.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                    if (err != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('⚠ $err',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cs.error)),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  a.protocol.toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// 계정 추가/수정
class AccountEditScreen extends StatefulWidget {
  const AccountEditScreen({
    super.key,
    required this.store,
    this.account,
    this.initialPreset = 0,
  });

  final Store store;
  final Account? account;

  /// 처음 화면에서 서비스를 골라 들어온 경우 선택해 둘 프리셋
  final int initialPreset;

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _email;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _inHost;
  late final TextEditingController _inPort;
  late final TextEditingController _smtpHost;
  late final TextEditingController _smtpPort;

  String _protocol = 'imap';
  bool _inSecure = true;
  bool _smtpSecure = true;
  bool _showPw = false;
  bool _busy = false;
  bool _showServer = true;
  int _preset = 0;

  bool get _editing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _label = TextEditingController(text: a?.label ?? '');
    _email = TextEditingController(text: a?.email ?? '');
    _username = TextEditingController(text: a?.username ?? '');
    _password = TextEditingController(text: a?.password ?? '');
    _inHost = TextEditingController(text: a?.inHost ?? '');
    _inPort = TextEditingController(text: '${a?.inPort ?? 993}');
    _smtpHost = TextEditingController(text: a?.smtpHost ?? '');
    _smtpPort = TextEditingController(text: '${a?.smtpPort ?? 465}');
    if (a != null) {
      _protocol = a.protocol;
      _inSecure = a.inSecure;
      _smtpSecure = a.smtpSecure;
    } else if (widget.initialPreset > 0 && widget.initialPreset < kMailPresets.length) {
      _applyPreset(widget.initialPreset, rebuild: false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _label,
      _email,
      _username,
      _password,
      _inHost,
      _inPort,
      _smtpHost,
      _smtpPort,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPreset(int i, {bool rebuild = true}) {
    void apply() {
      _preset = i;
      final p = kMailPresets[i];
      if (i == 0) {
        _showServer = true;
        return;
      }
      _inHost.text = _protocol == 'pop3' ? p.pop : p.imap;
      _inSecure = true;
      _inPort.text = '${_stdPort(_protocol, true)}';
      _smtpHost.text = p.smtp;
      _smtpPort.text = '${p.smtpPort}';
      _smtpSecure = p.smtpSecure;
      _showServer = false;
    }

    if (rebuild) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _setProtocol(String proto) {
    setState(() {
      _protocol = proto;
      _inPort.text = '${_stdPort(proto, _inSecure)}';
      if (_preset != 0) {
        final p = kMailPresets[_preset];
        _inHost.text = proto == 'pop3' ? p.pop : p.imap;
      }
    });
  }

  Account _build() {
    final email = _email.text.trim();
    final user = _username.text.trim();
    return Account(
      id: widget.account?.id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      label: _label.text.trim(),
      email: email,
      username: user.isEmpty ? email : user,
      password: _password.text,
      protocol: _protocol,
      inHost: _inHost.text.trim(),
      inPort: int.tryParse(_inPort.text.trim()) ?? _stdPort(_protocol, _inSecure),
      inSecure: _inSecure,
      smtpHost: _smtpHost.text.trim(),
      smtpPort: int.tryParse(_smtpPort.text.trim()) ?? (_smtpSecure ? 465 : 587),
      smtpSecure: _smtpSecure,
    );
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    String msg;
    final acc = _build();
    try {
      await MailService.testConnection(acc);
      msg = '연결 성공: 수신·발송 서버 로그인을 확인했습니다.';
    } catch (e) {
      msg = '연결 실패\n${MailService.explain(e, acc)}';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('연결 테스트'),
        content: SingleChildScrollView(child: Text(msg)),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('확인'))],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final acc = _build();
    await widget.store.saveAccount(acc);
    if (!mounted) return;
    Navigator.pop(context);
    widget.store.syncAll();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('계정 삭제'),
        content: const Text('이 계정과 이 앱에 저장된 대화가 삭제됩니다.\n(메일 서버의 메일은 지워지지 않습니다)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.deleteAccount(widget.account!.id);
    if (mounted) Navigator.pop(context);
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? '필수 항목입니다' : null;

  String? _portCheck(String? v) => int.tryParse(v?.trim() ?? '') == null ? '숫자' : null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hint = kMailPresets[_preset].hint;
    return Scaffold(
      body: Column(
        children: [
          GradientHeader(
            leading: const HeaderBackButton(),
            title: Text(
              _editing ? '계정 수정' : '메일 계정 추가',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            actions: [
              if (_editing)
                HeaderIconButton(
                  icon: Icons.delete_outline,
                  tooltip: '삭제',
                  onPressed: _delete,
                ),
            ],
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      SectionCard(
                        title: '메일 서비스',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (var i = 1; i < kMailPresets.length; i++)
                                  ProviderTile(
                                    name: kMailPresets[i].name,
                                    letter: kMailPresets[i].letter,
                                    color: kMailPresets[i].color,
                                    selected: _preset == i,
                                    onTap: () => _applyPreset(i),
                                  ),
                                ProviderTile(
                                  name: '직접 입력',
                                  letter: '',
                                  icon: Icons.tune,
                                  color: kMailPresets[0].color,
                                  selected: _preset == 0,
                                  onTap: () => _applyPreset(0),
                                ),
                              ],
                            ),
                            if (hint.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 10),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: cs.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.info_outline, size: 16, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(hint,
                                          style: TextStyle(
                                              fontSize: 12.5, color: cs.onSurface)),
                                    ),
                                  ],
                                ),
                              ),
                            if (_preset == 1) _gmailHelp(context),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Text('수신 방식',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600, fontSize: 13)),
                                const Spacer(),
                                SegmentedButton<String>(
                                  showSelectedIcon: false,
                                  style: SegmentedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    textStyle: const TextStyle(fontSize: 13),
                                  ),
                                  segments: const [
                                    ButtonSegment(value: 'imap', label: Text('IMAP')),
                                    ButtonSegment(value: 'pop3', label: Text('POP3')),
                                  ],
                                  selected: {_protocol},
                                  onSelectionChanged: (s) => _setProtocol(s.first),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SectionCard(
                        title: '로그인 정보',
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                hintText: '이메일 주소',
                                prefixIcon: Icon(Icons.alternate_email, size: 20),
                              ),
                              validator: (v) {
                                final s = v?.trim() ?? '';
                                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)
                                    ? null
                                    : '올바른 이메일 주소를 입력하세요';
                              },
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _password,
                              obscureText: !_showPw,
                              decoration: InputDecoration(
                                hintText: '비밀번호 (앱 비밀번호)',
                                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                      _showPw ? Icons.visibility_off : Icons.visibility,
                                      size: 20),
                                  onPressed: () => setState(() => _showPw = !_showPw),
                                ),
                              ),
                              validator: _required,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _label,
                              decoration: const InputDecoration(
                                hintText: '표시 이름 (선택, 예: 회사 메일)',
                                prefixIcon: Icon(Icons.label_outline, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _serverCard(context),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          SoftButton(
                            label: '연결 테스트',
                            icon: Icons.wifi_tethering,
                            onPressed: _busy ? null : _test,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GradientButton(
                              label: _editing ? '저장' : '계정 추가',
                              busy: _busy,
                              onPressed: _save,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAppPasswordPage() async {
    try {
      await launchUrl(
        Uri.parse('https://myaccount.google.com/apppasswords'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('브라우저에서 myaccount.google.com/apppasswords 를 열어 주세요')),
      );
    }
  }

  /// Gmail 연결 방법 안내 (일반 비밀번호로는 연결되지 않음)
  Widget _gmailHelp(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const steps = [
      'Google 계정 > 보안 > 2단계 인증 켜기',
      '"앱 비밀번호" 만들기 → 16자리 코드를 아래 비밀번호 칸에 입력 (공백은 자동 제거)',
      'Gmail > 설정 > 전달 및 POP/IMAP에서 IMAP 사용 켜기 (IMAP 권장)',
    ];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE5484D).withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5484D).withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Gmail 연결 방법',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('${i + 1}. ${steps[i]}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurface, height: 1.35)),
            ),
          const SizedBox(height: 6),
          SoftButton(
            label: '앱 비밀번호 만들기 열기',
            icon: Icons.open_in_new,
            onPressed: _openAppPasswordPage,
          ),
          const SizedBox(height: 4),
          Text('회사/학교(Google Workspace) 계정은 관리자가 외부 앱 접속을 막아 두면 연결되지 않을 수 있습니다.',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _serverCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canCollapse = _preset != 0;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: canCollapse ? () => setState(() => _showServer = !_showServer) : null,
            child: Row(
              children: [
                Text('서버 설정',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12.5, color: cs.primary)),
                const SizedBox(width: 8),
                if (canCollapse)
                  Text(_showServer ? '' : '자동 입력됨',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const Spacer(),
                if (canCollapse)
                  Icon(_showServer ? Icons.expand_less : Icons.expand_more,
                      color: cs.onSurfaceVariant),
              ],
            ),
          ),
          if (_showServer || !canCollapse) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(
                hintText: '로그인 ID (비우면 이메일 주소)',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),
            const SizedBox(height: 14),
            Text('수신 서버 (${_protocol.toUpperCase()})',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _inHost,
                    decoration: const InputDecoration(hintText: '서버 주소'),
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _inPort,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '포트'),
                    validator: _portCheck,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('SSL/TLS 사용'),
              value: _inSecure,
              onChanged: (v) => setState(() {
                _inSecure = v;
                _inPort.text = '${_stdPort(_protocol, v)}';
              }),
            ),
            const SizedBox(height: 6),
            const Text('발송 서버 (SMTP)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _smtpHost,
                    decoration: const InputDecoration(hintText: '서버 주소'),
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _smtpPort,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '포트'),
                    validator: _portCheck,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('SSL 사용 (끄면 STARTTLS)'),
              subtitle: const Text('465 = SSL, 587 = STARTTLS'),
              value: _smtpSecure,
              onChanged: (v) => setState(() {
                _smtpSecure = v;
                _smtpPort.text = v ? '465' : '587';
              }),
            ),
          ],
        ],
      ),
    );
  }
}
