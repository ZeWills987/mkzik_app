import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/models/track.dart';

void main() {
  group('formatCount', () {
    test('en dessous de 1000 → brut', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
    });
    test('milliers → suffixe k', () {
      expect(formatCount(1000), '1.0k');
      expect(formatCount(12400), '12.4k');
    });
    test('millions → suffixe M', () {
      expect(formatCount(1000000), '1.0M');
      expect(formatCount(1200000), '1.2M');
    });
  });

  group('timeAgoFr', () {
    String ago(Duration d) => timeAgoFr(DateTime.now().subtract(d));

    test('moins d\'une minute → à l\'instant', () {
      expect(ago(const Duration(seconds: 5)), "à l'instant");
    });
    test('date future → à l\'instant', () {
      expect(timeAgoFr(DateTime.now().add(const Duration(hours: 1))), "à l'instant");
    });
    test('minutes (singulier / pluriel)', () {
      expect(ago(const Duration(minutes: 1)), 'il y a une minute');
      expect(ago(const Duration(minutes: 5)), 'il y a 5 minutes');
    });
    test('heures (singulier / pluriel)', () {
      expect(ago(const Duration(hours: 1)), 'il y a une heure');
      expect(ago(const Duration(hours: 3)), 'il y a 3 heures');
    });
    test('jours (singulier / pluriel)', () {
      expect(ago(const Duration(days: 1)), 'il y a un jour');
      expect(ago(const Duration(days: 5)), 'il y a 5 jours');
    });
    test('mois', () {
      expect(ago(const Duration(days: 45)), 'il y a un mois');
      expect(ago(const Duration(days: 90)), 'il y a 3 mois');
    });
    test('années', () {
      expect(ago(const Duration(days: 400)), 'il y a un an');
      expect(ago(const Duration(days: 800)), 'il y a 2 ans');
    });
  });

  group('Track getters', () {
    const t = Track(
      id: '1',
      title: 'Titre',
      artist: 'Artiste',
      coverUrl: '',
      duration: Duration(minutes: 3, seconds: 5),
      audioUrl: 'https://cdn/song.mp3',
      likesCount: 12400,
    );

    test('durationFormatted zéro-paddé', () {
      expect(t.durationFormatted, '3:05');
      expect(
        const Track(id: 'x', title: '', artist: '', coverUrl: '', duration: Duration.zero, audioUrl: '')
            .durationFormatted,
        '0:00',
      );
    });
    test('likesLabel formaté', () => expect(t.likesLabel, '12.4k'));
    test('hasCover', () {
      expect(t.hasCover, isFalse);
      expect(t.copyWith().hasCover, isFalse);
    });
    test('hasPlayableUrl selon le préfixe http', () {
      expect(t.hasPlayableUrl, isTrue);
      expect(
        const Track(id: 'x', title: '', artist: '', coverUrl: '', duration: Duration.zero, audioUrl: '')
            .hasPlayableUrl,
        isFalse,
      );
    });
    test('publishedLabel null si pas de date', () => expect(t.publishedLabel, isNull));
  });

  group('Track.copyWith / égalité', () {
    const base = Track(
      id: '42',
      title: 'A',
      artist: 'B',
      coverUrl: '',
      duration: Duration.zero,
      audioUrl: '',
      isFavoris: false,
    );
    test('copyWith change isFavoris, garde le reste', () {
      final liked = base.copyWith(isFavoris: true);
      expect(liked.isFavoris, isTrue);
      expect(liked.id, '42');
      expect(liked.title, 'A');
    });
    test('égalité fondée sur l\'id', () {
      expect(base == base.copyWith(isFavoris: true), isTrue);
      expect(base.hashCode, base.copyWith().hashCode);
    });
  });

  group('Track.fromJson', () {
    test('format Symfony (authors liste, date objet PHP)', () {
      final t = Track.fromJson({
        'id': 7,
        'title': 'Blinding Lights',
        'authors': [
          {'username': 'The Weeknd'}
        ],
        'thumbnails': 'https://img/cover.jpg',
        'duration': 200,
        'likes': 12400,
        'listen': 50000,
        'is_favoris': true,
        'platforms': ['youtube'],
        'publication_date': {'date': '2024-06-17 10:00:00.000000'},
      });
      expect(t.apiId, 7);
      expect(t.id, '7');
      expect(t.artist, 'The Weeknd');
      expect(t.coverUrl, 'https://img/cover.jpg');
      expect(t.duration, const Duration(seconds: 200));
      expect(t.likesCount, 12400);
      expect(t.isFavoris, isTrue);
      expect(t.platforms, ['youtube']);
      expect(t.publishedAt, DateTime.parse('2024-06-17 10:00:00.000000'));
    });

    test('format Python (uploader string, source externe, date ISO)', () {
      final t = Track.fromJson({
        'url': 'https://music.youtube.com/watch?v=abc',
        'title': 'External Song',
        'uploader': 'Drake',
        'source': 'ytm',
        'duration': 180,
        'publication_date': '2023-01-02T03:04:05Z',
      });
      // pas d'id → url sert d'id stable
      expect(t.id, 'https://music.youtube.com/watch?v=abc');
      expect(t.apiId, isNull);
      expect(t.artist, 'Drake');
      expect(t.needsImport, isTrue);
      expect(t.isExternal, isTrue);
      expect(t.publishedAt, DateTime.parse('2023-01-02T03:04:05Z'));
    });

    test('champs absents → valeurs par défaut sûres', () {
      final t = Track.fromJson({'id': 1, 'title': 'X'});
      expect(t.artist, '');
      expect(t.coverUrl, '');
      expect(t.duration, Duration.zero);
      expect(t.likesCount, 0);
      expect(t.isFavoris, isFalse);
      expect(t.needsImport, isFalse);
      expect(t.publishedAt, isNull);
      expect(t.platforms, isEmpty);
    });
  });
}
