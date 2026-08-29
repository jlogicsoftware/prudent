import 'package:fixnum/fixnum.dart';

/// Parses a user-entered decimal amount (e.g. `"12.34"` or `"12,34"`) into an exact `Int64` count
/// of minor units (1234), the wire's money type (proto/prudent/v1/accounts.proto §2.1).
///
/// Deliberately does NOT go through `double`: `0.1 + 0.2 != 0.3` in binary floating point, and an
/// expense tracker sums thousands of values, so the parse itself has to stay in integers. Returns
/// `null` — never a rounded guess — for anything that is not a valid decimal with at most two
/// fraction digits.
Int64? parseMinorUnits(String input) {
  final normalized = input.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;

  final negative = normalized.startsWith('-');
  final unsigned = negative ? normalized.substring(1) : normalized;
  final parts = unsigned.split('.');
  if (parts.isEmpty || parts.length > 2) return null;

  final wholePart = parts[0];
  final fractionPart = parts.length == 2 ? parts[1] : '';
  if (wholePart.isEmpty || fractionPart.length > 2) return null;
  if (!RegExp(r'^\d+$').hasMatch(wholePart)) return null;
  if (fractionPart.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fractionPart)) return null;

  final paddedFraction = fractionPart.padRight(2, '0');
  final whole = Int64.parseInt(wholePart);
  final fraction = Int64.parseInt(paddedFraction);
  final minor = whole * 100 + fraction;
  return negative ? -minor : minor;
}

/// The exact inverse of [parseMinorUnits]'s rounding: minor units back to a two-decimal string,
/// with no `double` on the path either.
String formatMinorUnits(Int64 minor) {
  final negative = minor.isNegative;
  final absValue = negative ? -minor : minor;
  final whole = absValue ~/ 100;
  final fraction = (absValue % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole.$fraction';
}
