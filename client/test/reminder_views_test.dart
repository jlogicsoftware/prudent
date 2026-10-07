// The in-app reminder centre (jlogicsoftware/prudent#68, ADR-055): due and overdue reminders with
// their read state, the bell that counts the unread ones, and the occurrence a reminder opens.
// Driven through the real PrudentRepository over a mock HTTP server, so the requests the screens
// send are the ones asserted, not a fake's idea of them.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/generated/prudent/v1/categories.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:prudent/providers.dart';
import 'package:prudent/reminder/reminder_bell.dart';
import 'package:prudent/reminder/reminders_screen.dart';
import 'package:zen_transport/zen_transport.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';
import 'zen_fields.dart';

const _headers = {'X-Zen-Transport': 'json'};

/// One occurrence that has a reminder, as the fake server holds it.
class _Entry {
  _Entry(
    this.id,
    this.title,
    this.date, {
    this.overdue = false,
    this.read = false,
    this.amount = -250000,
    this.status,
  });

  final String id;
  final String title;
  final String date;
  final bool overdue;
  bool read;
  final int amount;

  /// The occurrence's status when it is not the one its reminder has: set once it is resolved.
  String? status;

  Map<String, Object?> occurrence() => {
    'id': id,
    'planId': 'plan-1',
    'occurrenceDate': date,
    'status': status ?? (overdue ? 'OCCURRENCE_STATUS_OVERDUE' : 'OCCURRENCE_STATUS_PLANNED'),
    'title': title,
    'amountMinor': '$amount',
    'currency': 'PLN',
    'accountId': 'acc',
    'categoryId': 'rent',
  };

  Map<String, Object?> reminder() => {
    'occurrence': occurrence(),
    'remindOn': date,
    'leadDays': 2,
    'read': read,
  };
}

/// A server holding some reminders, answering the centre and the occurrence actions and recording
/// every call, so a test can say what was — and was not — sent.
class _Server {
  _Server(this.entries);

  final List<_Entry> entries;
  final calls = <String>[];
  final posted = <String, String>{};

  /// When set, the next read or unread is refused with this message.
  String? refuseRead;

  int count(String call) => calls.where((c) => c == call).length;

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: _headers);

  List<_Entry> get _current => entries.where((e) => e.status == null).toList();

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (request.method == 'GET' && path == '/api/v1/reminders') {
      return _json({'reminders': [for (final e in _current) e.reminder()]});
    }
    if (request.method == 'POST') {
      posted[path] = request.body;
      if (path == '/api/v1/reminders/read-all') {
        for (final e in _current) {
          e.read = true;
        }
        return _json({'reminders': [for (final e in _current) e.reminder()]});
      }
      final reminder = RegExp(r'^/api/v1/reminders/([^/]+)/(read|unread)$').firstMatch(path);
      if (reminder != null) {
        final refusal = refuseRead;
        if (refusal != null) {
          refuseRead = null;
          return _json({'code': 'conflict', 'message': refusal}, 409);
        }
        final entry = entries.firstWhere((e) => e.id == reminder.group(1));
        entry.read = reminder.group(2) == 'read';
        return _json(entry.reminder());
      }
      final action = RegExp(r'^/api/v1/occurrences/([^/]+)/(skip|restore|confirm)$').firstMatch(path);
      if (action != null) {
        final entry = entries.firstWhere((e) => e.id == action.group(1));
        entry.status = switch (action.group(2)) {
          'skip' => 'OCCURRENCE_STATUS_SKIPPED',
          'restore' => null,
          _ => 'OCCURRENCE_STATUS_COMPLETED',
        };
        if (action.group(2) == 'confirm') {
          return _json({'occurrence': entry.occurrence(), 'record': {'id': 'rec-1'}}, 201);
        }
        return _json(entry.occurrence());
      }
    }
    return http.Response('unexpected ${request.method} $path', 500);
  }
}

class _FixedAccounts extends AccountsNotifier {
  @override
  Future<List<Account>> build() async => [Account(id: 'acc', name: 'Bank')];
}

class _FixedCategories extends CategoriesNotifier {
  @override
  Future<List<Category>> build() async => [Category(id: 'rent', title: 'Rent')];
}

void main() {
  late _Server server;

  _Server standard() => _Server([
    _Entry('old', 'Internet', '2026-10-01', overdue: true),
    _Entry('rent', 'Rent', '2026-10-10', overdue: true, read: true),
    _Entry('gym', 'Gym', '2026-10-17', amount: -12000),
  ]);

  Future<void> pump(WidgetTester tester, _Server s, {Widget home = const RemindersScreen()}) async {
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
          accountsProvider.overrideWith(_FixedAccounts.new),
          categoriesProvider.overrideWith(_FixedCategories.new),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            ...PrudentLocalizations.localizationsDelegates,
            zenWidgetsLocaleDelegate,
          ],
          supportedLocales: PrudentLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder unreadMarks() => find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == 'Unread');

  group('the centre', () {
    testWidgets('lists overdue reminders first, then those due soon, with date and amount', (
      tester,
    ) async {
      await pump(tester, standard());

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Due soon'), findsOneWidget);
      expect(find.text('Internet'), findsOneWidget);
      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('Gym'), findsOneWidget);
      expect(find.text('Overdue since Oct 1, 2026 · -2500.00 PLN'), findsOneWidget);
      expect(find.text('Due Oct 17, 2026 · -120.00 PLN'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Internet')).dy,
        lessThan(tester.getTopLeft(find.text('Gym')).dy),
        reason: 'overdue comes above due soon',
      );
    });

    testWidgets('marks the unread ones, in words as well as weight', (tester) async {
      await pump(tester, standard());

      // Rent was read; Internet and Gym were not.
      expect(unreadMarks(), findsNWidgets(2));
      final bold = find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontWeight == FontWeight.bold,
      );
      expect(bold, findsNWidgets(2));
      expect(find.descendant(of: bold, matching: find.text('Rent')), findsNothing);
    });

    testWidgets('says so when there is nothing to remind of', (tester) async {
      await pump(tester, _Server([]));

      expect(find.textContaining('No reminders.'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('a failed load says so and draws no reminders', (tester) async {
      final failing = _Server([]);
      server = failing;
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = ZenClient(
        baseUrl: 'https://example.test',
        format: ZenTransportFormat.json,
        httpClient: MockClient((_) async => http.Response('boom', 500, headers: _headers)),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [prudentRepositoryProvider.overrideWithValue(PrudentRepository(client: client))],
          child: MaterialApp(
            localizationsDelegates: PrudentLocalizations.localizationsDelegates,
            supportedLocales: PrudentLocalizations.supportedLocales,
            home: const RemindersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not load reminders'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });
  });

  group('read state', () {
    testWidgets('the button on a tile flips one reminder and no other', (tester) async {
      await pump(tester, standard());

      await tester.tap(iconButton('Mark as read').first);
      await tester.pumpAndSettle();

      expect(server.calls, contains('POST /api/v1/reminders/old/read'));
      expect(unreadMarks(), findsOneWidget);

      await tester.tap(iconButton('Mark as unread').first);
      await tester.pumpAndSettle();

      expect(server.calls, contains('POST /api/v1/reminders/old/unread'));
      expect(unreadMarks(), findsNWidgets(2));
      expect(server.entries.firstWhere((e) => e.id == 'rent').read, isTrue);
    });

    testWidgets('mark all as read sends one request and leaves nothing unread', (tester) async {
      await pump(tester, standard());

      await tester.tap(iconButton('Mark all as read'));
      await tester.pumpAndSettle();

      expect(server.count('POST /api/v1/reminders/read-all'), 1);
      expect(unreadMarks(), findsNothing);
      final button = tester.widget<ZenIconButton>(find.widgetWithIcon(ZenIconButton, Icons.done_all));
      expect(button.onPressed, isNull, reason: 'nothing left to mark');
    });

    testWidgets('a refusal is shown in the server words and the list is fetched again', (
      tester,
    ) async {
      await pump(tester, standard());
      server.refuseRead = 'That occurrence has no reminder right now.';
      final before = server.count('GET /api/v1/reminders');

      await tester.tap(iconButton('Mark as read').first);
      await tester.pumpAndSettle();

      expect(find.text('That occurrence has no reminder right now.'), findsOneWidget);
      await tester.tap(find.text('Okay'));
      await tester.pumpAndSettle();
      expect(server.count('GET /api/v1/reminders'), before + 1);
      expect(unreadMarks(), findsNWidgets(2), reason: 'nothing was marked');
    });
  });

  group('opening a reminder', () {
    testWidgets('marks it read and shows the occurrence with its plan fields', (tester) async {
      await pump(tester, standard());

      await tester.tap(find.text('Internet'));
      await tester.pumpAndSettle();

      expect(server.calls, contains('POST /api/v1/reminders/old/read'));
      expect(find.text('Planned transaction'), findsOneWidget);
      expect(find.text('Internet'), findsOneWidget);
      expect(find.text('Oct 1, 2026'), findsOneWidget);
      expect(find.text('-2500.00 PLN'), findsOneWidget);
      expect(find.text('Bank'), findsOneWidget);
      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Confirm as planned'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('an already read reminder opens without marking it again', (tester) async {
      await pump(tester, standard());

      await tester.tap(find.text('Rent'));
      await tester.pumpAndSettle();

      expect(find.text('Planned transaction'), findsOneWidget);
      expect(server.calls.where((c) => c.contains('/read')), isEmpty);
    });

    testWidgets('a refused mark keeps the occurrence closed', (tester) async {
      await pump(tester, standard());
      server.refuseRead = 'Resolved elsewhere.';

      await tester.tap(find.text('Internet'));
      await tester.pumpAndSettle();

      expect(find.text('Resolved elsewhere.'), findsOneWidget);
      expect(find.text('Planned transaction'), findsNothing);
    });

    testWidgets('confirming posts exactly as planned and ends the reminder', (tester) async {
      await pump(tester, standard());
      await tester.tap(find.text('Internet'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm as planned'));
      await tester.pumpAndSettle();

      expect(server.count('POST /api/v1/occurrences/old/confirm'), 1);
      expect(jsonDecode(server.posted['/api/v1/occurrences/old/confirm']!), isEmpty);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Confirm as planned'), findsNothing);

      await tester.tap(iconButton('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Internet'), findsNothing, reason: 'a confirmed occurrence has no reminder');
      expect(find.text('Rent'), findsOneWidget);
    });

    testWidgets('skipping ends the reminder and restoring offers it again', (tester) async {
      await pump(tester, standard());
      await tester.tap(find.text('Gym'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(server.count('POST /api/v1/occurrences/gym/skip'), 1);
      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
      expect(find.text('Confirm as planned'), findsNothing);

      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      expect(server.count('POST /api/v1/occurrences/gym/restore'), 1);
      expect(find.text('Planned'), findsOneWidget);
      expect(find.text('Confirm as planned'), findsOneWidget);
    });
  });

  group('the bell', () {
    Widget bell() => Scaffold(appBar: AppBar(actions: const [ReminderBell()]));

    testWidgets('counts the unread reminders on its badge and in its tooltip', (tester) async {
      await pump(tester, standard(), home: bell());

      expect(find.descendant(of: find.byType(Badge), matching: find.text('2')), findsOneWidget);
      expect(find.byTooltip('Reminders, 2 unread'), findsOneWidget);
    });

    testWidgets('shows no badge when everything is read, or when there is nothing', (tester) async {
      await pump(tester, _Server([_Entry('a', 'Rent', '2026-10-17', read: true)]), home: bell());

      expect(find.descendant(of: find.byType(Badge), matching: find.text('0')), findsNothing);
      expect(find.byTooltip('Reminders'), findsOneWidget);
    });

    testWidgets('opens the centre, and reading there updates the count', (tester) async {
      await pump(tester, standard(), home: bell());

      await tester.tap(find.byTooltip('Reminders, 2 unread'));
      await tester.pumpAndSettle();
      expect(find.text('Due soon'), findsOneWidget);

      await tester.tap(iconButton('Mark all as read'));
      await tester.pumpAndSettle();
      await tester.tap(iconButton('Back'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Reminders'), findsOneWidget);
    });
  });
}
