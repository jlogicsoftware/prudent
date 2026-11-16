// The parity engine itself: that it compares exactly — one cent apart is a failure — and that it
// never counts a step it could not run as a match (ADR-107). The server is played here by a scripted
// backend; local/prudent_parity_server runs the same engine against the live Quarkus server.
import 'package:prudent_local_core/parity.dart';
import 'package:test/test.dart';

/// A backend whose answers are given in advance.
final class _Scripted extends ParityBackend {
  _Scripted(this.name, this.answers);

  @override
  final String name;

  final Map<String, Map<String, Object?>> answers;
  int opened = 0;
  int closed = 0;

  @override
  Map<String, ParityOp> get ops => {
    for (final entry in answers.entries)
      entry.key: (input, bindings) async {
        if (input.containsKey('account')) bindings.resolve(input['account']);
        return StepResult(entry.value, createdId: '$name-id');
      },
  };

  @override
  Future<void> open(String scenarioName) async => opened++;

  @override
  Future<void> close() async => closed++;
}

ParityScenario _scenario(List<Map<String, Object?>> steps) => ParityScenario(
  name: 'probe',
  description: 'engine test',
  rules: const ['3.1'],
  steps: [
    for (final step in steps)
      ParityStep(
        op: step['op']! as String,
        input: (step['input'] as Map<String, Object?>?) ?? const {},
        bindAs: step['as'] as String?,
        outcome: step['outcome'] as String?,
      ),
  ],
);

void main() {
  final balances = _scenario([
    {'op': 'account.create', 'as': 'a', 'outcome': 'accepted'},
    {
      'op': 'account.balances',
      'input': {'account': r'$a'},
    },
  ]);

  Map<String, Map<String, Object?>> answering(String pln) => {
    'account.create': ParityObservation.accepted(),
    'account.balances': ParityObservation.accepted({
      'balances': {'EUR': '500', 'PLN': pln},
    }),
  };

  test('identical figures match', () async {
    final report = await ParityEngine(
      server: _Scripted('server', answering('8767')),
      local: _Scripted('local', answering('8767')),
    ).run(balances);
    expect(report.matches, isTrue, reason: report.describe());
  });

  test('a one-cent difference fails and names the step, the field and both figures', () async {
    final report = await ParityEngine(
      server: _Scripted('server', answering('8767')),
      local: _Scripted('local', answering('8766')),
    ).run(balances);
    expect(report.matches, isFalse);
    expect(report.differences.single.path, 'balances.PLN');
    expect(
      report.describe(),
      contains('step 2 (account.balances): balances.PLN — server "8767", local "8766"'),
    );
  });

  test('a figure as a number is not the same as the figure as text', () async {
    final report =
        await ParityEngine(
          server: _Scripted('server', {
            'account.create': ParityObservation.accepted({'x': '1'}),
          }),
          local: _Scripted('local', {
            'account.create': ParityObservation.accepted({'x': 1}),
          }),
        ).run(
          _scenario([
            {'op': 'account.create'},
          ]),
        );
    expect(report.matches, isFalse);
  });

  test('a field only one side reports is a difference', () async {
    final report =
        await ParityEngine(
          server: _Scripted('server', {
            'account.create': ParityObservation.accepted({'note': ''}),
          }),
          local: _Scripted('local', {'account.create': ParityObservation.accepted()}),
        ).run(
          _scenario([
            {'op': 'account.create'},
          ]),
        );
    expect(report.describe(), contains('note — server "", local (absent)'));
  });

  test('a double in an observation stops the scenario', () async {
    final engine = ParityEngine(
      server: _Scripted('server', {
        'account.create': ParityObservation.accepted({'x': 0.1}),
      }),
      local: _Scripted('local', {
        'account.create': ParityObservation.accepted({'x': 0.1}),
      }),
    );
    await expectLater(
      engine.run(
        _scenario([
          {'op': 'account.create'},
        ]),
      ),
      throwsA(isA<ParityStepFailed>()),
    );
  });

  test(
    'an operation one backend lacks fails the scenario and still closes both backends',
    () async {
      final server = _Scripted('server', {'account.create': ParityObservation.accepted()});
      final local = _Scripted('local', {});
      await expectLater(
        ParityEngine(server: server, local: local).run(
          _scenario([
            {'op': 'account.create'},
          ]),
        ),
        throwsA(isA<UnknownParityOp>()),
      );
      expect([server.closed, local.closed], [1, 1]);
    },
  );

  test(
    'the server answering other than the scenario says is a difference even when both agree',
    () async {
      final refusing = {'account.create': ParityObservation.refused(400)};
      final report =
          await ParityEngine(
            server: _Scripted('server', refusing),
            local: _Scripted('local', refusing),
          ).run(
            _scenario([
              {'op': 'account.create', 'outcome': 'accepted'},
            ]),
          );
      expect(report.matches, isFalse);
    },
  );

  group('the scenario format refuses what it does not define', () {
    test('an unknown step key', () {
      expect(
        () => ParityScenario.parse(
          '{"name":"x","description":"d","rules":["3.1"],"steps":[{"op":"a","outcom":"accepted"}]}',
        ),
        throwsFormatException,
      );
    });

    test('a scenario that names no rule', () {
      expect(
        () =>
            ParityScenario.parse('{"name":"x","description":"d","rules":[],"steps":[{"op":"a"}]}'),
        throwsFormatException,
      );
    });

    test('an outcome other than accepted or refused', () {
      expect(
        () => ParityScenario.parse(
          '{"name":"x","description":"d","rules":["3.1"],"steps":[{"op":"a","outcome":"ok"}]}',
        ),
        throwsFormatException,
      );
    });
  });
}
