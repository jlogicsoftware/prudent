import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:zen_core/zen_core.dart';

/// How a ledger refusal reaches a caller: a [ZenError] shaped as the server's refusal arrives
/// through the transport, so a screen reads it the same way from either repository.
///
/// The server's `PrudentException` carries a stable `code` (`invalid`, `not_found`, `conflict`) that
/// the shared screens branch on with `failureCode(error)` (ADR-108), an HTTP status, and an English
/// message. A local [Refusal] carries the status and the phase-0 rule it enforces; this turns it into
/// the matching [ZenError] with `internalData` holding `code`, `status` and `rule`. The message is
/// the server's own wording where a screen compares it (the account number taken).
abstract final class LedgerErrors {
  /// The [ZenError] for [refusal].
  static ZenError of(Refusal refusal) {
    final data = <String, dynamic>{
      'code': switch (refusal.status) {
        404 => 'not_found',
        409 => 'conflict',
        _ => 'invalid',
      },
      'status': refusal.status,
      'rule': refusal.rule,
    };
    return switch (refusal.status) {
      404 => ZenNotFoundError(refusal.message, internalData: data),
      409 => ZenConflictError(refusal.message, internalData: data),
      _ => ZenValidationError(refusal.message, internalData: data),
    };
  }

  /// The HTTP status the server answers the same refusal with, or null when [error] is not a ledger
  /// refusal — the store's own errors (a record in conflict, a storage failure) carry none, so they
  /// are never mistaken for a rule the person broke.
  static int? statusOf(ZenError error) => switch (error.internalData?['status']) {
    final int status => status,
    _ => null,
  };
}
