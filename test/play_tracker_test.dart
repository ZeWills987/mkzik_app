import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/models/track.dart';
import 'package:mkzik_app/player/core/play_tracker.dart';

Track _track(String id, {int? apiId, Duration duration = const Duration(minutes: 3)}) => Track(
      id: id,
      apiId: apiId,
      title: id,
      artist: 'a',
      coverUrl: '',
      duration: duration,
      audioUrl: '',
    );

typedef _Closed = ({int playId, double seconds, bool completed});

void main() {
  late List<int> started;
  late List<_Closed> closed;
  late Completer<int?>? gate; // si non null, startPlay attend ce Completer

  PlayTracker build({int? Function(int apiId)? playIdFor}) => PlayTracker(
        startPlay: (apiId) async {
          started.add(apiId);
          if (gate != null) return gate!.future;
          return playIdFor != null ? playIdFor(apiId) : apiId * 10;
        },
        completePlay: (id, {required listenedSeconds, required completed}) async {
          closed.add((playId: id, seconds: listenedSeconds, completed: completed));
        },
      );

  setUp(() {
    started = [];
    closed = [];
    gate = null;
  });

  test('begin démarre une écoute avec l\'apiId, tracked reflète le titre', () async {
    final t = build();
    await t.begin(_track('a', apiId: 1));
    expect(started, [1]);
    expect(t.tracked?.id, 'a');
  });

  test('finish envoie la position max (pas la dernière) et completed=false sous 90 %', () async {
    final t = build();
    await t.begin(_track('a', apiId: 1)); // 3 min = 180 s
    t.onPosition(const Duration(seconds: 100));
    t.onPosition(const Duration(seconds: 40)); // retour en arrière : le max reste 100
    await t.finish();
    expect(closed.single, (playId: 10, seconds: 100.0, completed: false));
  });

  test('completed=true à partir de 90 % de la durée', () async {
    final t = build();
    await t.begin(_track('a', apiId: 1));
    t.onPosition(const Duration(seconds: 162)); // 162 / 180 = 90 % pile
    await t.finish();
    expect(closed.single.completed, isTrue);
  });

  test('durée inconnue (0) → jamais completed', () async {
    final t = build();
    await t.begin(_track('a', apiId: 1, duration: Duration.zero));
    t.onPosition(const Duration(minutes: 10));
    await t.finish();
    expect(closed.single.completed, isFalse);
  });

  test('titre sans apiId : pas de POST, finish n\'envoie rien', () async {
    final t = build();
    await t.begin(_track('ext'));
    t.onPosition(const Duration(seconds: 30));
    await t.finish();
    expect(started, isEmpty);
    expect(closed, isEmpty);
  });

  test('startPlay sans playId (pas connecté) : finish n\'envoie rien', () async {
    final t = build(playIdFor: (_) => null);
    await t.begin(_track('a', apiId: 1));
    await t.finish();
    expect(closed, isEmpty);
  });

  test('finish est idempotent et remet à zéro', () async {
    final t = build();
    await t.begin(_track('a', apiId: 1));
    await t.finish();
    await t.finish();
    expect(closed, hasLength(1));
    expect(t.tracked, isNull);
  });

  test('onPosition sans écoute en cours est ignorée (pas de fuite sur la suivante)', () async {
    final t = build();
    t.onPosition(const Duration(seconds: 500)); // rien n'est suivi
    await t.begin(_track('a', apiId: 1));
    await t.finish();
    expect(closed.single.seconds, 0.0);
  });

  test('chaque écoute repart de zéro', () async {
    final t = build();
    await t.begin(_track('a', apiId: 1));
    t.onPosition(const Duration(seconds: 90));
    await t.finish();
    await t.begin(_track('b', apiId: 2));
    t.onPosition(const Duration(seconds: 5));
    await t.finish();
    expect(closed.map((c) => (c.playId, c.seconds)), [(10, 90.0), (20, 5.0)]);
  });

  test('skip rapide : l\'écoute dont la réponse arrive trop tard est clôturée à 0 s', () async {
    final slow = Completer<int?>();
    gate = slow;
    final t = build();
    final first = t.begin(_track('a', apiId: 1)); // attend la réponse du backend
    // L'utilisateur saute avant la réponse : on clôt (rien à clôturer encore) et on enchaîne.
    await t.finish();
    gate = null;
    await t.begin(_track('b', apiId: 2));
    // La réponse de la première écoute arrive enfin : elle ne correspond plus au titre suivi.
    slow.complete(111);
    await first;
    expect(closed.where((c) => c.playId == 111).single, (playId: 111, seconds: 0.0, completed: false));
    // Et l'écoute du titre b n'est pas touchée.
    expect(t.tracked?.id, 'b');
  });
}
