import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/models/track.dart';
import 'package:mkzik_app/player/stream_readiness.dart';

Track _t(String id) => Track(id: id, title: id, artist: 'A', coverUrl: '', duration: Duration.zero, audioUrl: '');

void main() {
  late List<Duration> waits;
  late List<int?> statuses;
  late List<Track> ready;
  late List<bool> gaveUp;
  late bool current;
  late StreamReadinessWatcher w;

  setUp(() {
    waits = [];
    ready = [];
    gaveUp = [];
    current = true;
    statuses = [];
    var i = 0;
    w = StreamReadinessWatcher(
      probe: (t) async => (status: statuses[i++], retryAfter: i == 1 ? const Duration(seconds: 7) : null),
      wait: (d) async => waits.add(d),
    );
  });

  Future<void> run(Track t, {int? status}) => w.watch(
        t,
        firstDelay: w.firstDelay(status),
        isCurrent: () => current,
        onReady: (x) async => ready.add(x),
        onGiveUp: gaveUp.add,
      );

  test('délai initial : 30 s, 10 s après un 429', () {
    expect(w.firstDelay(null), const Duration(seconds: 30));
    expect(w.firstDelay(429), const Duration(seconds: 10));
  });

  test('prêt dès la première sonde (206)', () async {
    statuses = [206];
    await run(_t('a'));
    expect(ready.map((t) => t.id), ['a']);
    expect(gaveUp, isEmpty);
  });

  test('réessaie en suivant le Retry-After du serveur', () async {
    statuses = [429, 200];
    await run(_t('a'));
    expect(waits, [const Duration(seconds: 30), const Duration(seconds: 7)]);
    expect(ready, hasLength(1));
  });

  test('404 : abandon « indisponible »', () async {
    statuses = [404];
    await run(_t('a'));
    expect(gaveUp, [true]);
  });

  test('401 : abandon sans « indisponible » définitif', () async {
    statuses = [401];
    await run(_t('a'));
    expect(gaveUp, [false]);
  });

  test("409 : on n'insiste pas et on ne signale rien", () async {
    statuses = [409];
    await run(_t('a'));
    expect(gaveUp, isEmpty);
    expect(ready, isEmpty);
  });

  test('quatre sondes sans succès : abandon', () async {
    statuses = [503, 503, 503, 503];
    await run(_t('a'));
    expect(gaveUp, [false]);
  });

  test('liste changée pendant la surveillance : abandon silencieux', () async {
    statuses = [206];
    current = false;
    await run(_t('a'));
    expect(ready, isEmpty);
    expect(gaveUp, isEmpty);
  });

  test('une seule surveillance par titre à la fois', () async {
    statuses = [206];
    final f = run(_t('a'));
    expect(w.isWatching('a'), isTrue);
    await run(_t('a')); // ignorée
    await f;
    expect(w.isWatching('a'), isFalse);
    expect(ready, hasLength(1));
  });
}
