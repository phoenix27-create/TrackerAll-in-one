import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import 'auth_widgets.dart';

/// Shown after register / email login until the user taps the verification
/// link Firebase emailed them. Checks automatically every few seconds and
/// whenever the app comes back to the foreground.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});
  final String email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  bool _checking = false;
  int _cooldown = 60;
  Timer? _cooldownTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCooldown();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _check(silent: true),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // User usually leaves to the mail app and comes back.
    if (state == AppLifecycleState.resumed) _check(silent: true);
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    if (!silent) setState(() => _checking = true);
    _checking = true;
    try {
      final ok = await AuthService.instance.checkEmailVerified();
      // On success AuthGate rebuilds into the home screen.
      if (!ok && !silent && mounted) {
        showError(
          context,
          'Not verified yet. Open the email and tap the link first.',
        );
      }
    } catch (e) {
      if (!silent && mounted) showError(context, AuthService.message(e));
    } finally {
      _checking = false;
      if (mounted && !silent) setState(() {});
    }
  }

  Future<void> _resend() async {
    try {
      await AuthService.instance.sendEmailCode();
      if (mounted) {
        showInfo(
          context,
          'A new verification email was sent to ${widget.email}',
        );
      }
      _startCooldown();
    } catch (e) {
      if (mounted) showError(context, AuthService.message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthHeader(
                title: 'Verify your email',
                subtitle: 'One last step before you can start tracking.',
              ),
              AppCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: AppColors.purpleLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mark_email_unread_rounded,
                        color: AppColors.purple,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'We sent a verification link to',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.email,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _Step(
                      n: 1,
                      text: 'Open your email inbox (check Spam / Promotions too).',
                    ),
                    const _Step(
                      n: 2,
                      text: 'Tap the "Verify" link in the email from Firebase.',
                    ),
                    const _Step(
                      n: 3,
                      text:
                          'Come back here – you will be let in automatically.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _checking ? null : () => _check(),
                child: _checking
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text("I've verified – continue"),
              ),
              const SizedBox(height: 16),
              Center(
                child: _cooldown > 0
                    ? Text(
                        'Resend email in ${_cooldown}s',
                        style: TextStyle(color: AppColors.muted),
                      )
                    : TextButton(
                        onPressed: _resend,
                        child: const Text('Resend email'),
                      ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: AuthService.instance.signOut,
                  child: Text(
                    'Use a different account',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.orange,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$n',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
