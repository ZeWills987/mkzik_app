import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/utils/format.dart';

void main() {
  group('formatDuration', () {
    test('secondes complétées sur 2 chiffres', () {
      expect(formatDuration(const Duration(minutes: 3, seconds: 5)), '3:05');
      expect(formatDuration(const Duration(seconds: 59)), '0:59');
      expect(formatDuration(Duration.zero), '0:00');
    });

    test('pas de format heures : 75 min → 75:00', () {
      expect(formatDuration(const Duration(minutes: 75)), '75:00');
    });
  });

  group('formatCount', () {
    test('sous 1000 → entier', () => expect(formatCount(999), '999'));
    test('milliers → k', () => expect(formatCount(12400), '12.4k'));
    test('millions → M', () => expect(formatCount(1200000), '1.2M'));
  });

  group('dates', () {
    test('ISO complète mois et jour sur 2 chiffres', () {
      expect(formatDateIso(DateTime(2026, 3, 7)), '2026-03-07');
    });

    test('FR jj/mm/aaaa', () {
      expect(formatDateFr(DateTime(2026, 3, 7)), '07/03/2026');
    });
  });

  group('timeAgoFr', () {
    test('moins d\'une minute', () {
      expect(timeAgoFr(DateTime.now()), "à l'instant");
    });

    test('pluriel / singulier', () {
      final now = DateTime.now();
      expect(timeAgoFr(now.subtract(const Duration(minutes: 1, seconds: 5))), 'il y a une minute');
      expect(timeAgoFr(now.subtract(const Duration(hours: 3, minutes: 1))), 'il y a 3 heures');
      expect(timeAgoFr(now.subtract(const Duration(days: 2, hours: 1))), 'il y a 2 jours');
    });
  });
}
