import 'package:prudent_ui/notification/local_notification_gateway.dart';
import 'package:prudent_ui/notification/reminder_notification.dart';

/// A platform with no notification scheduler, for widget tests: the test host has no plugin, and
/// device notifications are plan unit 6b's.
final class UnsupportedGatewayForTests implements LocalNotificationGateway {
  const UnsupportedGatewayForTests();

  @override
  bool get isSupported => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule(ReminderNotification notification) =>
      throw StateError('nothing is scheduled on an unsupported platform');

  @override
  Future<Set<int>> pendingIds() async => const {};

  @override
  Future<void> cancel(int id) async {}
}
