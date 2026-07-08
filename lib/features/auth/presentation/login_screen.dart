import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../widgets/legal_agreement_rich_text.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/remote/console_auth.dart';
import '../data/auth_repository.dart';
import '../domain/auth_controller.dart';
import 'auth_gate_screen.dart';

/// Login portal — same model as the Windows client:
/// two buttons (Sign in / Register) open smartdolphinvpn.com in the browser
/// with a one-time challenge, then the app polls until the browser approves.
/// The QR option (scan from another signed-in device) is kept at its old spot.
const _siteLoginBase = 'https://smartdolphinvpn.com/login';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.startAsRegister = false});

  final bool startAsRegister;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _qrLoginMode = false;
  String? _qrChallengeId;
  String? _qrPayload;
  String? _qrStatus;
  Timer? _qrPollTimer;

  // Browser sign-in / register flow
  bool _browserWaiting = false;
  String? _browserChallengeId;
  Timer? _browserPollTimer;
  String? _error;

  @override
  void dispose() {
    _qrPollTimer?.cancel();
    _browserPollTimer?.cancel();
    super.dispose();
  }

  // --- browser sign-in / register -----------------------------------------

  Future<void> _startBrowser(String action) async {
    if (_browserWaiting) return;
    setState(() {
      _browserWaiting = true;
      _error = null;
    });
    final repo = ref.read(authRepositoryProvider);
    try {
      final device = await repo.deviceId();
      final data = await repo.createQrLoginChallenge();
      final id = data['challenge_id'] as String?;
      if (id == null || id.isEmpty) {
        throw ConsoleAuthException('challenge_failed', 'Failed to create login request');
      }
      _browserChallengeId = id;
      final url = Uri.parse(
        '$_siteLoginBase?challenge=${Uri.encodeComponent(id)}'
        '&client=android&action=$action&device_id=${Uri.encodeComponent(device)}',
      );
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) throw ConsoleAuthException('browser_failed', 'Could not open the browser');
      _startBrowserPolling();
    } on ConsoleAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _browserWaiting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _browserWaiting = false;
        _error = '$e';
      });
    }
  }

  void _startBrowserPolling() {
    _browserPollTimer?.cancel();
    _browserPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final id = _browserChallengeId;
      if (id == null || !mounted || !_browserWaiting) return;
      try {
        final repo = ref.read(authRepositoryProvider);
        final data = await repo.pollQrLoginChallenge(id);
        if (data['status'] == 'pending') return;
        await ref.read(authControllerProvider.notifier).completeQrLogin(data);
        if (!mounted) return;
        final auth = ref.read(authControllerProvider);
        if (auth.status == AuthStatus.authenticated ||
            auth.status == AuthStatus.pending ||
            auth.status == AuthStatus.banned) {
          _browserPollTimer?.cancel();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const AuthGateScreen()),
            (_) => false,
          );
        }
      } on ConsoleAuthException catch (e) {
        if (e.code != 'qr_pending' && mounted) setState(() => _error = e.message);
      } catch (_) {}
    });
  }

  void _cancelBrowser() {
    _browserPollTimer?.cancel();
    setState(() {
      _browserWaiting = false;
      _browserChallengeId = null;
    });
  }

  // --- QR sign-in (scan from another signed-in device) --------------------

  Future<void> _toggleQrLoginMode() async {
    if (_qrLoginMode) {
      _qrPollTimer?.cancel();
      setState(() {
        _qrLoginMode = false;
        _qrChallengeId = null;
        _qrPayload = null;
        _qrStatus = null;
      });
      return;
    }
    setState(() {
      _qrLoginMode = true;
      _qrStatus = null;
    });
    await _refreshQrChallenge();
  }

  Future<void> _refreshQrChallenge() async {
    final l10n = AppLocalizations.of(context);
    try {
      final repo = ref.read(authRepositoryProvider);
      final data = await repo.createQrLoginChallenge();
      final qr = data['qr'] as Map<String, dynamic>? ?? {};
      final payload = jsonEncode(qr);
      if (!mounted) return;
      setState(() {
        _qrChallengeId = data['challenge_id'] as String?;
        _qrPayload = payload;
        _qrStatus = l10n.authQrWaiting;
      });
      _startQrPolling();
    } on ConsoleAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _qrPayload = null;
        _qrStatus = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qrPayload = null;
        _qrStatus = '$e';
      });
    }
  }

  void _startQrPolling() {
    _qrPollTimer?.cancel();
    _qrPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final id = _qrChallengeId;
      if (id == null || !mounted || !_qrLoginMode) return;
      try {
        final repo = ref.read(authRepositoryProvider);
        final data = await repo.pollQrLoginChallenge(id);
        if (data['status'] == 'pending') return;
        await ref.read(authControllerProvider.notifier).completeQrLogin(data);
        if (!mounted) return;
        final auth = ref.read(authControllerProvider);
        if (auth.status == AuthStatus.authenticated ||
            auth.status == AuthStatus.pending ||
            auth.status == AuthStatus.banned) {
          _qrPollTimer?.cancel();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const AuthGateScreen()),
            (_) => false,
          );
        }
      } on ConsoleAuthException catch (e) {
        if (e.code != 'qr_pending' && mounted) setState(() => _qrStatus = e.message);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
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
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.authLoginSubtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (_qrLoginMode) ...[
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: theme.colorScheme.outlineVariant),
                            ),
                            child: _qrPayload == null
                                ? const SizedBox(
                                    width: 220,
                                    height: 220,
                                    child: Center(child: CircularProgressIndicator()),
                                  )
                                : QrImageView(
                                    data: _qrPayload!,
                                    version: QrVersions.auto,
                                    size: 220,
                                    backgroundColor: Colors.white,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _qrStatus ?? l10n.authQrWaiting,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(onPressed: _refreshQrChallenge, child: Text(l10n.authQrRefresh)),
                      ] else if (_browserWaiting) ...[
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: 16),
                        Text(
                          l10n.authQrWaiting,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _cancelBrowser, child: Text(l10n.cancel)),
                      ] else ...[
                        FilledButton(
                          onPressed: () => _startBrowser('login'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(l10n.authSignIn),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => _startBrowser('register'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(l10n.authSignUp),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: LegalAgreementRichText(hintTemplate: l10n.authLegalAgreementHint),
                      ),
                    ],
                  ),
                  // QR toggle kept at its original position (top-right).
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: _qrLoginMode ? l10n.authQrUsePassword : l10n.authQrUseScan,
                      iconSize: 22,
                      visualDensity: VisualDensity.compact,
                      onPressed: _browserWaiting ? null : _toggleQrLoginMode,
                      icon: Icon(_qrLoginMode ? Icons.keyboard_outlined : Icons.qr_code_2),
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
