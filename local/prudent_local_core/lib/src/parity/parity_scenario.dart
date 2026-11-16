import 'dart:convert';

/// One parity scenario: data, not code (ADR-107).
///
/// A scenario is a JSON file in `local/prudent_local_core/parity/scenarios/`. It names the
/// phase-0 rules it covers and lists steps; each step is an operation (`op`) with an input, run in
/// order through the real server and through the local code, and the two answers are compared
/// exactly. A later unit adds a scenario by adding a file, and an operation by registering it on
/// both backends — the engine, the format and the comparison do not change.
///
/// ```json
/// {
///   "name": "multi_currency",
///   "description": "...",
///   "rules": ["3.1", "3.3"],
///   "steps": [
///     {"op": "account.create", "as": "wallet", "outcome": "accepted",
///      "input": {"name": "Wallet", "type": "ACCOUNT_TYPE_CASH",
///                "balances": [{"currency": "PLN", "amountMinor": "10000"}]}},
///     {"op": "record.create", "input": {"account": "$wallet", ...}}
///   ]
/// }
/// ```
///
/// - `as` binds the id the step created to a name; a later input refers to it as `"$name"`. Each
///   backend keeps its own ids, which never meet: server and Local mint different ones.
/// - `outcome` (optional) is what the **server** must answer, `accepted` or `refused`. It keeps a
///   scenario honest about what it exercises: a setup step the server refuses for a reason nobody
///   meant would otherwise compare equal to a local refusal and prove nothing.
/// - Amounts are strings of minor units, as proto3 JSON carries an int64; a JSON number is a double
///   in most readers, and `9223372036854775807` is not one.
final class ParityScenario {
  ParityScenario({
    required this.name,
    required this.description,
    required this.rules,
    required this.steps,
  });

  final String name;
  final String description;
  final List<String> rules;
  final List<ParityStep> steps;

  /// Reads a scenario, refusing anything the format does not define: an unknown key is a typo that
  /// would otherwise silently leave a step without the assertion its author wrote.
  factory ParityScenario.parse(String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('A parity scenario is a JSON object.');
    }
    _onlyKeys(decoded, const {'name', 'description', 'rules', 'steps'}, 'scenario');
    final name = _string(decoded, 'name', 'scenario');
    final steps = decoded['steps'];
    if (steps is! List<Object?> || steps.isEmpty) {
      throw FormatException('Scenario "$name" needs a non-empty "steps" list.');
    }
    final rules = decoded['rules'];
    if (rules is! List<Object?> || rules.isEmpty || rules.any((rule) => rule is! String)) {
      throw FormatException('Scenario "$name" needs "rules": the phase-0 rows it covers.');
    }
    return ParityScenario(
      name: name,
      description: _string(decoded, 'description', 'scenario "$name"'),
      rules: rules.cast<String>(),
      steps: [
        for (var i = 0; i < steps.length; i++) ParityStep._parse(steps[i], '$name step ${i + 1}'),
      ],
    );
  }
}

/// One step of a [ParityScenario].
final class ParityStep {
  ParityStep({required this.op, required this.input, this.bindAs, this.outcome});

  final String op;
  final Map<String, Object?> input;
  final String? bindAs;
  final String? outcome;

  static ParityStep _parse(Object? json, String where) {
    if (json is! Map<String, Object?>) throw FormatException('$where is not a JSON object.');
    _onlyKeys(json, const {'op', 'as', 'input', 'outcome', 'comment'}, where);
    final input = json['input'] ?? const <String, Object?>{};
    if (input is! Map<String, Object?>) throw FormatException('$where: "input" is not an object.');
    final outcome = json['outcome'];
    if (outcome != null && outcome != 'accepted' && outcome != 'refused') {
      throw FormatException('$where: "outcome" is "accepted" or "refused", not "$outcome".');
    }
    final bindAs = json['as'];
    if (bindAs != null && bindAs is! String) throw FormatException('$where: "as" is a name.');
    return ParityStep(
      op: _string(json, 'op', where),
      input: input,
      bindAs: bindAs as String?,
      outcome: outcome as String?,
    );
  }
}

String _string(Map<String, Object?> json, String key, String where) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw FormatException('$where needs "$key".');
  return value;
}

void _onlyKeys(Map<String, Object?> json, Set<String> allowed, String where) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('$where has unknown keys $unknown; allowed: ${allowed.toList()}.');
  }
}
