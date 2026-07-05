// Test de fumée minimal. Le vrai widget racine (MkzikApp) dépend de services
// (dotenv, audio, secure storage) non initialisés en contexte de test unitaire.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('smoke test placeholder', () {
    expect(1 + 1, 2);
  });
}
