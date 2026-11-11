import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';

const _pink = Color(0xFFE91E63);

/// Every user must allow location to use LifeTrack (needed for Partner GPS).
/// Asks with the system prompt on first use; if the user says no, this
/// screen stays and keeps asking (or opens Settings when the phone no
/// longer shows the prompt). Re-checks whenever the app comes back.
class LocationGate extends StatefulWidget {
  const LocationGate({super.key, required this.child});
  final Widget child;

  @override
  State<LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<LocationGate>
    with WidgetsBindingObserver {
  LocationAccess? _access;
  bool _busy = false;
  bool _askedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check(autoAsk: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check({bool autoAsk = false}) async {
    var a = await _safe(LocationService.instance.status);
    // First time: show the system prompt straight away.
    if (autoAsk && !_askedOnce && a == LocationAccess.denied) {
      _askedOnce = true;
      a = await _safe(LocationService.instance.request);
    }
    if (mounted) setState(() => _access = a);
  }

  Future<LocationAccess> _safe(Future<LocationAccess> Function() f) async {
    try {
      return await f();
    } catch (e) {
      debugPrint('Location permission: $e');
      return LocationAccess.denied;
    }
  }

  Future<void> _allow() async {
    setState(() => _busy = true);
    var a = await _safe(LocationService.instance.request);
    if (a != LocationAccess.granted && !kIsWeb) {
      await LocationService.instance.openSettings(a);
      a = await _safe(LocationService.instance.status);
    }
    if (mounted) {
      setState(() {
        _access = a;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _access;
    if (a == LocationAccess.granted) return widget.child;
    if (a == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final (title, text, button) = switch (a) {
      LocationAccess.serviceOff => (
        'Turn on location',
        'Your phone\'s location (GPS) is off. Turn it on so LifeTrack can share '
            'your live location with your partner.',
        kIsWeb ? 'Try again' : 'Open location settings',
      ),
      LocationAccess.deniedForever => (
        'Allow location in Settings',
        kIsWeb
            ? 'Location is blocked for this site. Click the lock/location icon in the '
                  'address bar, choose Allow, then tap Try again.'
            : 'Location was turned off for LifeTrack. Open Settings → Permissions → '
                  'Location and choose "Allow while using the app" (or "Allow all the time").',
        kIsWeb ? 'Try again' : 'Open settings',
      ),
      _ => (
        'Allow your location',
        'LifeTrack needs your location for the Partner GPS tracker: you and your '
            'partner can see each other live on the map. Location is shared only '
            'with your connected partner.',
        'Allow location',
      ),
    };

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_pink, Color(0xFFFF6090)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _pink.withValues(alpha: 0.3),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.my_location_rounded,
                    color: Colors.white,
                    size: 54,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              const _Point(
                icon: Icons.favorite_rounded,
                text: 'Only your partner can see it',
              ),
              const _Point(
                icon: Icons.lock_rounded,
                text: 'Protected by your account',
              ),
              const _Point(
                icon: Icons.notifications_active_rounded,
                text: 'A notification shows while it is shared',
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _pink,
                  minimumSize: const Size.fromHeight(54),
                ),
                onPressed: _busy ? null : _allow,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.location_on_rounded),
                label: Text(button),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => AuthService.instance.signOut(),
                child: Text(
                  'Log out',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: _pink),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 13)),
      ],
    ),
  );
}
