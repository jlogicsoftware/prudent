import 'package:flutter/services.dart';

/// Upper-cases what is typed, for a field whose value is a code (an ISO 4217 currency).
///
/// `ZenTextField` has no text-capitalization option, and a capitalization hint is only a keyboard
/// suggestion that a physical keyboard ignores; this makes the field show what will be saved.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
