import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../services/web_notify.dart';

const _pink = Color(0xFFE91E63);

enum _Step { location, notifications }

/// First-run permissions, like other apps – the same on the phone apps and
/// the web (incl. the iPhone home-screen app):
///
///   1. Location      – required (Partner GPS). "Allow location" shows the
///                      system prompt; if it was blocked, help or Settings.
///   2. Notifications – optional. "Allow notifications" shows the prompt,
///                      "Not now" skips; asked once per device.
///   → main menu.
///
/// Prompts only appear after a tap (Apple's guideline, and browsers require
/// it). Location is re-checked whenever the app comes back.
class PermissionsFlow extends StatefulWidget {
  const PermissionsFlow({super.key, required this.child});
  final Widget child;

  @override
  State<PermissionsFlow> createState() => _PermissionsFlowState();
}

class _PermissionsFlowState extends State<PermissionsFlow>
    with WidgetsBindingObserver {
  static const _askedKey = 'notificationsAsked';

  bool _loading = true;
  LocationAccess _location = LocationAccess.denied;
  NotifyAccess _notify = NotifyAccess.notDetermined;
  bool _notifyAsked = false;
  bool _busy = false;
  int _total = 1; // steps shown this time (for "Step 1 of 2")

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recheckLocation();
  }

  Future<void> _load() async {
    final loc = await _safeLoc(LocationService.instance.status);
    final notify = await NotificationService.instance.status();
    var asked = false;
    try {
      asked =
          (await SharedPreferences.getInstance()).getBool(_askedKey) ?? false;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _location = loc;
      _notify = notify;
      _notifyAsked = asked;
      _loading = false;
      _total = (_needsLocation ? 1 : 0) + (_needsNotify ? 1 : 0);
    });
  }

  /// After coming back from Settings (or another app).
  Future<void> _recheckLocation() async {
    var a = await _safeLoc(LocationService.instance.status);
    // Browsers often say "not decided" again after switching apps even when
    // allowed – only a real block brings the user back to this screen.
    if (kIsWeb &&
        _location == LocationAccess.granted &&
        a == LocationAccess.denied) {
      a = LocationAccess.granted;
    }
    if (mounted && a != _location) setState(() => _location = a);
  }

  Future<LocationAccess> _safeLoc(Future<LocationAccess> Function() f) async {
    try {
      return await f();
    } catch (e) {
      debugPrint('Location permission: $e');
      return LocationAccess.denied;
    }
  }

  bool get _needsLocation => _location != LocationAccess.granted;

  /// Ask once per device; skip if already decided or not available.
  bool get _needsNotify =>
      !_notifyAsked &&
      (_notify == NotifyAccess.notDetermined ||
          // iPhone Safari tab: explain once that it needs "Add to Home Screen".
          (_notify == NotifyAccess.unsupported && _iosBrowserTab));

  bool get _iosBrowserTab =>
      kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      !webIsStandalone();

  _Step? get _step => _needsLocation
      ? _Step.location
      : _needsNotify
      ? _Step.notifications
      : null;

  // ------------------------------------------------------------ actions --

  Future<void> _allowLocation() async {
    setState(() => _busy = true);
    var a = _location;
    if (!kIsWeb &&
        (a == LocationAccess.deniedForever || a == LocationAccess.serviceOff)) {
      // The phone won't show the prompt again – send them to Settings.
      await LocationService.instance.openSettings(a);
      a = await _safeLoc(LocationService.instance.status);
    } else {
      a = await _safeLoc(LocationService.instance.request);
    }
    if (mounted) {
      setState(() {
        _location = a;
        _busy = false;
      });
    }
  }

  Future<void> _allowNotifications() async {
    setState(() => _busy = true);
    final r = _notify == NotifyAccess.unsupported
        ? NotifyAccess.unsupported
        : await NotificationService.instance.request();
    await _markAsked();
    if (!mounted) return;
    setState(() {
      _notify = r;
      _busy = false;
    });
    if (r == NotifyAccess.denied && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are off. You can turn them on later in Settings.',
          ),
        ),
      );
    }
  }

  Future<void> _skipNotifications() async {
    await _markAsked();
    if (mounted) setState(() {});
  }

  Future<void> _markAsked() async {
    _notifyAsked = true;
    try {
      await (await SharedPreferences.getInstance()).setBool(_askedKey, true);
    } catch (_) {}
  }

  // -------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final step = _step;
    if (step == null) return widget.child;

    final index = step == _Step.location || _total < 2 ? 0 : 1;
    final page = switch (step) {
      _Step.location => _locationPage(),
      _Step.notifications => _notifyPage(),
    };
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0.12, 0),
                end: Offset.zero,
              ).animate(a),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(step),
            child: _PageFrame(
              index: index,
              total: _total < 1 ? 1 : _total,
              child: page,
            ),
          ),
        ),
      ),
    );
  }

  Widget _locationPage() {
    final a = _location;
    final blockedWeb =
        kIsWeb &&
        (a == LocationAccess.deniedForever || a == LocationAccess.serviceOff);
    final (title, text, button) = switch (a) {
      _ when blockedWeb => (
        'Allow location for this site',
        'Your browser blocked location for LifeTrack. Follow these steps, then tap Try again:',
        'Try again',
      ),
      LocationAccess.serviceOff => (
        'Turn on location',
        'Your phone\'s location (GPS) is off. Turn it on so LifeTrack can share your live location with your partner.',
        'Open location settings',
      ),
      LocationAccess.deniedForever => (
        'Allow location in Settings',
        'Location is turned off for LifeTrack. In Settings choose Location → "While Using the App" (or "Always").',
        'Open Settings',
      ),
      _ => (
        'Share your location',
        'LifeTrack uses your location for Partner GPS: you and your partner can see each other live on the map, get directions and arrival alerts.',
        'Allow location',
      ),
    };
    return _PermissionPage(
      icon: Icons.my_location_rounded,
      colors: const [_pink, Color(0xFFFF6090)],
      title: title,
      text: text,
      extra: blockedWeb
          ? const _BrowserSteps()
          : const Column(
              children: [
                _Point(
                  icon: Icons.favorite_rounded,
                  text: 'Only your partner can see it',
                ),
                _Point(
                  icon: Icons.lock_rounded,
                  text: 'Protected by your account',
                ),
                _Point(
                  icon: Icons.tune_rounded,
                  text: 'Change it any time in Settings',
                ),
              ],
            ),
      primary: button,
      primaryIcon: Icons.location_on_rounded,
      primaryColor: _pink,
      busy: _busy,
      onPrimary: _allowLocation,
      secondary: 'Log out',
      onSecondary: () => AuthService.instance.signOut(),
    );
  }

  Widget _notifyPage() {
    final unsupported = _notify == NotifyAccess.unsupported;
    return _PermissionPage(
      icon: Icons.notifications_active_rounded,
      colors: [AppColors.purple, const Color(0xFF9D6BFF)],
      title: unsupported
          ? 'Get notifications on iPhone'
          : 'Turn on notifications',
      text: unsupported
          ? 'iPhone shows web app notifications only when LifeTrack is on your Home Screen. '
                'Tap the Share button, choose "Add to Home Screen", then open LifeTrack from its icon.'
          : 'Stay in the loop with your partner and your budget. You can change this any time.',
      extra: const Column(
        children: [
          _Point(
            icon: Icons.payments_rounded,
            text: 'Partner expenses & budget alerts',
            color: null,
          ),
          _Point(
            icon: Icons.directions_car_rounded,
            text: 'Driving, leaving & arriving home',
            color: null,
          ),
          _Point(
            icon: Icons.alarm_rounded,
            text: 'Daily expense reminders',
            color: null,
          ),
        ],
      ),
      primary: unsupported ? 'Got it' : 'Allow notifications',
      primaryIcon: unsupported
          ? Icons.check_rounded
          : Icons.notifications_rounded,
      primaryColor: AppColors.purple,
      busy: _busy,
      onPrimary: unsupported ? _skipNotifications : _allowNotifications,
      secondary: unsupported ? null : 'Not now',
      onSecondary: _skipNotifications,
    );
  }
}

// ===========================================================================

/// Progress dots + page.
class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.index,
    required this.total,
    required this.child,
  });
  final int index, total;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (total > 1)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < total; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == index ? AppColors.purple : AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(child: child),
      ],
    );
  }
}

class _PermissionPage extends StatelessWidget {
  const _PermissionPage({
    required this.icon,
    required this.colors,
    required this.title,
    required this.text,
    required this.extra,
    required this.primary,
    required this.primaryIcon,
    required this.primaryColor,
    required this.busy,
    required this.onPrimary,
    this.secondary,
    this.onSecondary,
  });

  final IconData icon;
  final List<Color> colors;
  final String title, text, primary;
  final Widget extra;
  final IconData primaryIcon;
  final Color primaryColor;
  final bool busy;
  final VoidCallback onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              // Extra bottom space on the web keeps buttons above the host badge.
              padding: EdgeInsets.fromLTRB(28, 24, 28, 20 + webBottomGap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Center(
                    child: Container(
                      width: 116,
                      height: 116,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: colors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colors.first.withValues(alpha: 0.3),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 52),
                    ),
                  ),
                  const SizedBox(height: 30),
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
                  extra,
                  const SizedBox(height: 24),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      minimumSize: const Size.fromHeight(54),
                    ),
                    onPressed: busy ? null : onPrimary,
                    icon: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Icon(primaryIcon),
                    label: Text(primary),
                  ),
                  const SizedBox(height: 8),
                  if (secondary != null)
                    TextButton(
                      onPressed: busy ? null : onSecondary,
                      child: Text(
                        secondary!,
                        style: TextStyle(color: AppColors.muted),
                      ),
                    )
                  else
                    const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Step-by-step help for a browser that blocked location, written for the
/// device the page is open on (iPhone / Android / computer).
class _BrowserSteps extends StatelessWidget {
  const _BrowserSteps();

  @override
  Widget build(BuildContext context) {
    final steps = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => const [
        'Open the iPhone Settings app → Privacy & Security → Location Services, and turn it On.',
        'In that list, tap Safari Websites (or Chrome if you use Chrome) and choose "While Using the App".',
        'In Safari, tap "aA" (or the page icon) in the address bar → Website Settings → Location → Allow. '
            '(Home Screen app: delete and re-add it if it never asks.)',
        'Come back and tap Try again, then tap Allow when asked.',
      ],
      TargetPlatform.android => const [
        'Swipe down from the top of the screen and turn Location on.',
        'In Chrome, tap the icon left of the address (lock or tune icon) → Permissions → Location → Allow.',
        'Tap Try again, then Allow when asked.',
      ],
      _ => const [
        'Click the lock / location icon at the left of the address bar.',
        'Set Location to Allow for this site.',
        'Click Try again.',
      ],
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _pink.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: _pink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: const TextStyle(fontSize: 13, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text, this.color = _pink});
  final IconData icon;
  final String text;

  /// null = the brand purple of the current mode.
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color ?? AppColors.purple),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
