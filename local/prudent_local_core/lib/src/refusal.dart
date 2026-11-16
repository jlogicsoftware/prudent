/// A rule's refusal: the local counterpart of the server's `PrudentException`.
///
/// [status] is the HTTP status the server answers the same refusal with (400 invalid, 404 not
/// found, 409 conflict). Locally there is no HTTP, but the status is what the parity suite compares
/// — the server's message text is English prose and not a contract — and it is what tells a screen
/// whether the person typed something wrong or something else changed under them.
///
/// [rule] names the row of the phase-0 inventory (`docs/plans/prudent-local-phase0.md` §0.3) the
/// refusal enforces, for a test and a log line. Like the server, a refusal never carries the value
/// it refused: an account number or a note is personal data.
class Refusal implements Exception {
  const Refusal.invalid(this.rule, this.message) : status = 400;

  const Refusal.notFound(this.rule, this.message) : status = 404;

  const Refusal.conflict(this.rule, this.message) : status = 409;

  final int status;
  final String rule;
  final String message;

  @override
  String toString() => 'Refusal($status, rule $rule): $message';
}
