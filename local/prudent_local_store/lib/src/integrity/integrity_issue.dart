import 'package:meta/meta.dart';
import 'package:zen_core/zen_core.dart';

/// A rule across records that the store, as it stands now, breaks — found after a merge (or a local
/// write) by an `IntegrityCheck`, and shown to the person beside the store's own conflicts.
///
/// It is data, not words: the Local app (unit 9) turns each into a `zen_ui_store` `ZenIssue`, with
/// a title, a description and button labels chosen by [code] in the person's language — `id` maps to
/// `ZenIssue.id`, each [IntegrityAction] to a `ZenIssueAction` whose `run` it already has the shape
/// of. Nothing about it is fixed silently (ADR-102): it leaves the list only when a check no longer
/// finds it, after the person acted on this device or another.
@immutable
final class IntegrityIssue {
  /// Stable for as long as the problem is the same one: the [code] and the records it is about, never
  /// an amount, a name or an account number, so it can be logged.
  final String id;

  /// What rule is broken, as a dotted code (`reference.record_account_missing`); the app's words are
  /// chosen by it.
  final String code;

  /// The collection of the record the issue is about.
  final String collection;

  /// The record the issue is about.
  final String recordId;

  /// Ids and codes the words may name (`accountId`, `currency`) — never free text from a record.
  final Map<String, String> facts;

  /// What the person can do about it; never empty.
  final List<IntegrityAction> actions;

  /// Creates an issue; a check builds these.
  IntegrityIssue({
    required this.code,
    required this.collection,
    required this.recordId,
    this.facts = const {},
    required this.actions,
    String? key,
  }) : id = '$code:$collection/${key ?? recordId}' {
    if (actions.isEmpty) {
      throw ArgumentError.value(
        actions,
        'actions',
        'an issue without an action leaves nothing to do',
      );
    }
  }

  @override
  String toString() => 'IntegrityIssue($id, $facts, ${actions.map((a) => a.code).toList()})';
}

/// One thing the person can do about an [IntegrityIssue].
///
/// Most actions take no input. One that needs the person to pick something names the candidates in
/// [choices] (record ids; the app shows them by name), and one that needs a word from them — a name
/// for a record being re-created — sets [needsText]; the app asks before calling [run] with it.
@immutable
final class IntegrityAction {
  /// What the action does, as a code the app words (`delete_record`, `move_to_account`).
  final String code;

  /// The ids the person chooses among, or null when the action takes no choice.
  final List<String>? choices;

  /// Whether the action needs a short text from the person.
  final bool needsText;

  final Future<ZenResult<Object?>> Function(String? input) _run;

  /// An action that needs nothing from the person.
  IntegrityAction.now(this.code, Future<ZenResult<Object?>> Function() run)
    : choices = null,
      needsText = false,
      _run = ((_) => run());

  /// An action that applies one of [choices], which must not be empty.
  IntegrityAction.choose(
    this.code,
    List<String> choices,
    Future<ZenResult<Object?>> Function(String choice) run,
  ) : choices = List.unmodifiable(choices),
      needsText = false,
      _run = ((input) => run(input!)) {
    if (choices.isEmpty) throw ArgumentError.value(choices, 'choices', 'offers nothing to choose');
  }

  /// An action that needs a short text from the person.
  IntegrityAction.withText(this.code, Future<ZenResult<Object?>> Function(String text) run)
    : choices = null,
      needsText = true,
      _run = ((input) => run(input!));

  /// Runs the action. [input] is one of [choices], or the person's text when [needsText], and absent
  /// otherwise; anything else is refused without writing.
  Future<ZenResult<Object?>> run([String? input]) {
    final choices = this.choices;
    if (choices != null && !choices.contains(input)) {
      return Future.value(ZenResult.err(ZenValidationError('"$input" is not one of the choices.')));
    }
    if (needsText && (input == null || input.trim().isEmpty)) {
      return Future.value(ZenResult.err(const ZenValidationError('This action needs a text.')));
    }
    if (choices == null && !needsText && input != null) {
      return Future.value(ZenResult.err(const ZenValidationError('This action takes no input.')));
    }
    return _run(input);
  }
}
