import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/utils/media.dart';

void main() {
  // mediaUrl lit ApiConfig.baseUrl (→ dotenv). On fixe une base déterministe.
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_URL=https://cdn.mkzik.test/\nPYTHON_URL=https://py.mkzik.test/');
  });

  group('mediaUrl', () {
    test('chaîne vide → vide', () {
      expect(mediaUrl(''), '');
    });

    test('placeholders connus → vide (fallback dégradé)', () {
      expect(mediaUrl('https://x/unknow.jpg'), '');
      expect(mediaUrl('https://x/unknown.jpg'), '');
      expect(mediaUrl('https://x/default.jpg'), '');
      expect(mediaUrl('https://X/UNKNOW.JPG'), ''); // insensible à la casse
    });

    test('hôte local réécrit vers la base API', () {
      expect(
        mediaUrl('http://localhost:8000/uploads/a.jpg'),
        'https://cdn.mkzik.test/uploads/a.jpg',
      );
      expect(
        mediaUrl('http://127.0.0.1/uploads/b.jpg'),
        'https://cdn.mkzik.test/uploads/b.jpg',
      );
    });

    test('chemin relatif → préfixé par la base API (slash géré)', () {
      expect(mediaUrl('uploads/c.jpg'), 'https://cdn.mkzik.test/uploads/c.jpg');
      expect(mediaUrl('/uploads/d.jpg'), 'https://cdn.mkzik.test/uploads/d.jpg');
    });

    test('URL S3 sans clé d\'objet → vide (invalide)', () {
      expect(mediaUrl('https://s3.eu-west-3.amazonaws.com/'), '');
      expect(mediaUrl('https://s3.eu-west-3.amazonaws.com'), '');
    });

    test('URL S3 valide avec objet → inchangée', () {
      const u = 'https://s3.eu-west-3.amazonaws.com/bucket/cover.jpg';
      expect(mediaUrl(u), u);
    });

    test('URL https normale → inchangée', () {
      const u = 'https://img.distante.com/photo.png';
      expect(mediaUrl(u), u);
    });
  });
}
