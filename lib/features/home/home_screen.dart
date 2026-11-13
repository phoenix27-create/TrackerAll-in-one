import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../location/partner_map_screen.dart';
import '../../services/partner_service.dart';
import '../../services/push_service.dart';
import '../../services/reminder_service.dart';
import '../expense/expense_shell.dart';
import '../partner/partner_card.dart';
import '../profile/profile_screen.dart';

class TrackerInfo {
  const TrackerInfo({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    this.builder,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;

  /// null = coming soon.
  final WidgetBuilder? builder;
  bool get available => builder != null;
}

/// Main menu after login: one card per tracker.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});
  final User user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final Stream<Map<String, dynamic>> _profile = AuthService.instance
      .profile(widget.user.uid);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Permissions were asked on the onboarding screens (PermissionsFlow).
    ReminderService.instance.sync(widget.user.uid);
    PartnerService.instance.ensureCode(widget.user.uid);
    PartnerService.instance.listenInbox(widget.user.uid);
    // Web: get notifications even when the app is closed.
    PushService.instance.register(widget.user.uid);
    // Share live GPS while linked with a partner; stop when not.
    _profileSub = _profile.listen((p) {
      final pid = p['partnerId'] as String?;
      if (pid != _partnerId || !_locationStarted) {
        _locationStarted = true;
        setState(() => _partnerId = pid);
      }
      // Also passes name + saved places (Home / Work) for partner alerts;
      // cheap when nothing changed (sharing keeps running).
      LocationService.instance.update(uid: widget.user.uid, profile: p);
      // Which live-GPS alerts this user wants to receive.
      final prefs = p['locationAlerts'];
      PartnerService.instance.alertPrefs = prefs is Map
          ? Map<String, dynamic>.from(prefs)
          : const {};
    });
  }

  String? _partnerId;
  bool _locationStarted = false;
  StreamSubscription<Map<String, dynamic>>? _profileSub;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _profileSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // New day / data changed elsewhere: re-plan "no expense today" reminders.
    if (state == AppLifecycleState.resumed) {
      ReminderService.instance.sync(widget.user.uid);
      // Keeps the subscription (and time zone for reminders) fresh.
      PushService.instance.register(widget.user.uid);
    }
  }

  void _openProfile() =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ProfileScreen()));

  List<TrackerInfo> get _trackers => [
    TrackerInfo(
      title: 'Expense Tracker',
      subtitle: 'Salary, spending & savings',
      icon: Icons.account_balance_wallet_rounded,
      colors: [AppColors.purple, Color(0xFF9D6BFF)],
      builder: (_) => ExpenseShell(uid: widget.user.uid),
    ),
    TrackerInfo(
      title: 'Partner Location',
      subtitle: 'Live GPS with your partner',
      icon: Icons.location_on_rounded,
      colors: const [Color(0xFFE91E63), Color(0xFFFF6090)],
      builder: (_) =>
          PartnerMapScreen(myUid: widget.user.uid, partnerId: _partnerId),
    ),
    TrackerInfo(
      title: 'Fitness Tracker',
      subtitle: 'Steps, workouts & weight',
      icon: Icons.fitness_center_rounded,
      colors: [AppColors.orange, Color(0xFFFF9466)],
    ),
    const TrackerInfo(
      title: 'Habit Tracker',
      subtitle: 'Build daily routines',
      icon: Icons.check_circle_rounded,
      colors: [Color(0xFF00897B), Color(0xFF26C6A6)],
    ),
    const TrackerInfo(
      title: 'Sleep Tracker',
      subtitle: 'Bedtime & sleep quality',
      icon: Icons.bedtime_rounded,
      colors: [Color(0xFF3949AB), Color(0xFF7986CB)],
    ),
    const TrackerInfo(
      title: 'Water Tracker',
      subtitle: 'Daily hydration goal',
      icon: Icons.water_drop_rounded,
      colors: [Color(0xFF1E88E5), Color(0xFF64B5F6)],
    ),
  ];

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final name = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.split(' ').first
        : (user.email ?? '').split('@').first;
    final trackers = _trackers;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    StreamBuilder<Map<String, dynamic>>(
                      stream: _profile,
                      builder: (_, snap) => GestureDetector(
                        onTap: _openProfile,
                        child: _Avatar(
                          user: user,
                          profile: snap.data ?? const {},
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _RoundIcon(
                      icon: AppColors.isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      tooltip: AppColors.isDark ? 'Light mode' : 'Dark mode',
                      onTap: () => ThemeController.instance.toggle(
                        Theme.of(context).brightness,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RoundIcon(
                      icon: Icons.manage_accounts_rounded,
                      tooltip: 'Edit profile',
                      onTap: _openProfile,
                    ),
                    const SizedBox(width: 8),
                    _RoundIcon(
                      icon: Icons.logout_rounded,
                      tooltip: 'Log out',
                      onTap: () => _confirmLogout(context),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              sliver: SliverToBoxAdapter(child: _HeroCard()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              sliver: SliverToBoxAdapter(
                child: StreamBuilder<Map<String, dynamic>>(
                  stream: _profile,
                  builder: (_, snap) => snap.hasData
                      ? PartnerCard(user: user, profile: snap.data!)
                      : const SizedBox.shrink(),
                ),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverToBoxAdapter(child: SectionHeader('Your trackers')),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverGrid.builder(
                itemCount: trackers.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.88,
                ),
                itemBuilder: (_, i) => _TrackerCard(info: trackers[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can log in again any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) await AuthService.instance.signOut();
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      gradient: LinearGradient(
        colors: [AppColors.navy, AppColors.navyDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Track your life,\none card at a time',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Expense & Partner GPS are live. More trackers are coming soon.',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.insights_rounded,
              color: AppColors.orange,
              size: 34,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({required this.info});
  final TrackerInfo info;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: () {
        if (info.available) {
          Navigator.of(context).push(MaterialPageRoute(builder: info.builder!));
        } else {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text('${info.title} is coming soon 🚀')),
            );
        }
      },
      child: Opacity(
        opacity: info.available ? 1 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: info.colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(info.icon, color: Colors.white, size: 26),
                ),
                const Spacer(),
                if (!info.available)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Soon',
                      style: TextStyle(fontSize: 10.5, color: AppColors.muted),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              info.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              info.subtitle,
              maxLines: 2,
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  info.available ? 'Open' : 'Coming soon',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: info.available ? info.colors.first : AppColors.muted,
                  ),
                ),
                const SizedBox(width: 4),
                if (info.available)
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: info.colors.first,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.profile});
  final User user;
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final name = (profile['name'] as String?)?.isNotEmpty == true
        ? profile['name'] as String
        : (user.displayName?.isNotEmpty ?? false)
        ? user.displayName!
        : (user.email ?? '?');
    final initial = name.substring(0, 1).toUpperCase();
    final showPhoto = user.photoURL != null && profile['usePhoto'] != false;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: avatarColorOf(profile),
            borderRadius: BorderRadius.circular(14),
            image: showPhoto
                ? DecorationImage(
                    image: NetworkImage(user.photoURL!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: showPhoto
              ? null
              : Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
        ),
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(Icons.edit_rounded, size: 11, color: AppColors.purple),
          ),
        ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            // Sun / moon spin when the theme flips.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (c, a) => RotationTransition(
                turns: Tween(begin: 0.6, end: 1.0).animate(a),
                child: ScaleTransition(scale: a, child: c),
              ),
              child: Icon(icon, key: ValueKey(icon), size: 21),
            ),
          ),
        ),
      ),
    );
  }
}
