import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/partner_service.dart';
import '../auth/auth_widgets.dart';
import '../expense/expense_shell.dart';
import '../profile/profile_screen.dart';

const _pink = Color(0xFFE91E63);

/// Main-menu card:
///  * single  -> my partner code + "Connect with partner"
///  * linked  -> "Me ♥ Partner" names, latest partner activity, shortcuts
class PartnerCard extends StatelessWidget {
  const PartnerCard({super.key, required this.user, required this.profile});
  final User user;
  final Map<String, dynamic> profile;

  String get _myName {
    final n = (profile['name'] as String?)?.trim();
    if (n != null && n.isNotEmpty) return n;
    if (user.displayName?.isNotEmpty ?? false) return user.displayName!;
    return (user.email ?? 'Me').split('@').first;
  }

  @override
  Widget build(BuildContext context) {
    final partnerId = profile['partnerId'] as String?;
    if (partnerId == null) {
      final code = profile['partnerCode'] as String?;
      if (code == null) PartnerService.instance.ensureCode(user.uid);
      return _SingleCard(code: code, onConnect: () => _showConnect(context));
    }
    return _LinkedCard(
      user: user,
      me: profile,
      myName: _myName,
      partnerId: partnerId,
    );
  }

  Future<void> _showConnect(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ConnectSheet(myUid: user.uid, myName: _myName),
  );
}

// ===========================================================================

class _SingleCard extends StatelessWidget {
  const _SingleCard({required this.code, required this.onConnect});
  final String? code;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _pink.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.favorite_rounded, color: _pink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share with your partner',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'Manage each other\'s expenses & get notified',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Your partner code',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: code == null
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          code!,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 6,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                width: 50,
                child: IconButton.filledTonal(
                  tooltip: 'Copy code',
                  onPressed: code == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: code!));
                          showInfo(
                            context,
                            'Code $code copied – send it to your partner',
                          );
                        },
                  icon: const Icon(Icons.copy_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Share this code, or enter your partner\'s code below.',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _pink),
            onPressed: onConnect,
            icon: const Icon(Icons.link_rounded),
            label: const Text('Connect with partner'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================

class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet({required this.myUid, required this.myName});
  final String myUid;
  final String myName;
  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PartnerService.instance.connect(
        myUid: widget.myUid,
        myName: widget.myName,
        rawCode: _code.text,
      );
      if (mounted) {
        Navigator.pop(context);
        showInfo(
          context,
          'Connected 💞 You can now manage each other\'s expenses.',
        );
      }
    } catch (e) {
      setState(
        () =>
            _error = e is PartnerException ? e.message : AuthService.message(e),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Connect with partner',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter the 6-character code shown on your partner\'s LifeTrack main screen. '
            'You can only connect with one partner.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _code,
            autofocus: true,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              TextInputFormatter.withFunction(
                (o, n) => n.copyWith(text: n.text.toUpperCase()),
              ),
            ],
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) =>
                _code.text.length == 6 && !_busy ? _connect() : null,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              hintText: 'ABC123',
              counterText: '',
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _pink),
            onPressed: _busy || _code.text.length != 6 ? null : _connect,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================

class _LinkedCard extends StatelessWidget {
  const _LinkedCard({
    required this.user,
    required this.me,
    required this.myName,
    required this.partnerId,
  });
  final User user;
  final Map<String, dynamic> me;
  final String myName;
  final String partnerId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: AuthService.instance.profile(partnerId),
      builder: (context, snap) {
        final p = snap.data ?? const <String, dynamic>{};
        final partnerName = (p['name'] as String?)?.trim().isNotEmpty == true
            ? p['name'] as String
            : (p['email'] as String? ?? 'Partner').split('@').first;
        final since = (me['partnerSince'] as Timestamp?)?.toDate();
        final iRequested = me['disconnectRequestedAt'] != null;
        final theyRequested = p['disconnectRequestedAt'] != null;
        final first = partnerName.split(' ').first;

        return AppCard(
          padding: const EdgeInsets.all(18),
          gradient: LinearGradient(
            colors: [AppColors.pinkSoft, AppColors.card],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'You & your partner',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (!iRequested && !theyRequested)
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: AppColors.muted,
                      ),
                      onSelected: (v) {
                        if (v == 'disconnect') {
                          _requestDisconnect(context, partnerName);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'disconnect',
                          child: Row(
                            children: [
                              Icon(
                                Icons.link_off_rounded,
                                color: AppColors.red,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Text('Disconnect partner'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _Person(
                      name: myName,
                      label: 'You',
                      photo: me['usePhoto'] != false ? user.photoURL : null,
                      color: avatarColorOf(me),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _pink.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: _pink,
                      size: 22,
                    ),
                  ),
                  Expanded(
                    child: _Person(
                      name: partnerName,
                      label: 'Partner',
                      photo: p['usePhoto'] != false
                          ? p['photoUrl'] as String?
                          : null,
                      color: avatarColorOf(p),
                    ),
                  ),
                ],
              ),
              if (since != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Connected since ${_date(since)}',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ),
              ],
              if (theyRequested)
                _DisconnectBanner(
                  text:
                      '$first wants to disconnect. Both of you must agree – '
                      'confirm to stop sharing, or stay connected.',
                  actions: [
                    OutlinedButton(
                      onPressed: () => _run(
                        context,
                        () => PartnerService.instance.declineDisconnect(
                          myUid: user.uid,
                          myName: myName,
                          partnerUid: partnerId,
                        ),
                        'You are still connected with $first 💞',
                      ),
                      child: const Text('Stay connected'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.red,
                      ),
                      onPressed: () => _confirmDisconnect(context, first),
                      child: const Text('Confirm'),
                    ),
                  ],
                )
              else if (iRequested)
                _DisconnectBanner(
                  text:
                      'Disconnect requested. Waiting for $first to confirm. '
                      'You stay connected until they do.',
                  actions: [
                    OutlinedButton(
                      onPressed: () => _run(
                        context,
                        () => PartnerService.instance.cancelDisconnect(
                          myUid: user.uid,
                          myName: myName,
                          partnerUid: partnerId,
                        ),
                        'Request cancelled',
                      ),
                      child: const Text('Cancel request'),
                    ),
                  ],
                ),
              StreamBuilder<List<PartnerActivity>>(
                stream: PartnerService.instance.recentActivity(
                  user.uid,
                  limit: 2,
                ),
                builder: (_, a) {
                  final items = a.data ?? const [];
                  if (items.isEmpty) return const SizedBox(height: 4);
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: [
                        for (final it in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.notifications_rounded,
                                  size: 15,
                                  color: _pink,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    it.shortText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                Text(
                                  _ago(it.createdAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _pink,
                    minimumSize: const Size(0, 46),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExpenseShell(
                        uid: partnerId,
                        partnerView: true,
                        ownerName: first,
                      ),
                    ),
                  ),
                  icon: const Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 20,
                  ),
                  label: Text("Open $first's expenses"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _ask(
    BuildContext context,
    String title,
    String text,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action, style: TextStyle(color: AppColors.red)),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() job,
    String done,
  ) async {
    try {
      await job();
      if (context.mounted) showInfo(context, done);
    } catch (e) {
      if (context.mounted) {
        showError(
          context,
          e is PartnerException ? e.message : AuthService.message(e),
        );
      }
    }
  }

  /// Step 1 – ask the partner. Nothing is unlinked until they confirm.
  Future<void> _requestDisconnect(
    BuildContext context,
    String partnerName,
  ) async {
    final first = partnerName.split(' ').first;
    if (!await _ask(
      context,
      'Ask to disconnect?',
      '$first must confirm before you are disconnected. Until then you stay connected. '
          'After disconnecting you will no longer see each other\'s expenses. '
          'Nobody\'s data is deleted.',
      'Send request',
    )) {
      return;
    }
    if (!context.mounted) return;
    await _run(
      context,
      () => PartnerService.instance.requestDisconnect(
        myUid: user.uid,
        myName: myName,
        partnerUid: partnerId,
      ),
      'Request sent – waiting for $first to confirm',
    );
  }

  /// Step 2 – the partner asked, I confirm.
  Future<void> _confirmDisconnect(BuildContext context, String first) async {
    if (!await _ask(
      context,
      'Disconnect from $first?',
      'You both agreed. You will no longer see or manage each other\'s expenses. '
          'Nobody\'s data is deleted.',
      'Disconnect',
    )) {
      return;
    }
    if (!context.mounted) return;
    await _run(
      context,
      () => PartnerService.instance.confirmDisconnect(
        myUid: user.uid,
        partnerUid: partnerId,
      ),
      'Disconnected',
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

class _DisconnectBanner extends StatelessWidget {
  const _DisconnectBanner({required this.text, required this.actions});
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.redSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.link_off_rounded, color: AppColors.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: const TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final a in actions) ...[const SizedBox(width: 8), a],
            ],
          ),
        ],
      ),
    );
  }
}

class _Person extends StatelessWidget {
  const _Person({
    required this.name,
    required this.label,
    required this.color,
    this.photo,
  });
  final String name;
  final String label;
  final String? photo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.card, width: 3),
            image: photo != null
                ? DecorationImage(
                    image: NetworkImage(photo!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: photo == null
              ? Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.muted)),
      ],
    );
  }
}
