// English, Ukrainian and Polish (plan unit 9): every Local string exists in all three, and the
// framework screens jZen ships only in English and Ukrainian (zen_ui_store, zen_ui_lock) speak Polish
// through Prudent's own delegates rather than degrading to English.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/integrity/prudent_issue_source.dart';
import 'package:prudent_local_client/l10n/pl_local_delegates.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

void main() {
  Map<String, dynamic> arb(String locale) =>
      jsonDecode(File('lib/l10n/local_$locale.arb').readAsStringSync())
          as Map<String, dynamic>;

  test('every Local string is in English, Ukrainian and Polish', () {
    Set<String> keys(Map<String, dynamic> m) => {
      for (final k in m.keys)
        if (!k.startsWith('@')) k,
    };
    final en = keys(arb('en'));
    expect(keys(arb('uk')), en);
    expect(keys(arb('pl')), en);
    for (final locale in ['uk', 'pl']) {
      final strings = arb(locale);
      for (final key in en) {
        expect(
          (strings[key] as String).trim(),
          isNotEmpty,
          reason: '$locale $key',
        );
      }
    }
  });

  test(
    'Polish lock and store wording is Polish, not the English fallback',
    () async {
      const pl = Locale('pl');
      final lock = await const PlLockDelegate().load(pl);
      final english = lookupLockLocalizations(const Locale('en'));
      expect(lock.unlockTitle, isNot(english.unlockTitle));
      expect(lock.lockedOut(30), contains('30'));
      final store = await const PlStoreDelegate().load(pl);
      final storeEnglish = lookupStoreLocalizations(const Locale('en'));
      expect(store.conflictsTitle, isNot(storeEnglish.conflictsTitle));
      expect(store.bannerText(1), isNot(store.bannerText(5)));
      expect(store.bannerText(5), contains('5'));
      expect(store.bannerAttention(22), contains('22'));
    },
  );

  test('every integrity check this build runs has words for its issues', () {
    // The codes each check can emit, read from the store package's sources, so a check added later
    // without words here fails this test rather than reaching a person as a bare code.
    final sources = Directory('../prudent_local_store/lib/src/integrity/checks')
        .listSync()
        .whereType<File>()
        .map((f) => f.readAsStringSync())
        .join('\n');
    final codes = {
      for (final m in RegExp(
        r"code: '([a-z_]+\.[a-z_.]+)'",
      ).allMatches(sources))
        m.group(1)!,
    };
    expect(codes, isNotEmpty);
    expect(codes.difference(wordedIssueCodes), isEmpty);
    expect(IntegrityRunner.allChecks, isNotEmpty);
  });
}
