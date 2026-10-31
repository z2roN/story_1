import 'package:flutter/material.dart';

import 'screens/lock_screen.dart';
import 'screens/thread_list_screen.dart';
import 'store.dart';
import 'theme.dart';
import 'vault.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final vault = Vault();
  await vault.init();
  runApp(MailChatApp(vault: vault));
}

class MailChatApp extends StatelessWidget {
  const MailChatApp({super.key, required this.vault});

  final Vault vault;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '메일챗',
      debugShowCheckedModeBanner: false,
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: ThemeMode.system,
      home: AuthGate(vault: vault),
    );
  }
}

enum _Phase { loading, setup, locked, ready }

/// 암호 설정 / 잠금 해제 / 자동 로그인을 거쳐 메인 화면으로 연결
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.vault});

  final Vault vault;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  _Phase _phase = _Phase.loading;
  Store? _store;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _store?.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    if (!widget.vault.exists) {
      setState(() => _phase = _Phase.setup);
    } else if (await widget.vault.tryAutoUnlock()) {
      await _enter();
    } else if (mounted) {
      setState(() => _phase = _Phase.locked);
    }
  }

  Future<void> _enter() async {
    final store = Store(widget.vault);
    await store.load();
    store.startAutoSync();
    if (!mounted) return;
    setState(() {
      _store = store;
      _phase = _Phase.ready;
    });
    store.syncAll();
  }

  Future<void> _lock() async {
    _store?.unload();
    _store?.dispose();
    _store = null;
    await widget.vault.lock();
    if (mounted) setState(() => _phase = _Phase.locked);
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.loading:
        return const Scaffold(body: Center(child: MailChatLogo(size: 72)));
      case _Phase.setup:
        return LockScreen(
          key: const ValueKey('setup'),
          vault: widget.vault,
          setup: true,
          onUnlocked: _enter,
        );
      case _Phase.locked:
        return LockScreen(
          key: const ValueKey('locked'),
          vault: widget.vault,
          setup: false,
          onUnlocked: _enter,
          onReset: () => setState(() => _phase = _Phase.setup),
        );
      case _Phase.ready:
        return ThreadListScreen(store: _store!, onLock: _lock);
    }
  }
}
