import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:prudent_local_core/prudent_local_core.dart';

/// Record ids derived from natural keys (ADR-102, "ids from natural keys").
///
/// Where the server holds a unique index on a natural key, two devices that make "the same" thing
/// must write the *same* record, so that the uniqueness rule becomes a same-record conflict the store
/// shows instead of two rows nobody can tell apart. Every id here is
/// `SHA-256(domain ‖ kind ‖ components)` cut to 128 bits and written as 32 lower-case hex characters,
/// the form of every Local id (`LocalIds`, ADR-107), so derived and random ids sort and compare alike.
///
/// **The encoding is frozen.** Two devices on two app versions must derive the same id from the same
/// key, so a change here splits every derived record in two. `derived_ids_test` pins one vector per
/// kind. Each component is length-prefixed, so `("ab", "c")` and `("a", "bc")` never collide.
///
/// **What enters an id.** Only random ids, a currency code, a month, a date, a fingerprint (itself a
/// digest) and fixed words — never an amount, a title, a payee or an account number. On CloudKit a
/// record's name was `<collection>:<id>` in plaintext, so an id derived from a budget slot would show
/// Apple which months and currencies have one (ADR-100 T7). jZenDev/jZen#236 hashes record names with
/// an HMAC; the Local app consumes it when it wires CloudKit (unit 9).
abstract final class DerivedIds {
  static const String _domain = 'prudent-local/derived-id/v1';

  /// The settings record: one per person (`init.sql:147`).
  static const String settings = 'settings';

  /// One opening amount per account and currency (`init.sql:69`).
  static String accountCurrency(String accountId, String currency) =>
      _derive('account_currency', [_id(accountId), _currency(currency)]);

  /// One budget per category, month and currency (`budgets.sql:29`).
  static String budget(String categoryId, String month, String currency) =>
      _derive('budget', [_id(categoryId), _month(month), _currency(currency)]);

  /// One occurrence state per plan and date (`plan_occurrences.sql:27`).
  static String occurrence(String planId, String date) =>
      _derive('occurrence', [_id(planId), _date(date)]);

  /// The one record that confirms an occurrence (`record_plan_link.sql:29`).
  static String confirmation(String occurrenceId) => _derive('confirm', [_id(occurrenceId)]);

  /// One record per account, import fingerprint and occurrence (`import_fingerprints.sql:59`), so two
  /// devices that import one statement end with each row once (unit 8b).
  static String imported(String accountId, String fingerprint, int occurrence) {
    if (fingerprint.isEmpty) throw ArgumentError.value(fingerprint, 'fingerprint', 'is empty');
    if (occurrence < 1) throw ArgumentError.value(occurrence, 'occurrence', 'starts at 1');
    return _derive('import', [_id(accountId), fingerprint, '$occurrence']);
  }

  /// A starter category, seeded only by "Start fresh on this device", never by "Join"
  /// (`NewUserSetup.java:88`), so two devices that both start fresh do not double the list.
  static String starterCategory(String key) {
    if (key.isEmpty) throw ArgumentError.value(key, 'key', 'is empty');
    return _derive('starter', [key]);
  }

  /// The id of one of a transfer's two leg `Record`s, which exist only on the wire (ADR-102: a
  /// transfer is one store record). Stable, so a screen can address a leg across reads.
  static String transferLeg(String transferId, {required bool source}) =>
      _derive('transfer_leg', [_id(transferId), source ? 'source' : 'destination']);

  static String _derive(String kind, List<String> components) {
    final bytes = BytesBuilder(copy: false)
      ..add(_field(_domain))
      ..add(_field(kind));
    for (final component in components) {
      bytes.add(_field(component));
    }
    return sha256.convert(bytes.takeBytes()).toString().substring(0, 32);
  }

  static List<int> _field(String text) {
    final utf = utf8.encode(text);
    final length = ByteData(4)..setUint32(0, utf.length);
    return [...length.buffer.asUint8List(), ...utf];
  }

  // Components are refused unless already canonical, so one key can never be spelled two ways and
  // derive two ids (`a1…` and `A1…`, `pln` and `PLN`, `2026-1` and `2026-01`).
  static String _id(String id) {
    if (!LocalIds.isValid(id)) throw ArgumentError.value(id, 'id', 'is not a local id');
    return id;
  }

  static String _currency(String code) {
    if (!Currencies.isValid(code) || Currencies.normalize(code) != code) {
      throw ArgumentError.value(code, 'currency', 'is not a normalised ISO-4217 code');
    }
    return code;
  }

  static String _month(String month) {
    if (CivilMonth.tryParse(month)?.toString() != month) {
      throw ArgumentError.value(month, 'month', 'is not YYYY-MM');
    }
    return month;
  }

  static String _date(String date) {
    if (CivilDate.tryParse(date)?.toString() != date) {
      throw ArgumentError.value(date, 'date', 'is not YYYY-MM-DD');
    }
    return date;
  }
}
