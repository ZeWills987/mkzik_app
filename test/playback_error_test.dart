import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/player/core/playback_error.dart';

void main() {
  group('isTrackUnavailable', () {
    test('404 dans le message', () {
      expect(isTrackUnavailable(Exception('(0) Source error: HTTP 404')), isTrue);
    });

    test('libellé du proxy', () {
      expect(isTrackUnavailable('Titre indisponible'), isTrue);
    });

    test('format non supporté par WinRT', () {
      expect(isTrackUnavailable('sourceNotSupportedError'), isTrue);
    });

    test('erreurs transitoires ne sont pas « indisponible »', () {
      expect(isTrackUnavailable(Exception('HTTP 502')), isFalse);
      expect(isTrackUnavailable(Exception('Connection reset')), isFalse);
    });
  });

  group('httpStatusIn', () {
    test('lit les codes connus', () {
      for (final code in [404, 409, 429, 502, 503, 504]) {
        expect(httpStatusIn(Exception('Response code: $code')), code);
      }
    });

    test('ignore les autres nombres et les codes collés à du texte', () {
      expect(httpStatusIn(Exception('HTTP 500')), isNull);
      expect(httpStatusIn(Exception('port 14040')), isNull);
      expect(httpStatusIn('aucune info'), isNull);
    });
  });

  test('statuts transitoires', () {
    expect(transientHttpStatuses, {429, 502, 503, 504});
  });
}
