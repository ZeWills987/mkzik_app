import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/models/track.dart';
import 'package:mkzik_app/player/core/player_core.dart';
import 'package:mkzik_app/player/core/track_resolver.dart';
import 'package:mkzik_app/services/track_service.dart';

import 'support/fake_audio_engine.dart';

Track _track({
  String id = 't1',
  int? apiId,
  String source = '',
  String pageUrl = '',
  String audioUrl = '',
}) =>
    Track(
      id: id,
      apiId: apiId,
      title: 'Titre $id',
      artist: 'A',
      coverUrl: '',
      duration: const Duration(minutes: 3),
      audioUrl: audioUrl,
      source: source,
      pageUrl: pageUrl,
    );

void main() {
  late FakeAudioEngine engine;
  late PlayerCore core;

  // Titre externe (flux Python) et titre interne (URL signée).
  final stream = _track(id: 'yt', source: 'ytm', pageUrl: 'https://yt/x');
  final internal = _track(id: 'in', apiId: 5);

  setUp(() {
    engine = FakeAudioEngine();
    core = PlayerCore(
      engine: engine,
      resolver: TrackResolver(
        streamUrl: (p) => 'https://py.test/stream?url=$p',
        signOne: (id) async => SignedAudio('https://s3.test/$id.mp3', DateTime(2100)),
        signMany: (ids) async => {for (final id in ids) id: SignedAudio('https://s3.test/$id.mp3', DateTime(2100))},
        now: () => DateTime(2026),
      ),
    );
  });

  group('succès', () {
    test('résout, charge, règle la répétition et lance la lecture', () async {
      final r = await core.load(stream, repeatOne: true);
      expect(r, isA<LoadStarted>());
      expect((r as LoadStarted).track.audioUrl, 'https://py.test/stream?url=https://yt/x');
      expect(engine.loaded.single.audioUrl, r.track.audioUrl);
      expect(engine.repeatOne, isTrue);
      expect(engine.playCalls, 1);
    });

    test('titre interne : URL signée', () async {
      final r = await core.load(internal) as LoadStarted;
      expect(r.track.audioUrl, 'https://s3.test/5.mp3');
    });

    test('onResolved est appelé avec le titre résolu, avant le chargement', () async {
      Track? seen;
      int? loadedWhenCalled;
      await core.load(internal, onResolved: (t) {
        seen = t;
        loadedWhenCalled = engine.loaded.length;
      });
      expect(seen?.audioUrl, 'https://s3.test/5.mp3');
      expect(loadedWhenCalled, 0);
    });
  });

  group('annulation (taps rapides)', () {
    test('périmé après la résolution : rien n\'est chargé', () async {
      final r = await core.load(internal, isStale: () => true);
      expect(r, isA<LoadStale>());
      expect(engine.loaded, isEmpty);
      expect(engine.playCalls, 0);
    });

    test('périmé après le chargement : la lecture ne démarre pas', () async {
      var calls = 0;
      // Faux au premier contrôle (après résolution), vrai au second (après chargement).
      final r = await core.load(internal, isStale: () => ++calls > 1);
      expect(r, isA<LoadStale>());
      expect(engine.loaded, hasLength(1));
      expect(engine.playCalls, 0);
    });

    test('périmé pendant une erreur : pas de classification', () async {
      engine.loadOutcomes.add(Exception('HTTP 404'));
      var calls = 0;
      final r = await core.load(internal, isStale: () => ++calls > 1);
      expect(r, isA<LoadStale>());
    });
  });

  test('aucune URL jouable', () async {
    final r = await core.load(_track(id: 'x')); // ni apiId, ni URL
    expect(r, isA<LoadNoSource>());
    expect(engine.loaded, isEmpty);
  });

  group('échecs et nouvelle tentative', () {
    test('erreur transitoire sur un titre interne : on réessaie et ça passe', () async {
      engine.loadOutcomes.add(Exception('Connection reset'));
      final r = await core.load(internal);
      expect(r, isA<LoadStarted>());
      expect(engine.loaded, hasLength(2));
      expect(engine.playCalls, 1);
    });

    test('deux erreurs réseau → network', () async {
      engine.loadOutcomes.addAll([Exception('reset'), Exception('reset')]);
      final r = await core.load(internal) as LoadFailed;
      expect(r.kind, LoadFailureKind.network);
      expect(engine.loaded, hasLength(2));
      expect(engine.playCalls, 0);
    });

    test('deux délais dépassés → timeout', () async {
      engine.loadOutcomes.addAll([TimeoutException('t'), TimeoutException('t')]);
      final r = await core.load(internal) as LoadFailed;
      expect(r.kind, LoadFailureKind.timeout);
    });

    test('409 : annulé côté serveur, une seule tentative', () async {
      engine.loadOutcomes.add(Exception('HTTP 409'));
      final r = await core.load(internal) as LoadFailed;
      expect(r.kind, LoadFailureKind.cancelledByServer);
      expect(r.status, 409);
      expect(engine.loaded, hasLength(1));
    });

    test('404 : indisponible, une seule tentative', () async {
      engine.loadOutcomes.add(Exception('Titre indisponible (404)'));
      final r = await core.load(internal) as LoadFailed;
      expect(r.kind, LoadFailureKind.unavailable);
      expect(engine.loaded, hasLength(1));
    });

    test('flux Python + délai dépassé : pas prêt, pas de nouvelle tentative', () async {
      engine.loadOutcomes.add(TimeoutException('t'));
      final r = await core.load(stream) as LoadFailed;
      expect(r.kind, LoadFailureKind.streamNotReady);
      expect(engine.loaded, hasLength(1));
    });

    test('flux Python + 429 : pas prêt, le code est transmis', () async {
      engine.loadOutcomes.add(Exception('HTTP 429'));
      final r = await core.load(stream) as LoadFailed;
      expect(r.kind, LoadFailureKind.streamNotReady);
      expect(r.status, 429);
    });

    test('flux Python + 404 : indisponible (pas « pas prêt »)', () async {
      engine.loadOutcomes.add(Exception('HTTP 404'));
      final r = await core.load(stream) as LoadFailed;
      expect(r.kind, LoadFailureKind.unavailable);
    });

    test('flux Python + erreur réseau : on réessaie une fois', () async {
      engine.loadOutcomes.addAll([Exception('reset'), Exception('reset')]);
      final r = await core.load(stream) as LoadFailed;
      expect(r.kind, LoadFailureKind.network);
      expect(engine.loaded, hasLength(2));
    });

    test('délai dépassé sur un titre interne (non flux) : on réessaie', () async {
      engine.loadOutcomes.add(TimeoutException('t'));
      final r = await core.load(internal);
      expect(r, isA<LoadStarted>());
      expect(engine.loaded, hasLength(2));
    });
  });

  group('commandes', () {
    test('togglePlayPause : lance puis met en pause', () async {
      await core.togglePlayPause();
      expect(engine.playCalls, 1);
      expect(core.isPlaying, isTrue);
      await core.togglePlayPause();
      expect(engine.pauseCalls, 1);
      expect(core.isPlaying, isFalse);
    });

    test('seek ignoré tant que la source n\'est pas prête', () async {
      engine.ready = false;
      await core.seek(const Duration(seconds: 30));
      expect(engine.seeks, isEmpty);
      engine.ready = true;
      await core.seek(const Duration(seconds: 30));
      expect(engine.seeks, [const Duration(seconds: 30)]);
    });

    test('restart : revient au début et relance ; faux si pas prêt', () async {
      engine.ready = false;
      expect(await core.restart(), isFalse);
      engine.ready = true;
      expect(await core.restart(), isTrue);
      expect(engine.seeks, [Duration.zero]);
      expect(engine.playCalls, 1);
    });
  });
}
