import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';

/// A precondition on one write, run by jZen's store **inside** the write's serialized turn against
/// the record as it stands then — null when it is absent or deleted (jZenDev/jZen#251, consumed from
/// jZen PR #254). An error it returns refuses the write, and in a batch the whole batch.
///
/// A rule checked with a read before the write is checked outside that turn: a sync's `receive`
/// already queued runs between the two, and the write would then bring back a record another device
/// just deleted, or write a value over an edit that sync merged in. Whatever a write was decided
/// against goes here instead.
typedef WriteExpect<T> = ZenError? Function(T? current);

/// The preconditions Prudent Local's writes carry (ADR-115).
abstract final class WriteExpects {
  /// The record must still be exactly [basis], the version the write was decided against: the
  /// same serialised bytes, which is what the store merges by. A [basis] of null means it must
  /// still be absent.
  ///
  /// [gone] answers a record deleted since it was read; [changed] one that was edited, created or
  /// replaced. The defaults are the store's own kinds of error; the ledger passes the server's.
  /// [gone] is reached by a put only: on a delete, jZen answers an absent record with its own
  /// [ZenNotFoundError] before any precondition runs, and the caller maps that itself.
  ///
  /// Exact equality, not "the fields this write touches": a write puts a whole message, and the
  /// store counts every field that differs from the stored record as this device's edit — so a field
  /// another device changed in between would be silently written back to the value read, which is a
  /// last writer winning. Refused instead, the person sees the change and decides again.
  static WriteExpect<T> asRead<T extends GeneratedMessage>(
    T? basis, {
    ZenError Function()? gone,
    ZenError Function()? changed,
  }) => (current) {
    if (current == null) {
      if (basis == null) return null;
      return gone?.call() ??
          ZenNotFoundError('${_idOf(basis)} was deleted on another device before this was saved.');
    }
    if (basis != null && _sameBytes(current.writeToBuffer(), basis.writeToBuffer())) return null;
    return changed?.call() ??
        ZenConflictError(
          '${_idOf(current)} changed on another device before this was saved; look at it again.',
        );
  };

  static String _idOf(GeneratedMessage m) => 'Record "${m.getField(1)}"';

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
