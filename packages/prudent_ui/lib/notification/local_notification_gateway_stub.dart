import 'local_notification_gateway.dart';
import 'reminder_notification.dart';

/// The gateway where there is no dart:io — the web. Browsers do not schedule notifications for
/// a time the page is closed, so none is claimed; the in-app reminder centre is the path there.
LocalNotificationGateway createLocalNotificationGateway() => const _UnsupportedGateway();

class _UnsupportedGateway implements LocalNotificationGateway {
  const _UnsupportedGateway();

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
