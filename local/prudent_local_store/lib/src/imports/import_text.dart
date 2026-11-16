import 'dart:convert';
import 'dart:typed_data';

/// A statement's text as a session row stores it: the exact UTF-8 bytes (ADR-114).
///
/// Dart's UTF-8 decoder drops a byte-order mark at the start of what it decodes, and the protobuf
/// runtime decodes every `string` field with it, so a text that begins with U+FEFF does not survive
/// a store round trip as a `string`. The server keeps it, and fingerprints it (ADR-091): a BLIK
/// counterparty of only U+FEFF is not an empty one there. So the row keeps bytes, and [read] puts
/// back the one mark the decoder takes.
abstract final class ImportText {
  static const _bom = [0xEF, 0xBB, 0xBF];

  static Uint8List write(String text) => utf8.encode(text);

  static String read(List<int> bytes) {
    final decoded = utf8.decode(bytes);
    final startsWithMark =
        bytes.length >= 3 && bytes[0] == _bom[0] && bytes[1] == _bom[1] && bytes[2] == _bom[2];
    return startsWithMark ? '﻿$decoded' : decoded;
  }
}
