import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The synthetic Erste statement of the server's `ImportTestSupport.Erste`, rebuilt in Dart for the
/// two golden cases too large to write into a file (ADR-088: synthetic only). The golden file
/// carries the SHA-256 and length of the bytes the server read, and [rebuild] refuses to return
/// anything else, so a drift between this and the Java builder fails loudly.
abstract final class ErsteStatements {
  static List<String> summary() => [
    '2026-11-14',
    '01-01-2026',
    "'00 0000 0000 0000 0000 0000 0001",
    'JAN TESTOWY UL. PRZYKŁADOWA 1/2 00-000 TESTOWO',
    'PLN',
    '0,00',
    '50,00',
    '999',
    '',
  ];

  static List<String> tx(
    String booking,
    String date,
    String description,
    String counterparty,
    String account,
    String amount,
    int sequence, {
    String balance = '10,00',
  }) => [booking, date, description, counterparty, account, amount, balance, '$sequence', ''];

  static List<String> card(
    String booking,
    String date,
    String merchant,
    String amount,
    int sequence, {
    String balance = '10,00',
  }) {
    final embedded = amount.replaceAll('-', '').replaceAll(',', '.');
    return tx(
      booking,
      date,
      'DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ $embedded PLN $merchant',
      '',
      '',
      amount,
      sequence,
      balance: balance,
    );
  }

  /// One CSV line: a field is quoted exactly when it holds a comma or a quote, as the bank does.
  static String line(List<String> fields) => fields
      .map((f) => f.contains(',') || f.contains('"') ? '"${f.replaceAll('"', '""')}"' : f)
      .join(',');

  static Uint8List bytes(List<List<String>> rows) =>
      Uint8List.fromList(utf8.encode('${rows.map(line).join('\n')}\n'));

  /// The summary row and [count] one-zloty card payments on distinct sequence numbers.
  static Uint8List manyCards(int count) => bytes([
    summary(),
    for (var i = 1; i <= count; i++) card('06-03-2026', '06-03-2026', 'SKLEP TESTOWY $i', '-1,00', i),
  ]);

  /// The bytes of a golden case: base64, or a recipe checked against the server's digest.
  static Uint8List rebuild(Object? content) {
    if (content is String) return base64.decode(content);
    final recipe = content! as Map<String, Object?>;
    final Uint8List built = switch (recipe['recipe']) {
      'manyCards' => manyCards(recipe['count']! as int),
      'repeat' => Uint8List(recipe['count']! as int)..fillRange(0, recipe['count']! as int, recipe['byte']! as int),
      final other => throw StateError('no recipe called $other'),
    };
    if (built.length != recipe['length'] || sha256.convert(built).toString() != recipe['sha256']) {
      throw StateError('the rebuilt statement is not the one the server read');
    }
    return built;
  }
}
