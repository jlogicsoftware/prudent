import 'package:prudent_local_store/prudent_local_store.dart' show MoveInRefusal, MoveInRule;

import '../l10n/generated/local_localizations.dart';

/// The sentence that says why a move was refused (unit 10b, ADR-123), in the person's language.
/// One per [MoveInRule]: a new rule without a sentence fails to compile here.
String moveInReason(LocalLocalizations t, MoveInRule rule) => switch (rule) {
  MoveInRule.unreadable => t.moveInUnreadable,
  MoveInRule.formatVersion => t.moveInFormatVersion,
  MoveInRule.storeNotEmpty => t.moveInStoreNotEmpty,
  MoveInRule.malformedId => t.moveInMalformedId,
  MoveInRule.duplicateId => t.moveInDuplicateId,
  MoveInRule.unknownReference => t.moveInUnknownReference,
  MoveInRule.currencyNotHeld => t.moveInCurrencyNotHeld,
  MoveInRule.transferBroken => t.moveInTransferBroken,
  MoveInRule.twoDefaults => t.moveInTwoDefaults,
  MoveInRule.occurrenceUnpaired => t.moveInOccurrenceUnpaired,
  MoveInRule.planZone => t.moveInPlanZone,
  MoveInRule.importKey => t.moveInImportKey,
  MoveInRule.invalidValue => t.moveInInvalidValue,
  MoveInRule.balanceMismatch => t.moveInBalanceMismatch,
  MoveInRule.changedMeanwhile => t.moveInChangedMeanwhile,
  MoveInRule.storeFailed => t.moveInStoreFailed,
};

/// Where in the file the refusal was found, as data: the rule's code and its facts (ids, currency
/// codes, counts, minor-unit amounts — never a title, payee or note; see [MoveInRule]). Not
/// translated, because it names fields of the file, which are the same in every language; it lets
/// the person, or whoever helps them, find the row.
String moveInDetails(MoveInRefusal refusal) => [
  refusal.rule.code,
  for (final MapEntry(:key, :value) in refusal.facts.entries) '$key=$value',
].join(', ');
