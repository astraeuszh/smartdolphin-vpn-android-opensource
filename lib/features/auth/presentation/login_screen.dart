import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/legal_agreement_rich_text.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/remote/console_auth.dart';
import '../data/auth_repository.dart';
import '../domain/auth_controller.dart';
import 'auth_gate_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.startAsRegister = false});

  /// 从设置页「注册」进入时为 true。
  final bool startAsRegister;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  late bool _isRegister;
  bool _obscure = true;
  bool _obscure2 = true;
  int _codeCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _isRegister = widget.startAsRegister;
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _codeCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_codeCooldown <= 1) {
        t.cancel();
        setState(() => _codeCooldown = 0);
      } else {
        setState(() => _codeCooldown -= 1);
      }
    });
  }

  Future<void> _sendCode() async {
    final l10n = AppLocalizations.of(context);
    final email = _emailCtrl.text.trim();
    if (!_looksLikeEmail(email)) {
      _toast(l10n.authEnterValidEmail);
      return;
    }
    final repo = ref.read(authRepositoryProvider);
    try {
      await repo.sendRegisterCode(email);
      _startCooldown();
      if (mounted) {
        _toast(l10n.authCodeSent);
      }
    } on ConsoleAuthException catch (e) {
      _toast(_mapAuthError(e, l10n));
    } catch (e) {
      _toast(e.toString());
    }
  }

  String _mapAuthError(ConsoleAuthException e, AppLocalizations l10n) {
    switch (e.code) {
      case 'invalid_email':
        return l10n.authErrorInvalidEmail;
      case 'email_unreachable':
        return l10n.authErrorEmailUnreachable;
      case 'code_cooldown':
        return l10n.authErrorCodeCooldown(_codeCooldown > 0 ? _codeCooldown : 60);
      case 'email_taken':
        return l10n.authErrorEmailTaken;
      case 'username_taken':
        return l10n.authErrorUsernameTaken;
      case 'illegal_char':
        return l10n.authErrorIllegalChar;
      case 'invalid_verification_code':
        return l10n.authErrorInvalidVerificationCode;
      default:
        return e.message;
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _looksLikeEmail(String email) {
    final re = RegExp(
      r'^[a-zA-Z0-9](?:[a-zA-Z0-9._%+-]*[a-zA-Z0-9])?@[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)+$',
    );
    return re.hasMatch(email.trim());
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final ctrl = ref.read(authControllerProvider.notifier);
    if (_isRegister) {
      final name = _nameCtrl.text.trim();
      final email = _emailCtrl.text.trim().toLowerCase();
      final pass = _passCtrl.text;
      final pass2 = _pass2Ctrl.text;
      final code = _codeCtrl.text.trim();
      if (name.isEmpty) {
        _toast(l10n.authEnterName);
        return;
      }
      if (!_looksLikeEmail(email)) {
        _toast(l10n.authEnterEmail);
        return;
      }
      if (pass.length < 8) {
        _toast(l10n.authPasswordRule);
        return;
      }
      if (pass != pass2) {
        _toast(l10n.authPasswordMismatch);
        return;
      }
      if (code.length != 6 || int.tryParse(code) == null) {
        _toast(l10n.authEnterVerificationCode);
        return;
      }
      await ctrl.register(
        displayName: name,
        email: email,
        password: pass,
        verificationCode: code,
      );
    } else {
      final user = _userCtrl.text.trim();
      final pass = _passCtrl.text;
      if (user.isEmpty || pass.isEmpty) {
        _toast(l10n.authEnterCredentials);
        return;
      }
      await ctrl.login(user, pass);
    }
    if (!mounted) return;
    final auth = ref.read(authControllerProvider);
    if (auth.status == AuthStatus.authenticated ||
        auth.status == AuthStatus.pending ||
        auth.status == AuthStatus.banned) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthGateScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final busy = auth.status == AuthStatus.loading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/icons/appicon.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.shield_outlined,
                          size: 72,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Smart Dolphin VPN',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isRegister ? l10n.authRegisterSubtitle : l10n.authLoginSubtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_isRegister) ...[
                    TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.authFieldName,
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.authFieldEmail,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                  ] else
                    TextField(
                      controller: _userCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.authFieldUsername,
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  if (!_isRegister) const SizedBox(height: 16),
                  TextField(
                    controller: _passCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.authFieldPassword,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    obscureText: _obscure,
                    textInputAction:
                        _isRegister ? TextInputAction.next : TextInputAction.done,
                    onSubmitted: (_) => busy ? null : _submit(),
                  ),
                  if (_isRegister) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pass2Ctrl,
                      decoration: InputDecoration(
                        labelText: l10n.authFieldConfirmPassword,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure2 ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _obscure2 = !_obscure2),
                        ),
                      ),
                      obscureText: _obscure2,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeCtrl,
                            decoration: InputDecoration(
                              labelText: l10n.authFieldVerificationCode,
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => busy ? null : _submit(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 56,
                          child: OutlinedButton(
                            onPressed: busy || _codeCooldown > 0 ? null : _sendCode,
                            child: Text(
                              _codeCooldown > 0 ? '${_codeCooldown}s' : l10n.authGetCode,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (auth.message != null && auth.status == AuthStatus.error)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        auth.code != null
                            ? _mapAuthError(ConsoleAuthException(
                                auth.code!, auth.message!), l10n)
                            : auth.message!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isRegister ? l10n.authSignUp : l10n.authSignIn),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => _isRegister = !_isRegister),
                    child: Text(
                      _isRegister ? l10n.authHaveAccount : l10n.authNoAccount,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: LegalAgreementRichText(
                      hintTemplate: l10n.authLegalAgreementHint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
