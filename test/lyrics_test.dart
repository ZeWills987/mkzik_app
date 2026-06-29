import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/models/lyrics.dart';

void main() {
  group('Lyrics.fromJson — format Python (flux direct)', () {
    test('synchronisé : found+synced+lines → karaoké exploitable', () {
      final l = Lyrics.fromJson(const {
        'found': true,
        'synced': true,
        'source': 'Source: Musixmatch',
        'lyrics': 'Ligne 1\nLigne 2',
        'lines': [
          {'time': 12000, 'text': 'Ligne 1'},
          {'time': 15500, 'text': 'Ligne 2'},
        ],
      });
      expect(l.isEmpty, isFalse);
      expect(l.synced, isTrue);
      expect(l.hasSyncedLines, isTrue);
      expect(l.lines.length, 2);
      expect(l.lines.first.timeMs, 12000);
      expect(l.lines[1].text, 'Ligne 2');
    });

    test('non synchronisé : found+synced=false → texte brut, pas de lignes', () {
      final l = Lyrics.fromJson(const {
        'found': true,
        'synced': false,
        'source': 'lyrics.ovh',
        'lyrics': 'Couplet brut',
        'lines': null,
      });
      expect(l.isEmpty, isFalse);
      expect(l.synced, isFalse);
      expect(l.hasSyncedLines, isFalse);
      expect(l.text, 'Couplet brut');
      expect(l.lines, isEmpty);
    });

    test('rien trouvé : found=false → paroles vides', () {
      final l = Lyrics.fromJson(const {
        'found': false,
        'synced': false,
        'source': null,
        'lyrics': null,
        'lines': null,
      });
      expect(l.isEmpty, isTrue);
      expect(l.hasSyncedLines, isFalse);
    });
  });

  group('Lyrics.fromJson — format Symfony (BD)', () {
    test('clés lyrics_synced/lyrics_lines toujours supportées', () {
      final l = Lyrics.fromJson(const {
        'lyrics': 'A\nB',
        'lyrics_synced': true,
        'lyrics_lines': [
          {'time': 0, 'text': 'A'},
          {'time': 2000, 'text': 'B'},
        ],
      });
      expect(l.hasSyncedLines, isTrue);
      expect(l.lines.length, 2);
      expect(l.lines.last.timeMs, 2000);
    });
  });
}
