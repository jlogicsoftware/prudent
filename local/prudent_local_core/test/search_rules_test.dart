// The record search and the order of names (ADR-106, phase-0 §0.3 rows 5.49, 5.51, 5.52; findings
// F-09, F-10): SearchRules is held to the server's own expected-behaviour vectors — the files
// `TextRulesTest` runs against the Java code — and its fold to the JVM's table for every code point.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

import 'golden.dart';

/// The server's vector files are read where the server keeps them, never copied: one file, two
/// implementations (`dart test` runs in the package root).
Map<String, Object?> _serverVectors(String name) =>
    jsonDecode(File('../../server/src/test/resources/text-rules/$name').readAsStringSync())
        as Map<String, Object?>;

void main() {
  group('fold', () {
    final changed = <int, int>{
      for (final pair in (golden('fold.json')['changed']! as List<Object?>).cast<List<Object?>>())
        pair[0]! as int: pair[1]! as int,
    };

    test('is Character.toLowerCase(int) for every code point', () {
      expect(changed, isNotEmpty);
      var differences = 0;
      final shown = <String>[];
      for (var cp = 0; cp <= 0x10FFFF; cp++) {
        final java = changed[cp] ?? cp;
        final local = SearchRules.foldCodePoint(cp);
        if (java != local) {
          differences++;
          if (shown.length < 10) {
            shown.add(
              'U+${cp.toRadixString(16)}: Java U+${java.toRadixString(16)}, '
              'Local U+${local.toRadixString(16)}',
            );
          }
        }
      }
      expect(differences, 0, reason: shown.join('\n'));
    });

    test('folds U+0130 to plain i, where Dart\'s own full mapping gives two code points', () {
      expect(SearchRules.fold('\u0130'), 'i');
    });

    test('does not follow Dart\'s own toLowerCase, which an older Unicode answers', () {
      // U+037F GREEK CAPITAL LETTER YOT (Unicode 7.0): the JDK folds it, the Dart VM did not.
      expect(SearchRules.foldCodePoint(0x037F), 0x03F3);
    });
  });

  group('searchTerm (search-vectors.json "term")', () {
    for (final c in cases(_serverVectors('search-vectors.json'), 'term')) {
      test('${c['id']} ${show(c['search'])}', () {
        expect(SearchRules.searchTerm(c['search'] as String?), c['term']);
      });
    }

    test('is not Dart trim: U+FEFF, U+0085 and U+00A0 are kept, a control is removed', () {
      // The four inputs on which the port and Dart's own String.trim()/isEmpty would differ.
      for (final (search, term) in [('﻿', '﻿'), ('\u0085', '\u0085'), (' ', ' '), ('\u0001', '')]) {
        expect(SearchRules.searchTerm(search), term, reason: show(search));
        expect(
          search.trim() == term,
          isFalse,
          reason: 'Dart would answer the same for ${show(search)}',
        );
      }
    });
  });

  group('matchesAny (search-vectors.json "match")', () {
    for (final c in cases(_serverVectors('search-vectors.json'), 'match')) {
      final fields = (c['fields']! as List<Object?>).cast<String?>();
      final expected = (c['matches']! as List<Object?>).cast<bool>();
      test('${c['id']} ${show(c['term'])}', () {
        for (var i = 0; i < fields.length; i++) {
          expect(
            SearchRules.matchesAny(c['term']! as String, [fields[i]]),
            expected[i],
            reason: '${c['id']}[$i] ${show(fields[i])}',
          );
        }
      });
    }

    test('a search of only control characters matches every title', () {
      final term = SearchRules.searchTerm('\u0001\u0002')!;
      for (final title in ['Bread', 'a', '\u0001']) {
        expect(SearchRules.matchesAny(term, [title, null, null]), isTrue);
      }
    });
  });

  group('compareNames (name-order-vectors.json)', () {
    final random = Random(20261116);
    for (final c in cases(_serverVectors('name-order-vectors.json'), 'orders')) {
      final input = [
        for (final pair in (c['input']! as List<Object?>).cast<List<Object?>>())
          (name: pair[0]! as String, id: pair[1]! as String),
      ];
      // A vector names the expected order by name, or — where the names tie — by id.
      final byName = c.containsKey('sorted');
      final expected = (c[byName ? 'sorted' : 'sortedIds']! as List<Object?>).cast<String>();
      test('${c['id']}', () {
        // The server's test sorts every vector twenty times from shuffled input; so does this one.
        for (var round = 0; round < 20; round++) {
          final shuffled = input.toList()..shuffle(random);
          shuffled.sort((a, b) => SearchRules.compareNames(a.name, a.id, b.name, b.id));
          expect(
            [for (final e in shuffled) byName ? e.name : e.id],
            expected,
            reason: '${c['note']}',
          );
        }
      });
    }

    test('falls back to the id as text, which is the same order dashed or not', () {
      const a = '00000000-0000-0000-0000-00000000000a';
      const b = '00000000-0000-0000-0000-00000000000b';
      expect(SearchRules.compareNames('x', a, 'x', b), lessThan(0));
      expect(
        SearchRules.compareNames('x', a.replaceAll('-', ''), 'x', b.replaceAll('-', '')),
        lessThan(0),
      );
    });
  });
}
