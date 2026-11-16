import 'dart:developer' as developer;

import 'package:zen_core/zen_core.dart';

import '../failure_code.dart';
import '../l10n/generated/prudent_localizations.dart';

/// The start of the 400 the server sends for a malformed bank account number
/// (`AccountNumbers.normalize`). A 400 can also be an empty name or an unknown currency, so the
/// status alone is not enough to say "not an account number".
const accountNumberInvalidMessage = 'The account number must be';

/// The whole 409 the server sends when another of the user's accounts holds the number
/// (`AccountResource`).
const accountNumberTakenMessage = 'Another of your accounts already has this account number.';

/// Why saving an account failed, in the user's language. The two refusals a form can cause by the
/// bank account number (ADR-090) are told apart by the server's fixed message, because the status
/// code is shared with other refusals; anything else, including a failure that is not a server
/// answer at all, is the generic "not saved". The server's English message is never shown.
///
/// A failure that is not a [ZenError] is logged by its type only: its text could carry what the
/// user typed.
String accountSaveErrorText(PrudentLocalizations t, Object error) {
  if (error is! ZenError) {
    developer.log(
      'Saving an account failed (${error.runtimeType}).',
      name: 'prudent',
      level: 1000,
    );
    return t.accountSaveFailed;
  }
  final code = failureCode(error);
  final message = error.message;
  if (code == 'invalid' && message.startsWith(accountNumberInvalidMessage)) {
    return t.accountNumberInvalid;
  }
  if (code == 'conflict' && message == accountNumberTakenMessage) {
    return t.accountNumberTaken;
  }
  return t.accountSaveFailed;
}
