/// What the app remembers about having asked for notification permission, across launches.
///
/// The operating system owns the permission itself; this is only the app's record that the prompt
/// has been shown. Without it a user who refused would be prompted again on every launch, and on a
/// system that re-asks (Android lets an app ask twice) the refusal would not stick.
abstract interface class NotificationPermissionMemory {
  /// Whether the user has already been asked, in this or an earlier launch.
  Future<bool> hasAsked();

  /// Records that the user is being asked. Called before the prompt is shown, so an app that is
  /// closed while the prompt is up does not ask again.
  Future<void> markAsked();
}

/// Remembers for the life of the object only. The default for the scheduler, and what tests use.
class InMemoryNotificationPermissionMemory
    implements NotificationPermissionMemory {
  bool _asked = false;

  @override
  Future<bool> hasAsked() async => _asked;

  @override
  Future<void> markAsked() async => _asked = true;
}
