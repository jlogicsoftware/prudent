/// What one step answered on one backend: an observation to compare, and the backend's own id of
/// what the step created (if it created anything and the step binds it with `as`).
///
/// An observation is plain JSON: strings, booleans, small integers (a status), lists, maps, null.
/// **Every figure is a string of minor units** ([ParityObservation.figure]); a double is refused by
/// the engine, because a comparison that goes through a double is not to the cent.
final class StepResult {
  const StepResult(this.observation, {this.createdId});

  final Map<String, Object?> observation;
  final String? createdId;
}

/// The observation vocabulary both backends share, so that "accepted" and "refused" are spelled
/// once.
abstract final class ParityObservation {
  /// The step was accepted; [fields] are what the answer says, minus anything only one side has
  /// (ids, timestamps).
  static Map<String, Object?> accepted([Map<String, Object?> fields = const {}]) => {
    'outcome': 'accepted',
    ...fields,
  };

  /// The step was refused with [status] (the server's HTTP status; locally the
  /// `Refusal.status`). Message texts are not compared: they are prose, not a contract.
  static Map<String, Object?> refused(int status) => {'outcome': 'refused', 'status': status};

  /// A figure, exactly: the decimal text of a count of minor units.
  static String figure(int minorUnits) => minorUnits.toString();
}

/// Names bound by `as`, resolved to one backend's ids. Each backend has its own.
final class ParityBindings {
  final Map<String, String> _ids = {};

  void bind(String name, String id) {
    if (_ids.containsKey(name)) throw StateError('"$name" is bound twice in one scenario.');
    _ids[name] = id;
  }

  /// [reference] is `"$name"`; answers the id bound to `name`, and fails loudly for a name nothing
  /// bound — a typo in a scenario must not become a request with an empty id.
  String resolve(Object? reference) {
    if (reference is! String || !reference.startsWith(r'$')) {
      throw FormatException('Expected a "\$name" reference, got $reference.');
    }
    final id = _ids[reference.substring(1)];
    if (id == null) throw StateError('Nothing is bound to $reference (yet).');
    return id;
  }
}

/// Runs one step on a backend.
typedef ParityOp = Future<StepResult> Function(Map<String, Object?> input, ParityBindings bindings);

/// One side of the comparison — the real server, or the local code.
///
/// A backend is a table of operations. Units 4–8 add operations to both backends' tables and
/// scenarios that use them; the engine never changes. An operation one backend lacks is a failure
/// of the scenario ([UnknownParityOp]), never a skipped step.
abstract class ParityBackend {
  /// `server` or `local`, for the report.
  String get name;

  /// The operations this backend can run, by name.
  Map<String, ParityOp> get ops;

  /// Called once before a scenario: a fresh, empty world for it (a new user on the server, a new
  /// in-memory model locally), so scenarios never see each other's data.
  Future<void> open(String scenarioName);

  /// Called once after a scenario, whatever happened.
  Future<void> close();
}

/// A scenario used an operation a backend has not registered.
final class UnknownParityOp implements Exception {
  const UnknownParityOp(this.backend, this.op);

  final String backend;
  final String op;

  @override
  String toString() => 'The $backend backend has no parity operation "$op".';
}
