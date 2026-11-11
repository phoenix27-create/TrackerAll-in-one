import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../auth/auth_widgets.dart';

/// Bottom sheet on the Partner Location map:
///  * which live alerts I want about my partner (driving / places / battery)
///  * my own saved places (Home / Work) that my partner gets alerts for.
Future<void> showLocationAlertsSheet(
  BuildContext context, {
  required String myUid,
  required String partnerName,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _AlertsSheet(myUid: myUid, partnerName: partnerName),
);

class _AlertsSheet extends StatelessWidget {
  const _AlertsSheet({required this.myUid, required this.partnerName});
  final String myUid;
  final String partnerName;

  DocumentReference<Map<String, dynamic>> get _me =>
      FirebaseFirestore.instance.collection('users').doc(myUid);

  Future<void> _setAlert(BuildContext context, String key, bool on) async {
    try {
      await _me.set({
        'locationAlerts': {key: on},
      }, SetOptions(merge: true));
    } catch (e) {
      if (context.mounted) showError(context, AuthService.message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: AuthService.instance.profile(myUid),
      builder: (context, snap) {
        final p = snap.data ?? const <String, dynamic>{};
        final alerts = p['locationAlerts'] is Map
            ? Map<String, dynamic>.from(p['locationAlerts'] as Map)
            : const <String, dynamic>{};
        final places = p['places'] is Map
            ? Map<String, dynamic>.from(p['places'] as Map)
            : const <String, dynamic>{};
        bool on(String k) => alerts[k] != false;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Location alerts',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Get a notification when $partnerName…',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    _AlertSwitch(
                      icon: Icons.directions_car_rounded,
                      color: const Color(0xFF1E88E5),
                      title: 'Starts or stops driving',
                      subtitle: 'Moving faster than ~22 km/h',
                      value: on('driving'),
                      onChanged: (v) => _setAlert(context, 'driving', v),
                    ),
                    Divider(height: 1, indent: 64, color: AppColors.border),
                    _AlertSwitch(
                      icon: Icons.home_rounded,
                      color: AppColors.green,
                      title: 'Leaves or arrives at Home / Work',
                      subtitle: 'The places $partnerName saved',
                      value: on('places'),
                      onChanged: (v) => _setAlert(context, 'places', v),
                    ),
                    Divider(height: 1, indent: 64, color: AppColors.border),
                    _AlertSwitch(
                      icon: Icons.battery_charging_full_rounded,
                      color: AppColors.amber,
                      title: 'Phone charging, full or low battery',
                      subtitle: 'Low = 15% or less',
                      value: on('battery'),
                      onChanged: (v) => _setAlert(context, 'battery', v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'My places',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '$partnerName gets an alert when you leave or arrive here.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    _PlaceRow(
                      me: _me,
                      id: 'home',
                      label: 'Home',
                      icon: Icons.home_rounded,
                      saved: places['home'],
                    ),
                    Divider(height: 1, indent: 64, color: AppColors.border),
                    _PlaceRow(
                      me: _me,
                      id: 'work',
                      label: 'Work',
                      icon: Icons.work_rounded,
                      saved: places['work'],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Alerts are detected on the partner\'s phone and arrive while '
                      'LifeTrack is open or in the background. Phone notifications '
                      'work on the Android / iOS app.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AlertSwitch extends StatelessWidget {
  const _AlertSwitch({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    value: value,
    onChanged: onChanged,
    secondary: _IconBox(icon: icon, color: color),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(fontSize: 12, color: AppColors.muted),
    ),
  );
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, color: color, size: 22),
  );
}

class _PlaceRow extends StatefulWidget {
  const _PlaceRow({
    required this.me,
    required this.id,
    required this.label,
    required this.icon,
    required this.saved,
  });
  final DocumentReference<Map<String, dynamic>> me;
  final String id, label;
  final IconData icon;
  final Object? saved;

  @override
  State<_PlaceRow> createState() => _PlaceRowState();
}

class _PlaceRowState extends State<_PlaceRow> {
  bool _busy = false;

  bool get _isSet => widget.saved is Map && (widget.saved as Map)['lat'] is num;

  Future<void> _setHere() async {
    setState(() => _busy = true);
    try {
      await LocationService.instance.refreshMine();
      final pos = LocationService.instance.myPosition.value;
      if (pos == null) {
        if (mounted) {
          showError(context, 'Could not get your location. Is GPS on?');
        }
        return;
      }
      await widget.me.set({
        'places': {
          widget.id: {
            'lat': pos.latitude,
            'lng': pos.longitude,
            'radius': 150,
            'setAt': FieldValue.serverTimestamp(),
          },
        },
      }, SetOptions(merge: true));
      if (mounted) {
        showInfo(context, '${widget.label} saved at your current location');
      }
    } catch (e) {
      if (mounted) showError(context, AuthService.message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    try {
      await widget.me.update({'places.${widget.id}': FieldValue.delete()});
    } catch (e) {
      if (mounted) showError(context, AuthService.message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.id == 'work' ? AppColors.purple : AppColors.green;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      leading: _IconBox(icon: widget.icon, color: color),
      title: Text(
        widget.label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        _isSet ? 'Saved · alerts within 150 m' : 'Not set',
        style: TextStyle(
          fontSize: 12,
          color: _isSet ? AppColors.green : AppColors.muted,
        ),
      ),
      trailing: _busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: _setHere,
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(_isSet ? 'Move here' : 'Set here'),
                ),
                if (_isSet)
                  IconButton(
                    tooltip: 'Remove ${widget.label}',
                    onPressed: _remove,
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppColors.muted,
                      size: 20,
                    ),
                  ),
              ],
            ),
    );
  }
}
