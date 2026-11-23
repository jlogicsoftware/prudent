// The server-connected app's SettingsSession tells the server the chosen language through
// IdentityRepository.setLanguage (PUT /auth/language, jZen#275; jlogicsoftware/prudent#291).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/auth/identity_settings_session.dart';
import 'package:prudent_ui/settings_session.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

class _Repository implements IdentityRepository {
  _Repository(this.answer);

  final ZenResult<void> answer;
  final List<String> sent = [];

  @override
  Future<ZenResult<void>> setLanguage(String language) async {
    sent.add(language);
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  SettingsSession sessionOver(_Repository repository) {
    final container = ProviderContainer(
      overrides: [
        identityRepositoryProvider.overrideWithValue(repository),
        identitySettingsSession,
      ],
    );
    addTearDown(container.dispose);
    return container.read(settingsSessionProvider)!;
  }

  test('the chosen language goes to the identity repository', () async {
    final repository = _Repository(const ZenResult.ok(null));

    await sessionOver(repository).setLanguage!('pl');

    expect(repository.sent, ['pl']);
  });

  test('a refusal is thrown for Settings to report', () async {
    final repository = _Repository(const ZenResult.err(ZenUnknownError('invalid_language')));

    await expectLater(sessionOver(repository).setLanguage!('uk'), throwsA(isA<ZenError>()));
    expect(repository.sent, ['uk']);
  });
}
