import 'refusal.dart';

/// Identifier rules of Prudent Local (finding F-11; ADR-102, ADR-103).
///
/// A Local id is **32 lower-case hexadecimal characters**: a UUID's 16 bytes with no dashes. Ids
/// are compared as **text**, which for that form is the same order as comparing the bytes — the
/// order Postgres sorts a `uuid` column by, and so the server's `id` tie-break in its list routes.
///
/// Who mints an id (the device at random, or a hash of a natural key) is unit 4's (row 3.9 changes
/// meaning, phase-0 §0.3). This class only fixes the form, the order, and how a server id is read
/// in (the privacy-export import, ADR-103).
///
/// Two server routes tie-break with Java's `UUID.compareTo` instead, which compares the two halves
/// as **signed** longs — a different order (`OccurrenceResource.java:302`,
/// `ReminderResource.java:192`). Ids differ between server and Local anyway, so order within one
/// date is never a parity property; `test/golden/ids.json` shows both orders from the JVM, and the
/// test proves text order is the byte order and not Java's.
abstract final class LocalIds {
  static final RegExp _local = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _serverForm = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// Whether [id] is a Local id: exactly 32 lower-case hex characters.
  static bool isValid(String id) => _local.hasMatch(id);

  /// The Local id of a server id, as the server writes one (`UUID.toString()`: lower-case,
  /// 8-4-4-4-12). Anything else is refused (404, as the server's `Ids.parse` answers a malformed
  /// id).
  ///
  /// Java's `UUID.fromString` would also read `1-1-1-1-1`, upper case, a sign or non-ASCII digits
  /// (`ids.json`, `fromString`). Local reads ids only from what the server wrote, so it accepts only
  /// that form: a looser reader would make two spellings of one id two records.
  static String fromServerId(String serverId) {
    if (!_serverForm.hasMatch(serverId)) {
      throw const Refusal.notFound('3.9', 'Not an id the server writes.');
    }
    return serverId.replaceAll('-', '');
  }

  /// The order of two Local ids: text order, which is byte order.
  static int compare(String a, String b) => a.compareTo(b);
}
