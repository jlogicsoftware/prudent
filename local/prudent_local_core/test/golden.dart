import 'dart:convert';
import 'dart:io';

import 'package:prudent_local_core/prudent_local_core.dart';

/// Reads a golden vector file written by the server's `GoldenVectorsTest` (ADR-107). `dart test`
/// runs with the package root as the working directory.
Map<String, Object?> golden(String name) {
  final file = File('test/golden/$name');
  if (!file.existsSync()) {
    throw StateError(
      '${file.path} is missing. Generate it from the server: (cd server && ./mvnw -B test '
      '-Dtest=GoldenVectorsTest -Dprudent.golden.write=true)',
    );
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

/// The cases of a golden file, each a JSON object.
List<Map<String, Object?>> cases(Map<String, Object?> file, String key) =>
    (file[key]! as List<Object?>).cast<Map<String, Object?>>();

/// A readable name for an input that may be invisible: every code unit outside printable ASCII is
/// shown as `\uXXXX`.
String show(Object? input) {
  if (input is! String) return '$input';
  final out = StringBuffer('"');
  for (final unit in input.codeUnits) {
    if (unit >= 0x20 && unit < 0x7f) {
      out.writeCharCode(unit);
    } else {
      out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    }
  }
  out.write('"');
  final text = out.toString();
  return text.length > 80 ? '${text.substring(0, 60)}..." (${input.length} units)' : text;
}

/// A rule's answer in the golden files' shape: `{"ok": value}`, `{"refused": status}` for a
/// [Refusal] (the server's `PrudentException`), or `{"error": kind}` for an error type [errors]
/// names (the server's other exceptions). Anything else is rethrown: an unexpected failure is a
/// test failure, not a value to compare.
Map<String, Object?> attempt(Object? Function() rule, {Map<Type, String> errors = const {}}) {
  try {
    return {'ok': rule()};
  } on Refusal catch (refusal) {
    return {'refused': refusal.status};
  } on Object catch (error) {
    final kind = errors[error.runtimeType];
    if (kind != null) return {'error': kind};
    rethrow;
  }
}
