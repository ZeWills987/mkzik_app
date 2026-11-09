import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/models/track.dart';
import 'package:mkzik_app/player/core/track_resolver.dart';
import 'package:mkzik_app/services/track_service.dart';

Track _track({
  String id = 't1',
  int? apiId,
  String audioUrl = '',
  String source = '',
  bool inMkzik = false,
  String pageUrl = '',
}) =>
    Track(
      id: id,
      apiId: apiId,
      title: 'Titre $id',
      artist: 'Artiste',
      coverUrl: '',
      duration: const Duration(minutes: 3),
      audioUrl: audioUrl,
      source: source,
      inMkzik: inMkzik,
      pageUrl: pageUrl,
    );

void main() {
  late DateTime now;
  late int oneCalls;
  late int manyCalls;
  late List<List<int>> manyArgs;
  // Réponse de la signature : expire dans 1 h par défaut.
  late DateTime? expiry;

  TrackResolver build() => TrackResolver(
        now: () => now,
        streamUrl: (p) => 'https://py.test/stream?url=$p',
        signOne: (id) async {
          oneCalls++;
          return SignedAudio('https://s3.test/$id.mp3', expiry);
        },
        signMany: (ids) async {
          manyCalls++;
          manyArgs.add(ids);
          return {for (final id in ids) id: SignedAudio('https://s3.test/$id.mp3', expiry)};
        },
      );

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    expiry = now.add(const Duration(hours: 1));
    oneCalls = 0;
    manyCalls = 0;
    manyArgs = [];
  });

  group('resolvePlayable', () {
    test('externe pur (needsStream) → flux Python, aucune signature', () async {
      final r = build();
      final t = _track(source: 'ytm', pageUrl: 'https://yt/watch?v=1');
      final out = await r.resolvePlayable(t);
      expect(out!.audioUrl, 'https://py.test/stream?url=https://yt/watch?v=1');
      expect(oneCalls, 0);
    });

    test('externe sans URL de page → null', () async {
      expect(await build().resolvePlayable(_track(source: 'sc')), isNull);
    });

    test('interne sans URL → URL signée', () async {
      final out = await build().resolvePlayable(_track(apiId: 7));
      expect(out!.audioUrl, 'https://s3.test/7.mp3');
      expect(oneCalls, 1);
    });

    test('URL directement jouable → inchangée, aucune signature', () async {
      final t = _track(apiId: 7, audioUrl: 'https://cdn.test/a.mp3');
      final out = await build().resolvePlayable(t);
      expect(out!.audioUrl, 'https://cdn.test/a.mp3');
      expect(oneCalls, 0);
    });

    test('externe déjà dans la BD (inMkzik) → URL signée, pas de flux', () async {
      final t = _track(apiId: 9, source: 'ytm', inMkzik: true, pageUrl: 'https://yt/x');
      final out = await build().resolvePlayable(t);
      expect(out!.audioUrl, 'https://s3.test/9.mp3');
    });

    test('ni URL ni apiId → null', () async {
      expect(await build().resolvePlayable(_track()), isNull);
    });
  });

  group('cache des URL signées', () {
    test('URL fraîche réutilisée sans rappeler l\'API', () async {
      final r = build();
      await r.signedUrlFor(1);
      await r.signedUrlFor(1);
      expect(oneCalls, 1);
    });

    test('URL qui expire dans la marge de 60 s → re-signée', () async {
      final r = build();
      expiry = now.add(const Duration(seconds: 30));
      await r.signedUrlFor(1);
      await r.signedUrlFor(1);
      expect(oneCalls, 2);
    });

    test('expiration inconnue → jamais considérée fraîche', () async {
      final r = build();
      expiry = null;
      await r.signedUrlFor(1);
      await r.signedUrlFor(1);
      expect(oneCalls, 2);
    });

    test('l\'expiration est évaluée à l\'instant courant', () async {
      final r = build();
      await r.signedUrlFor(1);
      now = now.add(const Duration(hours: 2)); // l'URL a expiré entre-temps
      await r.signedUrlFor(1);
      expect(oneCalls, 2);
    });

    test('signedUrlFor renvoie null si l\'API ne signe pas', () async {
      final r = TrackResolver(signOne: (_) async => null, signMany: (_) async => {});
      expect(await r.signedUrlFor(1), isNull);
    });

    test('isLoadedSourceValid : inconnu → vrai, périmé → faux', () async {
      final r = build();
      final t = _track(apiId: 5);
      expect(r.isLoadedSourceValid(t), isTrue); // jamais signé
      await r.signedUrlFor(5);
      expect(r.isLoadedSourceValid(t), isTrue);
      now = now.add(const Duration(hours: 2));
      expect(r.isLoadedSourceValid(t), isFalse);
      expect(r.isLoadedSourceValid(_track()), isTrue); // sans apiId
    });
  });

  group('signedUrlsFor (batch)', () {
    test('une seule requête pour les ids manquants, le cache sert les autres', () async {
      final r = build();
      await r.signedUrlFor(1); // 1 déjà en cache
      final out = await r.signedUrlsFor([1, 2, 3]);
      expect(out, {1: 'https://s3.test/1.mp3', 2: 'https://s3.test/2.mp3', 3: 'https://s3.test/3.mp3'});
      expect(manyCalls, 1);
      expect(manyArgs.single, [2, 3]);
    });

    test('tout en cache → aucune requête', () async {
      final r = build();
      await r.signedUrlsFor([1, 2]);
      await r.signedUrlsFor([1, 2]);
      expect(manyCalls, 1);
    });

    test('liste vide → aucune requête', () async {
      await build().signedUrlsFor([]);
      expect(manyCalls, 0);
    });
  });

  group('resolveForQueue', () {
    test('URL jouable → telle quelle', () async {
      final t = _track(audioUrl: 'https://cdn.test/a.mp3');
      expect(await build().resolveForQueue(t), same(t));
    });

    test('flux Python → null (résolu seulement quand il devient courant)', () async {
      final t = _track(source: 'ytm', pageUrl: 'https://yt/x');
      expect(await build().resolveForQueue(t), isNull);
    });

    test('interne → URL signée', () async {
      final out = await build().resolveForQueue(_track(apiId: 4));
      expect(out!.audioUrl, 'https://s3.test/4.mp3');
    });

    test('rien de résoluble → null', () async {
      expect(await build().resolveForQueue(_track()), isNull);
    });
  });

  group('resolveBatch', () {
    test('conserve l\'ordre, null pour l\'injouable, un seul batch', () async {
      final r = build();
      final tracks = [
        _track(id: 'a', apiId: 1),
        _track(id: 'b', audioUrl: 'https://cdn.test/b.mp3'),
        _track(id: 'c', source: 'ytm', pageUrl: 'https://yt/c'),
        _track(id: 'd'), // injouable
        _track(id: 'e', apiId: 2),
      ];
      final out = await r.resolveBatch(tracks);
      expect(out.map((t) => t?.id), ['a', 'b', 'c', null, 'e']);
      expect(out[0]!.audioUrl, 'https://s3.test/1.mp3');
      expect(out[1]!.audioUrl, 'https://cdn.test/b.mp3');
      expect(out[2]!.audioUrl, 'https://py.test/stream?url=https://yt/c');
      expect(out[4]!.audioUrl, 'https://s3.test/2.mp3');
      expect(manyCalls, 1);
      expect(manyArgs.single, [1, 2]);
    });
  });
}
