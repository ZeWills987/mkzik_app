import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/player/queue_navigation.dart';

void main() {
  group('nextSourceIndex (ordre normal)', () {
    test('avance d\'un titre', () {
      expect(nextSourceIndex(length: 5, current: 1, shuffle: false), 2);
    });

    test('revient au début après le dernier (boucle)', () {
      expect(nextSourceIndex(length: 5, current: 4, shuffle: false), 0);
    });

    test('titre courant inconnu → premier titre', () {
      expect(nextSourceIndex(length: 5, current: -1, shuffle: false), 0);
    });

    test('liste d\'un seul titre ou vide → 0', () {
      expect(nextSourceIndex(length: 1, current: 0, shuffle: false), 0);
      expect(nextSourceIndex(length: 0, current: 0, shuffle: false), 0);
    });
  });

  group('nextSourceIndex (aléatoire)', () {
    test('ne renvoie jamais le titre courant et couvre tous les autres', () {
      final rng = Random(42);
      final seen = <int>{};
      for (var i = 0; i < 500; i++) {
        final n = nextSourceIndex(length: 6, current: 3, shuffle: true, random: rng);
        expect(n, isNot(3));
        expect(n, inInclusiveRange(0, 5));
        seen.add(n);
      }
      expect(seen, {0, 1, 2, 4, 5});
    });

    test('deux titres : toujours l\'autre', () {
      final rng = Random(1);
      for (var i = 0; i < 50; i++) {
        expect(nextSourceIndex(length: 2, current: 0, shuffle: true, random: rng), 1);
        expect(nextSourceIndex(length: 2, current: 1, shuffle: true, random: rng), 0);
      }
    });

    test('courant inconnu : peut renvoyer n\'importe quel index valide', () {
      final rng = Random(7);
      final seen = <int>{};
      for (var i = 0; i < 300; i++) {
        seen.add(nextSourceIndex(length: 4, current: -1, shuffle: true, random: rng));
      }
      expect(seen, {0, 1, 2, 3});
    });
  });

  group('previousSourceIndex', () {
    test('recule d\'un titre', () => expect(previousSourceIndex(length: 5, current: 3), 2));
    test('boucle au dernier titre depuis le premier', () => expect(previousSourceIndex(length: 5, current: 0), 4));
    test('courant inconnu → dernier titre', () => expect(previousSourceIndex(length: 5, current: -1), 4));
    test('un seul titre → 0', () => expect(previousSourceIndex(length: 1, current: 0), 0));
  });
}
