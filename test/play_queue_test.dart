import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/models/track.dart';
import 'package:mkzik_app/player/play_queue.dart';

Track _t(String id) => Track(id: id, title: id, artist: 'A', coverUrl: '', duration: Duration.zero, audioUrl: '');
List<Track> _many(int n) => [for (var i = 0; i < n; i++) _t('t$i')];
List<String> _ids(Iterable<Track> l) => [for (final t in l) t.id];

void main() {
  group('load', () {
    test("une autre liste change l'époque, la même la conserve", () {
      final q = PlayQueue();
      expect(q.load(_many(3)), isTrue);
      final e = q.epoch;
      expect(q.load(_many(3)), isFalse);
      expect(q.load(_many(2)), isFalse); // préfixe de la liste connue
      expect(q.epoch, e);
      expect(q.load([_t('x'), _t('y')]), isTrue);
      expect(q.epoch, e + 1);
    });

    test('une page suivante fournie plus tard est adoptée', () {
      final q = PlayQueue()..load(_many(2));
      q.load(_many(2), fetchMore: ({required int limit, required int offset}) async => [_t('p')], pageSize: 1);
      expect(q.hasMore, isTrue);
    });
  });

  group('fenêtre', () {
    test('windowAround : ±10 autour du titre, bornée', () {
      final q = PlayQueue()..load(_many(50));
      final w = q.windowAround(_t('t25'));
      expect(w.length, 21);
      expect(w.first.id, 't15');
      expect(q.windowAround(_t('t0')).length, 11);
    });

    test('windowAround ajoute en tête un titre inconnu', () {
      final q = PlayQueue()..load(_many(3));
      expect(q.windowAround(_t('new')).first.id, 'new');
      expect(q.indexOfId('new'), 0);
    });

    test('upcomingAfter / previousBefore', () async {
      final q = PlayQueue()..load(_many(30));
      expect(_ids(await q.upcomingAfter(_t('t5'))), [for (var i = 6; i <= 15; i++) 't$i']);
      expect(_ids(q.previousBefore(_t('t15'))), [for (var i = 5; i < 15; i++) 't$i']);
      expect(q.previousBefore(_t('t0')), isEmpty);
    });

    test('upcomingAfter demande la page suivante quand la liste est épuisée', () async {
      final calls = <int>[];
      final q = PlayQueue()
        ..load(_many(3), pageSize: 2, hasMore: true, fetchMore: ({required int limit, required int offset}) async {
          calls.add(offset);
          return [_t('p1'), _t('p2')];
        });
      expect(_ids(await q.upcomingAfter(_t('t2'))), ['p1', 'p2']);
      expect(calls, [3]);
      expect(q.hasMore, isTrue); // page pleine → il peut en rester
    });

    test('page incomplète : plus de suite', () async {
      final q = PlayQueue()
        ..load(_many(1), pageSize: 5, fetchMore: ({required int limit, required int offset}) async => [_t('p')]);
      await q.upcomingAfter(_t('t0'));
      expect(q.hasMore, isFalse);
      expect(q.loadedAllUpcoming(_t('p')), isTrue);
    });

    test('page reçue après un changement de liste : ignorée', () async {
      late PlayQueue q;
      q = PlayQueue()
        ..load(_many(1), pageSize: 5, fetchMore: ({required int limit, required int offset}) async {
          q.load([_t('autre')]); // une autre liste est lancée pendant l'appel
          return [_t('p')];
        });
      expect(await q.upcomingAfter(_t('t0')), isEmpty);
      expect(_ids(q.tracks), ['autre']);
    });
  });

  group('navigation', () {
    test('nextOf et previousOf bouclent', () {
      final q = PlayQueue()..load(_many(3));
      expect(q.nextOf(_t('t2'), shuffle: false).id, 't0');
      expect(q.previousOf(_t('t0')).id, 't2');
    });

    test('nextOf aléatoire ne renvoie pas le courant', () {
      final q = PlayQueue()..load(_many(4));
      for (var i = 0; i < 50; i++) {
        expect(q.nextOf(_t('t1'), shuffle: true).id, isNot('t1'));
      }
    });
  });

  group('édition', () {
    test('replaceWindow remplace la portion et dédoublonne', () {
      final q = PlayQueue()..load(_many(6));
      q.replaceWindow([_t('t1'), _t('t2'), _t('t3')], [_t('t3'), _t('t1')]);
      expect(_ids(q.tracks), ['t0', 't3', 't1', 't4', 't5']);
    });

    test('insertAfter, removeById, wrapAt', () {
      final q = PlayQueue()..load(_many(3));
      q.insertAfter(_t('t0'), _t('n'));
      expect(_ids(q.tracks), ['t0', 'n', 't1', 't2']);
      expect(q.removeById('n'), 1);
      expect(q.removeById('absent'), -1);
      expect(q.wrapAt(5)!.id, 't2');
      expect(PlayQueue().wrapAt(0), isNull);
    });

    test('replaceFrom abandonne la suite et la pagination', () {
      final q = PlayQueue()
        ..load(_many(5), fetchMore: ({required int limit, required int offset}) async => [], pageSize: 5);
      q.replaceFrom(_t('t2'), [_t('t2'), _t('r1')]);
      expect(_ids(q.tracks), ['t0', 't1', 't2', 'r1']);
      expect(q.hasMore, isFalse);
    });
  });
}
