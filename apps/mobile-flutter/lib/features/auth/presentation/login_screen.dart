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

class _LoginScreenState extends ConsumerState<LoginScreen>
    with WidgetsBindingObserver {
  bool _qrLoginMode = false;
  String? _qrChallengeId;
  String? _qrPayload;
  String? _qrStatus;
  Timer? _qrPollTimer;

  // Browser sign-in / register flow
  bool _browserWaiting = false;
  String? _browserChallengeId;
  Timer? _browserPollTimer;
  bool _browserPollInFlight = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreBrowserChallenge());
  }

  Future<void> _restoreBrowserChallenge() async {
    final id =
        await ref.read(authRepositoryProvider).loadBrowserLoginChallenge();
    if (!mounted || id == null || id.trim().isEmpty) return;
    setState(() {
      _browserChallengeId = id;
      _browserWaiting = true;
      _error = null;
    });
    _startBrowserPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _qrPollTimer?.cancel();
    _browserPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Timers are suspended while Chrome is in the foreground. Always query the
    // challenge immediately when the user returns, rather than waiting for the
    // next periodic tick that may never run on an aggressively managed device.
    if (state == AppLifecycleState.resumed && _browserWaiting) {
      unawaited(_pollBrowserChallenge());
    }
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
        throw ConsoleAuthException(
            'challenge_failed', 'Failed to create login request');
      }
      _browserChallengeId = id;
      await repo.saveBrowserLoginChallenge(id);
      final url = Uri.parse(
        '$_siteLoginBase?challenge=${Uri.encodeComponent(id)}'
        '&client=android&action=$action&device_id=${Uri.encodeComponent(device)}',
      );
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw ConsoleAuthException(
            'browser_failed', 'Could not open the browser');
      }
      if (!mounted) return;
      _startBrowserPolling();
    } on ConsoleAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _browserWaiting = false;
        _error = e.message;
      });
      await repo.clearBrowserLoginChallenge();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _browserWaiting = false;
        _error = '$e';
      });
      await repo.clearBrowserLoginChallenge();
    }
  }

  void _startBrowserPolling() {
    _browserPollTimer?.cancel();
    unawaited(_pollBrowserChallenge());
    _browserPollTimer = Timer.periodic(
        const Duration(seconds: 2), (_) => unawaited(_pollBrowserChallenge()));
  }

  Future<void> _pollBrowserChallenge() async {
    if (_browserPollInFlight || !mounted || !_browserWaiting) return;
    final id = _browserChallengeId;
    if (id == null) return;
    _browserPollInFlight = true;
    try {
      final data =
          await ref.read(authRepositoryProvider).pollQrLoginChallenge(id);
      if (data['status'] == 'pending') return;
      await ref.read(authControllerProvider.notifier).completeQrLogin(data);
      if (!mounted) return;
      final auth = ref.read(authControllerProvider);
      if (auth.status == AuthStatus.authenticated ||
          auth.status == AuthStatus.pending ||
          auth.status == AuthStatus.banned ||
          auth.status == AuthStatus.expired) {
        _browserPollTimer?.cancel();
        await ref.read(authRepositoryProvider).clearBrowserLoginChallenge();
        if (!mounted) return;
        setState(() => _browserWaiting = false);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const AuthGateScreen()),
          (_) => false,
        );
      } else if (auth.status == AuthStatus.error) {
        setState(() {
          _browserWaiting = false;
          _error = auth.message ?? 'Unable to complete sign-in.';
        });
      }
    } on ConsoleAuthException catch (e) {
      if (!mounted || e.code == 'qr_pending') return;
      _browserPollTimer?.cancel();
      await ref.read(authRepositoryProvider).clearBrowserLoginChallenge();
      setState(() {
        _browserWaiting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      _browserPollTimer?.cancel();
      await ref.read(authRepositoryProvider).clearBrowserLoginChallenge();
      setState(() {
        _browserWaiting = false;
        _error = 'Unable to verify browser approval: $e';
      });
    } finally {
      _browserPollInFlight = false;
    }
  }

  void _cancelBrowser() {
    _browserPollTimer?.cancel();
    unawaited(ref.read(authRepositoryProvider).clearBrowserLoginChallenge());
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
        if (e.code != 'qr_pending' && mounted) {
          setState(() => _qrStatus = e.message);
        }
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
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
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
                              border: Border.all(
                                  color: theme.colorScheme.outlineVariant),
                            ),
                            child: _qrPayload == null
                                ? const SizedBox(
                                    width: 220,
                                    height: 220,
                                    child: Center(
                                        child: CircularProgressIndicator()),
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
                        TextButton(
                            onPressed: _refreshQrChallenge,
                            child: Text(l10n.authQrRefresh)),
                      ] else if (_browserWaiting) ...[
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: 16),
                        Text(
                          'Waiting for browser approval. The app will open automatically after approval. If it does not, return to this screen and sign-in will continue.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                            onPressed: _cancelBrowser,
                            child: Text(l10n.cancel)),
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
                        child: LegalAgreementRichText(
                          hintTemplate: l10n.authLegalAgreementHint,
                        ),
                      ),
                    ],
                  ),
                  // QR toggle kept at its original position (top-right).
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: _qrLoginMode
                          ? l10n.authQrUsePassword
                          : l10n.authQrUseScan,
                      iconSize: 22,
                      visualDensity: VisualDensity.compact,
                      onPressed: _browserWaiting ? null : _toggleQrLoginMode,
                      icon: Icon(_qrLoginMode
                          ? Icons.keyboard_outlined
                          : Icons.qr_code_2),
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
