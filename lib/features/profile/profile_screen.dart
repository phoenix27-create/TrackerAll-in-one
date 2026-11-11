import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/reminder_service.dart';
import '../auth/auth_widgets.dart';
import 'appearance_picker.dart';

/// Colours the user can pick for their initials avatar.
const avatarColors = <Color>[
  Color(0xFF7B3FF2),
  Color(0xFFFF6B35),
  Color(0xFFE91E63),
  Color(0xFF00897B),
  Color(0xFF1E88E5),
  Color(0xFF3949AB),
  Color(0xFF43A047),
  Color(0xFF2B2D42),
];

Color avatarColorOf(Map<String, dynamic> profile) {
  final i = (profile['avatarColor'] as num?)?.toInt() ?? 0;
  return avatarColors[i.clamp(0, avatarColors.length - 1)];
}

/// Edit account information + app settings.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _occupation = TextEditingController();
  DateTime? _birthday;
  String? _gender;
  int _color = 0;
  bool _reminders = true;
  bool _usePhoto = true;
  bool _loaded = false;
  bool _saving = false;

  final _auth = AuthService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final u = _auth.user!;
    final p = await _auth.profile(u.uid).first;
    if (!mounted) return;
    setState(() {
      _name.text = (p['name'] as String?)?.isNotEmpty == true
          ? p['name'] as String
          : (u.displayName ?? '');
      _phone.text = p['phone'] as String? ?? '';
      _occupation.text = p['occupation'] as String? ?? '';
      final b = p['birthday'];
      _birthday = b is String ? DateTime.tryParse(b) : null;
      _gender = p['gender'] as String?;
      _color = (p['avatarColor'] as num?)?.toInt() ?? 0;
      _reminders = p['expenseReminders'] != false;
      _usePhoto = p['usePhoto'] != false;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _occupation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _auth.updateProfile({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'occupation': _occupation.text.trim(),
        'birthday': _birthday == null
            ? null
            : '${_birthday!.year.toString().padLeft(4, '0')}-'
                  '${_birthday!.month.toString().padLeft(2, '0')}-'
                  '${_birthday!.day.toString().padLeft(2, '0')}',
        'gender': _gender,
        'avatarColor': _color,
        'usePhoto': _usePhoto,
        'expenseReminders': _reminders,
      });
      await ReminderService.instance.sync(_auth.user!.uid);
      if (mounted) {
        showInfo(context, 'Profile updated ✓');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showError(context, AuthService.message(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _auth.user!;
    final hasPhoto = u.photoURL != null;
    final initial =
        (_name.text.trim().isNotEmpty ? _name.text.trim() : (u.email ?? '?'))
            .substring(0, 1)
            .toUpperCase();

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  // ---------------------------------------------- avatar card
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            color: avatarColors[_color],
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.card, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: avatarColors[_color].withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                            image: hasPhoto && _usePhoto
                                ? DecorationImage(
                                    image: NetworkImage(u.photoURL!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: hasPhoto && _usePhoto
                              ? null
                              : Text(
                                  initial,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 38,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _name.text.isEmpty ? 'Your name' : _name.text,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                u.email ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: AppColors.green,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (hasPhoto)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Use Google photo'),
                            value: _usePhoto,
                            onChanged: (v) => setState(() => _usePhoto = v),
                          ),
                        if (!hasPhoto || !_usePhoto) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Avatar colour',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (var i = 0; i < avatarColors.length; i++)
                                GestureDetector(
                                  onTap: () => setState(() => _color = i),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: avatarColors[i],
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: i == _color
                                            ? AppColors.text
                                            : Colors.transparent,
                                        width: 2.5,
                                      ),
                                    ),
                                    child: i == _color
                                        ? const Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 18,
                                          )
                                        : null,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // -------------------------------------------- personal info
                  const SectionHeader('Personal information'),
                  AppCard(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setState(() {}),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Enter your name'
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: u.email,
                          enabled: false,
                          decoration: const InputDecoration(
                            labelText: 'Email (cannot be changed)',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+ ]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            hintText: '09xxxxxxxxx',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _occupation,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Occupation',
                            prefixIcon: Icon(Icons.work_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _birthday ?? DateTime(2000),
                              firstDate: DateTime(1930),
                              lastDate: DateTime.now(),
                              initialDatePickerMode: DatePickerMode.year,
                            );
                            if (d != null) setState(() => _birthday = d);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Birthday',
                              prefixIcon: Icon(Icons.cake_outlined),
                            ),
                            child: Text(
                              _birthday == null
                                  ? 'Not set'
                                  : dayLabel(_birthday!),
                              style: TextStyle(
                                color: _birthday == null
                                    ? AppColors.muted
                                    : AppColors.text,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text(
                              'Gender',
                              style: TextStyle(color: AppColors.muted),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                children: [
                                  for (final g in const [
                                    'Male',
                                    'Female',
                                    'Other',
                                  ])
                                    ChoiceChip(
                                      label: Text(g),
                                      selected: _gender == g,
                                      onSelected: (s) => setState(
                                        () => _gender = s ? g : null,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ----------------------------------------------- appearance
                  const SectionHeader('Appearance'),
                  const AppearancePicker(),

                  // ------------------------------------------------- settings
                  const SectionHeader('Notifications'),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: SwitchListTile(
                      value: _reminders,
                      onChanged: (v) => setState(() => _reminders = v),
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.orangeLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.notifications_active_rounded,
                          color: AppColors.orange,
                        ),
                      ),
                      title: const Text(
                        'Daily expense reminders',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        kIsWeb ? 'Works on the Android / iOS app' : 'Every 3 hours (9AM–9PM) if nothing is logged today',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),

                  // ------------------------------------------------- security
                  const SectionHeader('Security'),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        if (_auth.isPasswordUser)
                          ListTile(
                            leading: Icon(
                              Icons.lock_reset_rounded,
                              color: AppColors.purple,
                            ),
                            title: const Text('Change password'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _changePassword(context),
                          )
                        else
                          ListTile(
                            leading: Icon(
                              Icons.verified_user_rounded,
                              color: AppColors.green,
                            ),
                            title: Text('Signed in with Google'),
                            subtitle: Text(
                              'Password is managed by your Google account',
                            ),
                          ),
                        Divider(height: 1, color: AppColors.border),
                        ListTile(
                          leading: Icon(
                            Icons.logout_rounded,
                            color: AppColors.red,
                          ),
                          title: Text(
                            'Log out',
                            style: TextStyle(color: AppColors.red),
                          ),
                          onTap: () async {
                            Navigator.of(context).popUntil((r) => r.isFirst);
                            await _auth.signOut();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save changes'),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) {
        var busy = false;
        return StatefulBuilder(
          builder: (c, setSheet) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              24 + MediaQuery.viewInsetsOf(c).bottom,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Change password',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  PasswordField(
                    controller: current,
                    label: 'Current password',
                    validator: (v) =>
                        (v ?? '').isEmpty ? 'Enter current password' : null,
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: next,
                    label: 'New password',
                    validator: (v) =>
                        (v ?? '').length < 6 ? 'At least 6 characters' : null,
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: confirm,
                    label: 'Confirm new password',
                    validator: (v) =>
                        v != next.text ? 'Passwords do not match' : null,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setSheet(() => busy = true);
                            try {
                              await _auth.changePassword(
                                current.text,
                                next.text,
                              );
                              if (c.mounted) Navigator.pop(c);
                              if (mounted) {
                                showInfo(this.context, 'Password changed ✓');
                              }
                            } catch (e) {
                              setSheet(() => busy = false);
                              if (c.mounted) {
                                ScaffoldMessenger.of(c).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppColors.red,
                                    content: Text(AuthService.message(e)),
                                  ),
                                );
                              }
                            }
                          },
                    child: Text(busy ? 'Saving…' : 'Update password'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    // Controllers are left to the GC: the sheet may still be animating out.
  }
}
