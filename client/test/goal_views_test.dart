// The goal and envelope views (jlogicsoftware/prudent#67): active, completed and archived goals; a
// goal's history and the actions its state allows; and envelope amounts drawn apart from account
// balances. Driven through the real PrudentRepository over a mock HTTP server, so the requests the
// screens send are the ones asserted, not a fake's idea of them.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/generated/prudent/v1/settings.pb.dart';
import 'package:prudent/goal/envelope_amount.dart';
import 'package:prudent/goal/goals_screen.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:prudent/providers.dart';
import 'package:zen_transport/zen_transport.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'zen_platform_skip.dart';

const _headers = {'X-Zen-Transport': 'json'};

Map<String, Object?> _goal(
  String id,
  String name, {
  String status = 'GOAL_STATUS_ACTIVE',
  String currency = 'PLN',
  int target = 500000,
  String? date,
}) => {
  'id': id,
  'name': name,
  'currency': currency,
  'targetAmountMinor': '$target',
  'status': status,
  if (date != null) 'targetDate': date,
};

Map<String, Object?> _progress(
  String id, {
  required int allocated,
  required int target,
  required String guidance,
  String currency = 'PLN',
  int? monthly,
  int? months,
}) => {
  'goalId': id,
  'currency': currency,
  'allocatedMinor': '$allocated',
  'targetAmountMinor': '$target',
  'remainingMinor': '${target - allocated < 0 ? 0 : target - allocated}',
  'progressPercent': allocated * 100 ~/ target > 100 ? 100 : allocated * 100 ~/ target,
  'guidance': guidance,
  if (monthly != null) 'monthlyContributionMinor': '$monthly',
  if (months != null) 'monthsRemaining': months,
};

/// A server holding a few goals, answering what the goal views read and recording what they write.
class _Server {
  _Server({
    required this.goals,
    required this.progress,
    required this.freeMoney,
    this.history = const {},
  });

  List<Map<String, Object?>> goals;
  List<Map<String, Object?>> progress;
  List<Map<String, Object?>> freeMoney;
  Map<String, List<Map<String, Object?>>> history;

  final calls = <String>[];
  final posted = <String, Map<String, Object?>>{};

  /// When set, the next allocation is refused with this message.
  String? refuseAllocation;

  int count(String call) => calls.where((c) => c == call).length;

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: _headers);

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (request.method == 'GET') {
      switch (path) {
        case '/api/v1/goals':
          return _json({'goals': goals});
        case '/api/v1/goals/progress':
          return _json({'asOf': request.url.queryParameters['asOf'], 'goals': progress});
        case '/api/v1/goal-allocations/free-money':
          return _json({'currencies': freeMoney});
        case '/api/v1/goal-allocations':
          return _json({'allocations': history[request.url.queryParameters['goalId']] ?? []});
      }
    }
    if (request.method == 'POST') {
      final body = request.body.isEmpty ? <String, Object?>{} : jsonDecode(request.body);
      posted[path] = (body as Map).cast<String, Object?>();
      if (path == '/api/v1/goal-allocations') {
        final refusal = refuseAllocation;
        if (refusal != null) {
          return _json({'code': 'CONFLICT', 'message': refusal}, 409);
        }
        return _json({'id': 'new', ...posted[path]!, 'currency': 'PLN'});
      }
      final lifecycle = RegExp(
        r'^/api/v1/goals/([^/]+)/(complete|archive|reactivate)$',
      ).firstMatch(path);
      if (lifecycle != null) {
        final status = switch (lifecycle.group(2)) {
          'complete' => 'GOAL_STATUS_COMPLETED',
          'archive' => 'GOAL_STATUS_ARCHIVED',
          _ => 'GOAL_STATUS_ACTIVE',
        };
        final goal = {...goals.firstWhere((g) => g['id'] == lifecycle.group(1)), 'status': status};
        return _json(goal);
      }
    }
    return http.Response('unexpected ${request.method} $path', 500);
  }
}

Account _account(String currency) => Account(
  id: 'acc',
  name: 'Bank',
  type: AccountType.ACCOUNT_TYPE_CARD,
  isActive: true,
  balances: [CurrencyBalance(currency: currency)],
);

void main() {
  late _Server server;

  _Server standard() => _Server(
    goals: [
      _goal('car', 'Car', date: '2027-03-15'),
      _goal('trip', 'Trip', target: 200000),
      _goal('bike', 'Bike', status: 'GOAL_STATUS_COMPLETED', target: 100000),
      _goal('tv', 'TV', status: 'GOAL_STATUS_ARCHIVED', target: 300000),
      _goal('eur', 'Euro trip', currency: 'EUR', target: 100000),
    ],
    progress: [
      _progress(
        'car',
        allocated: 125000,
        target: 500000,
        guidance: 'GOAL_GUIDANCE_CONTRIBUTION',
        monthly: 62500,
        months: 6,
      ),
      _progress('trip', allocated: 0, target: 200000, guidance: 'GOAL_GUIDANCE_NO_TARGET_DATE'),
      _progress('bike', allocated: 100000, target: 100000, guidance: 'GOAL_GUIDANCE_NOT_ACTIVE'),
      _progress('tv', allocated: 0, target: 300000, guidance: 'GOAL_GUIDANCE_NOT_ACTIVE'),
      _progress(
        'eur',
        currency: 'EUR',
        allocated: 0,
        target: 100000,
        guidance: 'GOAL_GUIDANCE_NO_TARGET_DATE',
      ),
    ],
    freeMoney: [
      {
        'currency': 'PLN',
        'eligibleMinor': '800000',
        'allocatedMinor': '225000',
        'freeMinor': '575000',
        'eligibleAccountIds': ['acc'],
      },
    ],
    history: {
      'car': [
        {
          'id': 'h3',
          'kind': 'GOAL_ALLOCATION_KIND_MOVE',
          'sourceGoalId': 'car',
          'targetGoalId': 'trip',
          'currency': 'PLN',
          'amountMinor': '5000',
          'createdAtMs': '1790000000000',
        },
        {
          'id': 'h2',
          'kind': 'GOAL_ALLOCATION_KIND_WITHDRAW',
          'sourceGoalId': 'car',
          'currency': 'PLN',
          'amountMinor': '20000',
          'note': 'Repair',
          'createdAtMs': '1780000000000',
        },
        {
          'id': 'h1',
          'kind': 'GOAL_ALLOCATION_KIND_ALLOCATE',
          'targetGoalId': 'car',
          'currency': 'PLN',
          'amountMinor': '150000',
          'createdAtMs': '1770000000000',
        },
      ],
    },
  );

  Future<void> pump(WidgetTester tester, _Server s) async {
    server = s;
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final client = ZenClient(
      baseUrl: 'https://example.test',
      format: ZenTransportFormat.json,
      httpClient: MockClient(s.handle),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prudentRepositoryProvider.overrideWithValue(PrudentRepository(client: client)),
          accountsProvider.overrideWith(() => _FixedAccounts([_account('PLN'), _account('EUR')])),
          settingsProvider.overrideWith(_FixedSettings.new),
          goalProgressAsOfProvider.overrideWithValue('2026-10-02'),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            ...PrudentLocalizations.localizationsDelegates,
            zenWidgetsLocaleDelegate,
          ],
          supportedLocales: PrudentLocalizations.supportedLocales,
          home: GoalsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inEnvelope(String text) =>
      find.descendant(of: find.byType(EnvelopeAmount), matching: find.text(text));

  testWidgets('lists the active goals with their envelope, progress and guidance', (tester) async {
    await pump(tester, standard());

    expect(server.calls, contains('GET /api/v1/goals/progress'));
    expect(find.text('Car'), findsOneWidget);
    expect(find.text('Trip'), findsOneWidget);
    expect(find.text('Euro trip'), findsOneWidget);
    expect(find.text('Bike'), findsNothing);
    expect(find.text('TV'), findsNothing);

    expect(find.text('By Mar 15, 2027'), findsOneWidget);
    expect(find.text('25% of target'), findsOneWidget);
    expect(inEnvelope('1250.00 PLN'), findsOneWidget);
    expect(find.text('5000.00 PLN'), findsOneWidget);
    expect(find.text('3750.00 PLN'), findsOneWidget);
    expect(find.text('Set aside 625.00 PLN a month · 6 months left'), findsOneWidget);
    expect(find.text('No target date'), findsNWidgets(2));
  });

  testWidgets('keeps envelope amounts apart from account money and says why', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, standard());

    expect(find.text('Money for goals'), findsOneWidget);
    expect(find.textContaining('never changes a balance'), findsOneWidget);
    // Eligible and free money are account money: plain text. Set-aside money is an envelope.
    expect(find.text('8000.00 PLN'), findsOneWidget);
    expect(inEnvelope('8000.00 PLN'), findsNothing);
    expect(find.text('5750.00 PLN'), findsOneWidget);
    expect(inEnvelope('5750.00 PLN'), findsNothing);
    expect(inEnvelope('2250.00 PLN'), findsOneWidget);
    // Read out as set-aside money, so the difference is not carried by colour alone.
    expect(find.bySemanticsLabel('Set aside for goals: 2250.00 PLN'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('says when the envelopes hold more than the eligible accounts', (tester) async {
    final s =
        standard()
          ..freeMoney = [
            {
              'currency': 'PLN',
              'eligibleMinor': '100000',
              'allocatedMinor': '125000',
              'freeMinor': '-25000',
            },
          ];
    await pump(tester, s);

    expect(find.text('-250.00 PLN'), findsOneWidget);
    expect(find.text('Envelopes hold 250.00 PLN more than your eligible accounts'), findsOneWidget);
  });

  testWidgets('shows completed and archived goals on their own segments', (tester) async {
    await pump(tester, standard());

    await tester.tap(find.text('Completed').first);
    await tester.pumpAndSettle();
    expect(find.text('Bike'), findsOneWidget);
    expect(find.text('Car'), findsNothing);
    expect(find.text('100% of target'), findsOneWidget);

    await tester.tap(find.text('Archived').first);
    await tester.pumpAndSettle();
    expect(find.text('TV'), findsOneWidget);
    expect(find.text('Bike'), findsNothing);
  });

  testWidgets('has an empty state per segment and a hint when nothing is eligible', (tester) async {
    await pump(tester, _Server(goals: const [], progress: const [], freeMoney: const []));

    expect(find.text('No active goals. Add one to start setting money aside.'), findsOneWidget);
    expect(
      find.text('Mark an account as available for goals to start setting money aside.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();
    expect(find.text('No archived goals.'), findsOneWidget);
  });

  testWidgets('reports a failed load rather than an empty list', (tester) async {
    final s = standard();
    await pump(tester, _FailingGoals(s));
    expect(find.textContaining('Could not load goals'), findsOneWidget);
    expect(find.text('No active goals. Add one to start setting money aside.'), findsNothing);
  });

  testWidgets('a goal opens to its history, read from its own side', (tester) async {
    await pump(tester, standard());
    await tester.tap(find.text('Car'));
    await tester.pumpAndSettle();

    expect(server.calls, contains('GET /api/v1/goal-allocations'));
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Moved to Trip'), findsOneWidget);
    expect(inEnvelope('-50.00 PLN'), findsOneWidget);
    expect(find.text('Withdrawn'), findsOneWidget);
    expect(find.textContaining('Repair'), findsOneWidget);
    expect(inEnvelope('-200.00 PLN'), findsOneWidget);
    expect(inEnvelope('+1500.00 PLN'), findsOneWidget);
    // Newest first, as the server sent it.
    expect(
      tester.getTopLeft(find.text('Moved to Trip')).dy,
      lessThan(tester.getTopLeft(find.text('Withdrawn')).dy),
    );
  });

  testWidgets('an active goal offers add, withdraw and move; adding sends one allocation', (
    tester,
  ) async {
    if (skipWithoutZenPlatform()) return;
    await pump(tester, standard());
    await tester.tap(find.text('Car'));
    await tester.pumpAndSettle();

    expect(find.text('Add money'), findsOneWidget);
    expect(find.text('Withdraw'), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);

    final progressReads = server.count('GET /api/v1/goals/progress');
    await tester.tap(find.text('Add money'));
    await tester.pumpAndSettle();
    expect(find.text('Add money to Car'), findsOneWidget);
    expect(find.text('Free to set aside: 5750.00 PLN'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '100.5');
    await tester.enterText(find.byType(TextField).last, 'Bonus');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final body = server.posted['/api/v1/goal-allocations']!;
    expect(body['kind'], 'GOAL_ALLOCATION_KIND_ALLOCATE');
    expect(body['targetGoalId'], 'car');
    expect(body.containsKey('sourceGoalId'), isFalse);
    expect(body['amountMinor'], '10050');
    expect(body['note'], 'Bonus');
    expect(find.text('Add money to Car'), findsNothing);
    // The envelope is a sum over the history, so the figures are asked for again.
    expect(server.count('GET /api/v1/goals/progress'), greaterThan(progressReads));
  });

  testWidgets('a refused allocation is explained in the form, which stays open', (tester) async {
    if (skipWithoutZenPlatform()) return;
    await pump(tester, standard()..refuseAllocation = 'Only 5750.00 PLN is free.');
    await tester.tap(find.text('Car'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add money'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '9000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Only 5750.00 PLN is free.'), findsOneWidget);
    expect(find.text('Add money to Car'), findsOneWidget);
  });

  testWidgets('a zero amount is refused before anything is sent', (tester) async {
    if (skipWithoutZenPlatform()) return;
    await pump(tester, standard());
    await tester.tap(find.text('Car'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();

    expect(find.text('In this envelope: 1250.00 PLN'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter an amount above zero'), findsOneWidget);
    expect(server.posted, isEmpty);
  });

  testWidgets('a move offers only active goals in the same currency', (tester) async {
    if (skipWithoutZenPlatform()) return;
    await pump(tester, standard());
    await tester.tap(find.text('Car'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Move to'));
    await tester.pumpAndSettle();
    expect(find.text('Trip'), findsWidgets);
    expect(find.text('Euro trip'), findsNothing);
    expect(find.text('Bike'), findsNothing);
    expect(find.text('TV'), findsNothing);
    await tester.tap(find.text('Trip').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '25');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final body = server.posted['/api/v1/goal-allocations']!;
    expect(body['kind'], 'GOAL_ALLOCATION_KIND_MOVE');
    expect(body['sourceGoalId'], 'car');
    expect(body['targetGoalId'], 'trip');
    expect(body['amountMinor'], '2500');
  });

  testWidgets('a completed goal can give money out but not take it in', (tester) async {
    await pump(tester, standard());
    await tester.tap(find.text('Completed').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bike'));
    await tester.pumpAndSettle();

    expect(find.text('Add money'), findsNothing);
    expect(find.text('Withdraw'), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);
    expect(find.text('Nothing has been set aside for this goal yet.'), findsOneWidget);
  });

  testWidgets('an archived goal is read-only until it is reactivated', (tester) async {
    await pump(tester, standard());
    await tester.tap(find.text('Archived').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TV'));
    await tester.pumpAndSettle();

    expect(find.text('Add money'), findsNothing);
    expect(find.text('Withdraw'), findsNothing);
    expect(find.text('Move'), findsNothing);
    expect(find.textContaining('This goal is archived'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Archive'), findsNothing);
    await tester.tap(find.text('Reactivate'));
    await tester.pumpAndSettle();

    expect(server.calls, contains('POST /api/v1/goals/tv/reactivate'));
    expect(find.text('Add money'), findsOneWidget);
  });

  testWidgets('a refused archive is reported in the server\'s words', (tester) async {
    final s = _RefusingArchive(standard());
    await pump(tester, s);
    await tester.tap(find.text('Car'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Withdraw the money first.'), findsOneWidget);
  });
}

class _FailingGoals extends _Server {
  _FailingGoals(_Server s)
    : super(goals: s.goals, progress: s.progress, freeMoney: s.freeMoney, history: s.history);

  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'GET' && request.url.path == '/api/v1/goals') {
      calls.add('GET /api/v1/goals');
      return http.Response(jsonEncode({'message': 'down'}), 503, headers: _headers);
    }
    return super.handle(request);
  }
}

class _RefusingArchive extends _Server {
  _RefusingArchive(_Server s)
    : super(goals: s.goals, progress: s.progress, freeMoney: s.freeMoney, history: s.history);

  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/archive')) {
      calls.add('POST ${request.url.path}');
      return http.Response(
        jsonEncode({'code': 'CONFLICT', 'message': 'Withdraw the money first.'}),
        409,
        headers: _headers,
      );
    }
    return super.handle(request);
  }
}

class _FixedAccounts extends AccountsNotifier {
  _FixedAccounts(this._accounts);
  final List<Account> _accounts;

  @override
  Future<List<Account>> build() async => _accounts;
}

class _FixedSettings extends SettingsNotifier {
  @override
  Future<Settings> build() async => Settings(mainCurrency: 'PLN');
}
