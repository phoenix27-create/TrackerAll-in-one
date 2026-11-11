import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'web_notify.dart';

/// Notification permission state (phone apps and browsers).
enum NotifyAccess { granted, denied, notDetermined, unsupported }

/// Device notifications: Android + iOS (flutter_local_notifications) and the
/// web (browser notifications, incl. iPhone home-screen apps).
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _alerts = AndroidNotificationChannel(
    'budget_alerts',
    'Budget alerts',
    description:
        'Warnings when your spending is close to or below your keep amount',
    importance: Importance.max,
  );

  static const _reminders = AndroidNotificationChannel(
    'expense_reminders',
    'Expense reminders',
    description: 'Reminders to log your daily expenses',
    importance: Importance.high,
  );

  static const _partner = AndroidNotificationChannel(
    'partner_activity',
    'Partner activity',
    description: 'When your partner adds an expense or connects with you',
    importance: Importance.high,
  );

  Future<void> showPartner({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) {
      await webNotifyShow(title, body, tag: 'partner-$id');
      return;
    }
    try {
      await init();
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _partner.id,
            _partner.name,
            channelDescription: _partner.description,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
            color: const Color(0xFFE91E63),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Partner notification failed: $e');
    }
  }

  Future<void> _initTimezone() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Yangon'));
    }
  }

  /// Schedules a one-off reminder at [when] (device local time).
  Future<void> scheduleReminder({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    await init();
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      title: title,
      body: body,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _reminders.id,
          _reminders.name,
          channelDescription: _reminders.description,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
          color: const Color(0xFF7B3FF2),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
  }

  Future<void> cancelIds(Iterable<int> ids) async {
    if (kIsWeb) return;
    await init();
    for (final id in ids) {
      await _plugin.cancel(id: id);
    }
  }

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await init();
    await _plugin.cancelAll();
  }

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    await _initTimezone();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_alerts);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_reminders);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_partner);
    _ready = true;
  }

  /// Current permission, without asking.
  Future<NotifyAccess> status() async {
    if (kIsWeb) return _fromWeb(webNotifyStatus());
    try {
      await init();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        final on = await android.areNotificationsEnabled();
        return on == true ? NotifyAccess.granted : NotifyAccess.notDetermined;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        final p = await ios.checkPermissions();
        return p?.isEnabled == true
            ? NotifyAccess.granted
            : NotifyAccess.notDetermined;
      }
    } catch (e) {
      debugPrint('Notification status: $e');
    }
    return NotifyAccess.notDetermined;
  }

  /// Shows the system "Allow notifications?" prompt (call from a tap).
  Future<NotifyAccess> request() async {
    if (kIsWeb) return _fromWeb(await webNotifyRequest());
    try {
      await init();
      bool? ok = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      ok ??= await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return ok == true ? NotifyAccess.granted : NotifyAccess.denied;
    } catch (e) {
      debugPrint('Notification request: $e');
      return NotifyAccess.denied;
    }
  }

  /// Kept for older call sites.
  Future<void> requestPermission() async => request();

  static NotifyAccess _fromWeb(String s) => switch (s) {
    'granted' => NotifyAccess.granted,
    'denied' => NotifyAccess.denied,
    'default' => NotifyAccess.notDetermined,
    _ => NotifyAccess.unsupported,
  };

  Future<void> show({
    required String title,
    required String body,
    bool urgent = false,
  }) async {
    if (kIsWeb) {
      await webNotifyShow(
        title,
        body,
        tag: urgent ? 'budget-urgent' : 'budget',
      );
      return;
    }
    try {
      await init();
      await _plugin.show(
        id: urgent ? 1001 : 1002,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _alerts.id,
            _alerts.name,
            channelDescription: _alerts.description,
            importance: Importance.max,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
            color: urgent ? const Color(0xFFE53935) : const Color(0xFFFF6B35),
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            interruptionLevel: urgent
                ? InterruptionLevel.timeSensitive
                : InterruptionLevel.active,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }
}
