import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent/generated/prudent/v1/records.pb.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:prudent/providers.dart';
import 'package:zen_transport/zen_transport.dart';

void main() {
  late ProviderContainer container;
  late Map<String, Object> response;

  Map<String, String> record(String id, String date) => {
    'id': id,
    'date': date,
  };

  setUp(() {
    final client = ZenClient(
      baseUrl: 'https://example.test',
      format: ZenTransportFormat.json,
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.method == 'GET'
                ? {
                  'records': [
                    record('a', '2026-10-03'),
                    record('z', '2026-10-01'),
                  ],
                }
                : response,
          ),
          200,
          headers: {'X-Zen-Transport': 'json'},
        ),
      ),
    );
    container = ProviderContainer(
      overrides: [
        prudentRepositoryProvider.overrideWithValue(
          PrudentRepository(client: client),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<List<String>> ids() async =>
      (await container.read(recordsProvider.future)).map((r) => r.id).toList();

  test('inserts a record by date and id', () async {
    await ids();
    response = record('c', '2026-10-02');
    await container
        .read(recordsProvider.notifier)
        .addRecord(CreateRecordRequest());
    response = record('b', '2026-10-02');
    await container
        .read(recordsProvider.notifier)
        .addRecord(CreateRecordRequest());
    expect(await ids(), ['a', 'b', 'c', 'z']);
  });

  test('inserts both transfer legs in server order', () async {
    await ids();
    response = {
      'fromRecord': record('d', '2026-10-02'),
      'toRecord': record('c', '2026-10-02'),
    };
    await container
        .read(recordsProvider.notifier)
        .addTransfer(CreateTransferRequest());
    expect(await ids(), ['a', 'c', 'd', 'z']);
  });

  test('inserts a correction in server order', () async {
    await ids();
    response = record('c', '2026-10-02');
    await container
        .read(recordsProvider.notifier)
        .addCorrection(CreateCorrectionRequest());
    expect(await ids(), ['a', 'c', 'z']);
  });

  test('moves an edited record when its date changes', () async {
    await ids();
    response = record('z', '2026-10-04');
    await container
        .read(recordsProvider.notifier)
        .editRecord('z', UpdateRecordRequest());
    expect(await ids(), ['z', 'a']);
  });
}
