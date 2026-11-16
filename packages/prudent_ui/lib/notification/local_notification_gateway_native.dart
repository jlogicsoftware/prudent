import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'local_notification_gateway.dart';
import 'reminder_notification.dart';

/// The gateway where there is a dart:io: the platform plugin on Android, iOS, macOS and Windows,
/// and "unsupported" on Linux, which the plugin cannot schedule on.
LocalNotificationGateway createLocalNotificationGateway() =>
    Platform.isLinux ? _UnsupportedGateway() : _PluginGateway();

class _UnsupportedGateway implements LocalNotificationGateway {
  @override
  bool get isSupported => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule(ReminderNotification notification) =>
      throw UnsupportedError('Local notifications cannot be scheduled on this platform');

  @override
  Future<Set<int>> pendingIds() async => const {};

  @override
  Future<void> cancel(int id) => throw UnsupportedError('Local notifications cannot be cancelled on this platform');
}

class _PluginGateway implements LocalNotificationGateway {
  static const _channelId = 'planned_reminders';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initialized;

  @override
  bool get isSupported => true;

  /// Initialises once, and never asks for permission: every `request*Permission` flag is off, so
  /// the prompt appears only when [requestPermission] is called — when there is a reminder to
  /// deliver — and not on first launch.
  Future<void> _initialize() => _initialized ??= _doInitialize();

  Future<void> _doInitialize() async {
    tz_data.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));

    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
        macOS: darwin,
        windows: WindowsInitializationSettings(
          appName: 'Prudent',
          appUserModelId: 'com.jlogicsoftware.prudent',
          guid: '446fe5b1-b297-450e-9e68-7c988afcefcd',
        ),
      ),
    );
  }

  @override
  Future<bool> hasPermission() async {
    await _initialize();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return (await ios?.checkPermissions())?.isEnabled ?? false;
    }
    if (Platform.isMacOS) {
      final macos = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      return (await macos?.checkPermissions())?.isEnabled ?? false;
    }
    // Windows shows a toast to any app that asks; there is no application-level grant to read.
    return true;
  }

  @override
  Future<bool> requestPermission() async {
    await _initialize();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    if (Platform.isMacOS) {
      final macos = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      return await macos?.requestPermissions(alert: true, sound: true) ?? false;
    }
    return true;
  }

  @override
  Future<void> schedule(ReminderNotification notification) async {
    await _initialize();
    await _plugin.zonedSchedule(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      scheduledDate: tz.TZDateTime.from(notification.fireAt, tz.local),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          notification.channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      ),
      // A reminder is for a day, not a minute, so the inexact alarm is the right one: it needs no
      // "alarms & reminders" permission, which Android 14 grants only on request.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: notification.occurrenceId,
    );
  }

  @override
  Future<Set<int>> pendingIds() async {
    await _initialize();
    final pending = await _plugin.pendingNotificationRequests();
    return {for (final request in pending) request.id};
  }

  @override
  Future<void> cancel(int id) async {
    await _initialize();
    await _plugin.cancel(id: id);
  }
}
