import 'package:flutter/foundation.dart';

/// One local notification the device is asked to show: what, and when.
///
/// [id] is derived from the occurrence ([reminderNotificationId]), so scheduling the same
/// occurrence twice replaces its notification rather than adding a second one — the property the
/// reconciliation task builds on.
@immutable
class ReminderNotification {
  const ReminderNotification({
    required this.id,
    required this.occurrenceId,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.channelName,
  });

  final int id;
  final String occurrenceId;

  /// The device's wall-clock moment it should appear: the reminder's civil date at
  /// [reminderNotificationHour], in whatever zone the device is in when it fires.
  final DateTime fireAt;

  final String title;
  final String body;

  /// The name of the Android notification channel, which the user sees in system settings.
  final String channelName;

  @override
  bool operator ==(Object other) =>
      other is ReminderNotification &&
      other.id == id &&
      other.occurrenceId == occurrenceId &&
      other.fireAt == fireAt &&
      other.title == title &&
      other.body == body &&
      other.channelName == channelName;

  @override
  int get hashCode => Object.hash(id, occurrenceId, fireAt, title, body, channelName);
}
