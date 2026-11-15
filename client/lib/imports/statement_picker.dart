import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'statement_format.dart';

/// A statement the user chose: its file name (the user's own, shown back to them) and its bytes.
class PickedStatement {
  const PickedStatement({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// The file is larger than the server accepts; nothing was read.
class StatementTooLarge implements Exception {
  const StatementTooLarge();

  @override
  String toString() => 'StatementTooLarge';
}

/// Asks the user for a statement file. Null when they cancel; throws [StatementTooLarge] before
/// reading a file over [maxStatementBytes].
typedef StatementPicker = Future<PickedStatement?> Function();

/// The platform's own file picker (`file_selector`: a sheet on iOS, a panel on macOS and desktop,
/// the document picker on Android, a file input on the web). The app sees only the file the user
/// picks; it holds no storage permission.
Future<PickedStatement?> pickStatementFile() async {
  const csv = XTypeGroup(
    label: 'CSV',
    extensions: <String>['csv'],
    mimeTypes: <String>['text/csv', 'text/comma-separated-values', 'application/csv'],
    uniformTypeIdentifiers: <String>['public.comma-separated-values-text'],
  );
  final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[csv]);
  if (file == null) return null;
  if (await file.length() > maxStatementBytes) throw const StatementTooLarge();
  return PickedStatement(name: file.name, bytes: await file.readAsBytes());
}

/// Overridden in tests with a fake; the app uses [pickStatementFile].
final statementPickerProvider = Provider<StatementPicker>((ref) => pickStatementFile);
