import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'chat_screen.dart';

/// 새 대화(새 메일) 시작
class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key, required this.store});

  final Store store;

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _to = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  late String _accountId = widget.store.accounts.first.id;

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final acc = widget.store.accountById(_accountId);
    if (acc == null) return;
    final to = _to.text.trim().toLowerCase();
    final subject = _subject.text.trim();
    widget.store.send(acc: acc, to: to, subject: subject, text: _body.text.trim());
    final key = '${normalizeSubject(subject).toLowerCase()}|$to';
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(store: widget.store, threadKey: key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = widget.store.accounts;
    return Scaffold(
      body: Column(
        children: [
          GradientHeader(
            leading: const HeaderBackButton(),
            title: const Text('새 메일',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            actions: [
              HeaderTextButton(label: '보내기', icon: Icons.send, onPressed: _submit),
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
                        child: Column(
                          children: [
                            if (accounts.length > 1) ...[
                              DropdownButtonFormField<String>(
                                value: _accountId,
                                decoration: const InputDecoration(
                                  hintText: '보내는 계정',
                                  prefixIcon: Icon(Icons.account_circle_outlined, size: 20),
                                ),
                                items: [
                                  for (final a in accounts)
                                    DropdownMenuItem(
                                      value: a.id,
                                      child: Text(
                                        a.label.isEmpty ? a.email : '${a.label} (${a.email})',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _accountId = v ?? _accountId),
                              ),
                              const SizedBox(height: 10),
                            ],
                            TextFormField(
                              controller: _to,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                hintText: '받는 사람 이메일',
                                prefixIcon: Icon(Icons.person_outline, size: 20),
                              ),
                              validator: (v) {
                                final s = v?.trim() ?? '';
                                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                                  return '올바른 이메일 주소를 입력하세요';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _subject,
                              decoration: const InputDecoration(
                                hintText: '제목',
                                prefixIcon: Icon(Icons.title, size: 20),
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? '제목을 입력하세요' : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _body,
                              minLines: 6,
                              maxLines: 12,
                              decoration: const InputDecoration(hintText: '내용'),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? '내용을 입력하세요' : null,
                            ),
                          ],
                        ),
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
}
