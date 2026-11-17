import 'parity_backend.dart';
import 'parity_clock.dart';
import 'parity_scenario.dart';

/// Runs a [ParityScenario] through two backends and compares every step's answer exactly
/// (ADR-107).
///
/// Exactly means: the same keys, the same strings character for character, the same figures as
/// decimal text — `"1234"` and `"1235"` differ, and so do `"1234"` and `1234`. There is no
/// tolerance anywhere and no field is skipped; what a backend must not compare (an id, a timestamp)
/// it leaves out of its observation, and both backends then leave it out.
///
/// A scenario may name dates relative to today in a zone (`@today(Europe/Warsaw)+3`, [ParityClock]);
/// they are resolved once, before either backend runs the step.
///
/// A step that throws on either side (an unknown operation, a broken binding, a transport failure)
/// ends the scenario as a failure with the error named — a step that could not run is never
/// counted as a match.
final class ParityEngine {
  const ParityEngine({required this.server, required this.local});

  final ParityBackend server;
  final ParityBackend local;

  /// Runs [scenario] once, or twice when a time zone's midnight passed during the first run: the
  /// server reads the wall clock and Local reads the instant the scenario was pinned at, so a
  /// scenario that straddled a midnight compared two different days (see [ParityClock]). A second
  /// run that straddles one too is a failure, not a pass.
  Future<ParityReport> run(ParityScenario scenario) async {
    for (var attempt = 1; ; attempt++) {
      final clock = ParityClock();
      final report = await _runOnce(scenario, clock);
      if (!clock.crossedMidnight) return report;
      if (attempt == 2) {
        throw ParityStepFailed(
          scenario.name,
          'a time zone the scenario names passed midnight during two runs in a row, so server and '
          'local were never compared on the same day; run it again.',
        );
      }
    }
  }

  Future<ParityReport> _runOnce(ParityScenario scenario, ParityClock clock) async {
    server.clock = clock;
    local.clock = clock;
    final differences = <ParityDifference>[];
    final serverBindings = ParityBindings();
    final localBindings = ParityBindings();
    await server.open(scenario.name);
    try {
      await local.open(scenario.name);
      try {
        for (var index = 0; index < scenario.steps.length; index++) {
          final step = scenario.steps[index];
          final where = 'step ${index + 1} (${step.op})';
          final input = clock.expand(step.input)! as Map<String, Object?>;
          final serverResult = await _runOne(server, step, input, serverBindings);
          final localResult = await _runOne(local, step, input, localBindings);
          _checkFigures(server.name, where, serverResult.observation);
          _checkFigures(local.name, where, localResult.observation);

          final expected = step.outcome;
          final serverOutcome = serverResult.observation['outcome'];
          if (expected != null && serverOutcome != expected) {
            differences.add(
              ParityDifference(
                where,
                'outcome (the scenario says the server must answer "$expected")',
                serverOutcome,
                expected,
              ),
            );
          }
          _compare(where, '', serverResult.observation, localResult.observation, differences);

          final bindAs = step.bindAs;
          if (bindAs != null) {
            final serverId = serverResult.createdId;
            final localId = localResult.createdId;
            if (serverId == null || localId == null) {
              throw ParityStepFailed(
                where,
                '"as": "$bindAs" needs an id from both backends; '
                'server gave ${serverId ?? 'none'}, local gave ${localId ?? 'none'}.',
              );
            }
            serverBindings.bind(bindAs, serverId);
            localBindings.bind(bindAs, localId);
          }
        }
      } finally {
        await local.close();
      }
    } finally {
      await server.close();
    }
    return ParityReport(scenario, differences);
  }

  static Future<StepResult> _runOne(
    ParityBackend backend,
    ParityStep step,
    Map<String, Object?> input,
    ParityBindings bindings,
  ) {
    final op = backend.ops[step.op];
    if (op == null) throw UnknownParityOp(backend.name, step.op);
    return op(input, bindings);
  }

  static void _checkFigures(String backend, String where, Object? value) {
    if (value is double) {
      throw ParityStepFailed(
        where,
        'the $backend observation holds the double $value; a figure is a string of minor units.',
      );
    }
    if (value is Map) {
      for (final entry in value.values) {
        _checkFigures(backend, where, entry);
      }
    } else if (value is List) {
      for (final entry in value) {
        _checkFigures(backend, where, entry);
      }
    }
  }

  static void _compare(
    String where,
    String path,
    Object? server,
    Object? local,
    List<ParityDifference> out,
  ) {
    if (server is Map && local is Map) {
      final keys = {...server.keys, ...local.keys}.toList()..sort();
      for (final key in keys) {
        final childPath = path.isEmpty ? '$key' : '$path.$key';
        if (!server.containsKey(key) || !local.containsKey(key)) {
          out.add(
            ParityDifference(
              where,
              childPath,
              server.containsKey(key) ? server[key] : const _Missing(),
              local.containsKey(key) ? local[key] : const _Missing(),
            ),
          );
        } else {
          _compare(where, childPath, server[key], local[key], out);
        }
      }
    } else if (server is List && local is List) {
      if (server.length != local.length) {
        out.add(ParityDifference(where, '$path (length)', server.length, local.length));
        return;
      }
      for (var i = 0; i < server.length; i++) {
        _compare(where, '$path[$i]', server[i], local[i], out);
      }
    } else if (server.runtimeType != local.runtimeType || server != local) {
      out.add(ParityDifference(where, path, server, local));
    }
  }
}

/// The outcome of one scenario.
final class ParityReport {
  ParityReport(this.scenario, this.differences);

  final ParityScenario scenario;
  final List<ParityDifference> differences;

  bool get matches => differences.isEmpty;

  /// Every difference, one per line, naming the step, the field and both values.
  String describe() {
    if (matches) return '${scenario.name}: server and local agree on every step.';
    return [
      '${scenario.name}: ${differences.length} difference(s) between server and local:',
      for (final difference in differences) '  $difference',
    ].join('\n');
  }
}

/// One field on which the two backends disagree.
final class ParityDifference {
  const ParityDifference(this.step, this.path, this.server, this.local);

  final String step;
  final String path;
  final Object? server;
  final Object? local;

  @override
  String toString() => '$step: $path — server ${_show(server)}, local ${_show(local)}';

  static String _show(Object? value) => value is String ? '"$value"' : '$value';
}

/// A step could not be run or compared at all.
final class ParityStepFailed implements Exception {
  const ParityStepFailed(this.step, this.reason);

  final String step;
  final String reason;

  @override
  String toString() => 'Parity $step failed: $reason';
}

/// A key one observation has and the other does not.
final class _Missing {
  const _Missing();

  @override
  String toString() => '(absent)';
}
