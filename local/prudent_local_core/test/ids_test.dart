// Finding F-11 (phase-0 §0.3): Local ids are 32 lower-case hex characters compared as text, which
// is Postgres' byte order of a uuid and not Java's signed UUID.compareTo (test/golden/ids.json).
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

import 'golden.dart';

void main() {
  final file = golden('ids.json');
  List<String> list(String key) => (file[key]! as List<Object?>).cast<String>();

  test('a server id reads in as its 32 hex characters', () {
    for (final uuid in list('uuids')) {
      final id = LocalIds.fromServerId(uuid);
      expect(LocalIds.isValid(id), isTrue, reason: uuid);
      expect(id, uuid.replaceAll('-', ''));
    }
  });

  test('text order of Local ids is the byte order Postgres sorts the server ids by', () {
    final local = list('uuids').map(LocalIds.fromServerId).toList()..sort(LocalIds.compare);
    expect(local, list('unsignedByteOrder').map(LocalIds.fromServerId).toList());
  });

  test("and it is not Java's signed UUID.compareTo, which two server routes use", () {
    expect(list('javaCompareToOrder'), isNot(list('unsignedByteOrder')));
  });

  test('only the form the server writes is read; what else UUID.fromString takes is refused', () {
    for (final entry in cases(file, 'fromString')) {
      final input = entry['input']! as String;
      final java = entry['fromString']! as Map<String, Object?>;
      final local = attempt(() => LocalIds.fromServerId(input));
      if (local.containsKey('ok')) {
        // Whatever Local reads, Java reads to the same id.
        expect((java['ok']! as String).replaceAll('-', ''), local['ok'], reason: show(input));
      } else {
        expect(local, {'refused': 404}, reason: show(input));
      }
    }
    expect(() => LocalIds.fromServerId('1-1-1-1-1'), throwsA(isA<Refusal>()));
  });
}
