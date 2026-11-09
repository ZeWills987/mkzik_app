import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/models/track.dart';
import 'package:mkzik_app/player/core/play_tracker.dart';
import 'package:mkzik_app/player/core/system_media_controls.dart';
import 'package:mkzik_app/player/core/track_resolver.dart';
import 'package:mkzik_app/providers/player_provider.dart';

import 'support/fake_audio_engine.dart';

/// Titre interne avec une URL directement jouable : aucun appel réseau.
Track _t(String id, {int? apiId}) => Track(
      id: id,
      apiId: apiId,
      title: 'Titre $id',
      artist: 'A',
      coverUrl: '',
      duration: const Duration(minutes: 3),
      audioUrl: 'https://cdn.test/$id.mp3',
    );

typedef _Closed = ({int playId, double seconds, bool completed});

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_URL=https://api.test/\nPYTHON_URL=https://py.test/');
  });

  late FakeAudioEngine engine;
  late ProviderContainer container;
  late PlayerNotifier player;
  late List<int> started; // apiId des écoutes démarrées
  late List<_Closed> closed; // écoutes clôturées
  late List<Track> suggestions; // renvoyées par la radio

  final a = _t('a', apiId: 1);
  final b = _t('b', apiId: 2);
  final c = _t('c', apiId: 3);

  PlayerState st() => player.state;
  List<String> ids(Iterable<Track> l) => [for (final t in l) t.id];
  Future<void> settle() => pumpEventQueue();

  setUp(() {
    engine = FakeAudioEngine();
    started = [];
    closed = [];
    suggestions = [];
    final provider = StateNotifierProvider<PlayerNotifier, PlayerState>(
      (ref) => PlayerNotifier(
        ref,
        engine: engine,
        resolver: TrackResolver(),
        tracker: PlayTracker(
          startPlay: (apiId) async {
            started.add(apiId);
            return apiId * 10;
          },
          completePlay: (id, {required listenedSeconds, required completed}) async {
            closed.add((playId: id, seconds: listenedSeconds, completed: completed));
          },
        ),
        mediaControls: NoopMediaControls(),
        radioSuggestions: (_) async => suggestions,
      ),
    );
    container = ProviderContainer();
    addTearDown(container.dispose);
    player = container.read(provider.notifier);
  });

  group('lancer un titre', () {
    test('charge le titre, isLoading retombe, la file est la liste', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      expect(ids(engine.loaded), ['a']);
      expect(st().currentTrack?.id, 'a');
      expect(st().isLoading, isFalse); // régression : ne pas attendre la fin de la lecture
      expect(st().isPlaying, isTrue);
      expect(ids(st().queue), ['a', 'b', 'c']);
      expect(engine.playCalls, 1);
    });

    test('pause puis reprise pendant l\'écoute', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      await player.togglePlayPause();
      await settle();
      expect(engine.pauseCalls, 1);
      expect(st().isPlaying, isFalse);
      await player.togglePlayPause();
      await settle();
      expect(engine.playCalls, 2);
      expect(st().isPlaying, isTrue);
    });

    test('le suivi d\'écoute démarre au lancement du titre (pas à sa fin)', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      expect(started, [1]);
      expect(closed, isEmpty);
    });

    test('relancer le titre en cours le reprend au début sans le recharger', () async {
      await player.playTrack(a, queue: [a, b]);
      await settle();
      await player.playTrack(a, queue: [a, b]);
      await settle();
      expect(engine.loaded, hasLength(1));
      expect(engine.seeks, [Duration.zero]);
    });
  });

  group('enchaînement à la fin d\'un titre', () {
    test('passe au titre suivant et clôt l\'écoute avec la position atteinte', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      engine.emitPosition(const Duration(seconds: 50));
      await settle();
      engine.finishTrack();
      await settle();
      expect(ids(engine.loaded), ['a', 'b']);
      expect(st().currentTrack?.id, 'b');
      expect(closed.single, (playId: 10, seconds: 50.0, completed: false));
      expect(started, [1, 2]);
    });

    test('après le dernier titre, reboucle sur le premier', () async {
      await player.playTrack(c, queue: [a, b, c]);
      await settle();
      engine.finishTrack();
      await settle();
      expect(ids(engine.loaded), ['c', 'a']);
    });

    test('un seul titre : il est rejoué', () async {
      await player.playTrack(a);
      await settle();
      engine.finishTrack();
      await settle();
      expect(engine.loaded, hasLength(1));
      expect(engine.seeks, [Duration.zero]);
      expect(engine.playCalls, 2);
    });

    test('aléatoire : ne rejoue pas le même titre', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      player.toggleShuffle();
      engine.finishTrack();
      await settle();
      expect(engine.loaded.last.id, isNot('a'));
      expect(engine.loaded, hasLength(2));
    });

    test('pas d\'enchaînement double si la fin arrive pendant un chargement', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      engine.loadGate = Completer<void>();
      final f = player.next(); // charge b, bloqué sur le gate
      await settle();
      engine.finishTrack(); // fin de a signalée pendant le chargement de b
      await settle();
      engine.loadGate!.complete();
      await f;
      await settle();
      expect(ids(engine.loaded), ['a', 'b']);
    });
  });

  group('suivant / précédent / saut', () {
    test('suivant puis précédent', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      await player.next();
      await settle();
      expect(st().currentTrack?.id, 'b');
      await player.previous();
      await settle();
      expect(st().currentTrack?.id, 'a');
    });

    test('précédent depuis le premier titre → dernier', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      await player.previous();
      await settle();
      expect(st().currentTrack?.id, 'c');
    });

    test('jumpTo charge le titre demandé', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      await player.jumpTo(2);
      await settle();
      expect(ids(engine.loaded), ['a', 'c']);
      expect(st().currentTrack?.id, 'c');
    });

    test('« suivant » demandé pendant un chargement passe (taps rapides)', () async {
      engine.loadGate = Completer<void>();
      final f = player.playTrack(a, queue: [a, b, c]); // charge a, bloqué
      await settle();
      final g = player.next(); // l'utilisateur saute avant la fin du chargement
      await settle();
      engine.loadGate!.complete();
      await Future.wait([f, g]);
      await settle();
      expect(ids(engine.loaded), ['a', 'b']);
      expect(st().currentTrack?.id, 'b');
      expect(engine.playCalls, 1); // seul b est lancé, a est périmé
    });
  });

  group('répétition', () {
    test('cycleRepeat règle le moteur et persiste sur les titres suivants', () async {
      await player.playTrack(a, queue: [a, b]);
      await settle();
      await player.cycleRepeat();
      expect(st().repeatMode, RepeatMode.one);
      expect(engine.repeatOne, isTrue);
      await player.next();
      await settle();
      expect(engine.repeatOne, isTrue);
      await player.cycleRepeat();
      expect(st().repeatMode, RepeatMode.all);
      expect(engine.repeatOne, isFalse);
    });
  });

  group('échecs de chargement', () {
    test('titre indisponible dans une liste : retiré, on enchaîne', () async {
      engine.loadOutcomes.add(Exception('Titre indisponible (404)'));
      await player.playTrack(a, queue: [a, b]);
      await settle();
      expect(ids(engine.loaded), ['a', 'b']);
      expect(st().currentTrack?.id, 'b');
      expect(ids(st().queue), ['b']);
    });

    test('titre indisponible seul : la lecture s\'arrête', () async {
      engine.loadOutcomes.add(Exception('Titre indisponible (404)'));
      await player.playTrack(a);
      await settle();
      expect(st().isPlaying, isFalse);
      expect(st().isLoading, isFalse);
      expect(engine.playCalls, 0);
    });

    test('deux erreurs réseau : on s\'arrête après deux tentatives', () async {
      engine.loadOutcomes.addAll([Exception('reset'), Exception('reset')]);
      await player.playTrack(a, queue: [a, b]);
      await settle();
      expect(engine.loaded, hasLength(2));
      expect(st().isPlaying, isFalse);
      expect(st().isLoading, isFalse);
      expect(started, isEmpty);
    });

    test('erreur transitoire : la deuxième tentative réussit', () async {
      engine.loadOutcomes.add(Exception('reset'));
      await player.playTrack(a, queue: [a, b]);
      await settle();
      expect(engine.loaded, hasLength(2));
      expect(st().isPlaying, isTrue);
      expect(started, [1]);
    });
  });

  group('erreurs de flux pendant l\'écoute', () {
    test('liste de plusieurs titres : on passe au suivant', () async {
      await player.playTrack(a, queue: [a, b]);
      await settle();
      engine.emitError(Exception('boom'));
      await settle();
      expect(ids(engine.loaded), ['a', 'b']);
      expect(st().currentTrack?.id, 'b');
    });

    test('titre seul : on s\'arrête sans rejouer', () async {
      await player.playTrack(a);
      await settle();
      engine.emitError(Exception('boom'));
      await settle();
      expect(engine.loaded, hasLength(1));
      expect(st().isPlaying, isFalse);
    });

    test('pendant le chargement : ignorée (déjà traitée par le chargement)', () async {
      engine.loadGate = Completer<void>();
      final f = player.playTrack(a, queue: [a, b]);
      await settle();
      engine.emitError(Exception('boom'));
      await settle();
      engine.loadGate!.complete();
      await f;
      await settle();
      expect(ids(engine.loaded), ['a']);
      expect(st().currentTrack?.id, 'a');
    });
  });

  group('file d\'attente', () {
    test('addToList(playNext) insère après le titre courant', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      await player.addToList(_t('d', apiId: 4), playNext: true);
      expect(ids(st().queue), ['a', 'd', 'b', 'c']);
      expect(st().currentIndex, 0);
    });

    test('addToList en fin de file, sans doublon', () async {
      await player.playTrack(a, queue: [a, b]);
      await settle();
      await player.addToList(c);
      await player.addToList(c);
      expect(ids(st().queue), ['a', 'b', 'c']);
    });

    test('removeAt retire un titre, jamais le titre en cours', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      player.removeAt(0); // titre en cours : ignoré
      expect(ids(st().queue), ['a', 'b', 'c']);
      player.removeAt(1);
      expect(ids(st().queue), ['a', 'c']);
    });

    test('reorder garde le titre courant synchronisé', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      player.reorder(2, 0); // c passe en tête
      expect(ids(st().queue), ['c', 'a', 'b']);
      expect(st().currentIndex, 1);
      expect(st().currentTrack?.id, 'a');
    });
  });

  group('mode radio', () {
    // Suggestion Python : titre externe sans URL, à lire via /stream.
    Track ext(String id) => Track(
          id: id,
          title: 'Ext $id',
          artist: 'A',
          coverUrl: '',
          duration: const Duration(minutes: 3),
          audioUrl: '',
          source: 'ytm',
          pageUrl: 'https://music.youtube.com/watch?v=$id',
        );

    test('les suggestions externes sans URL restent dans la file', () async {
      suggestions = [ext('x1'), ext('x2')];
      await player.playTrack(a, queue: [a, b]);
      await settle();
      expect(await player.startRadio(), isTrue);
      expect(ids(st().queue), ['a', 'x1', 'x2']);
      expect(st().currentTrack?.id, 'a');
    });

    test('sans suggestion : la radio ne démarre pas', () async {
      await player.playTrack(a, queue: [a, b]);
      await settle();
      expect(await player.startRadio(), isFalse);
      expect(ids(st().queue), ['a', 'b']);
    });
  });

  group('voisins dans le moteur (notification, sans coupure)', () {
    setUp(() => engine.neighbors = true);

    test('le moteur reçoit le précédent et le suivant du titre lancé', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      expect(engine.neighborNext?.id, 'b');
      expect(engine.neighborPrevious?.id, 'c'); // la liste boucle
    });

    test("moteur sans voisins (Windows) : rien n'est envoyé", () async {
      engine.neighbors = false;
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      expect(engine.setNeighborsCalls, 0);
    });

    test('suivant choisi par le moteur : état aligné, écoute clôturée, voisins recalculés', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      engine.emitPosition(const Duration(seconds: 40));
      await settle();
      engine.moveToNext();
      await settle();
      expect(st().currentTrack?.id, 'b');
      expect(st().currentIndex, 1);
      expect(engine.loaded, hasLength(1)); // pas de rechargement : sans coupure
      expect(closed.single, (playId: 10, seconds: 40.0, completed: false));
      expect(started, [1, 2]);
      expect(engine.neighborPrevious?.id, 'a');
      expect(engine.neighborNext?.id, 'c');
    });

    test('précédent choisi par le moteur (bouton de la notification)', () async {
      await player.playTrack(b, queue: [a, b, c]);
      await settle();
      engine.moveToPrevious();
      await settle();
      expect(st().currentTrack?.id, 'a');
      expect(engine.loaded, hasLength(1));
      expect(engine.neighborNext?.id, 'b');
    });

    test('mode aléatoire : le suivant prévu est celui que « suivant » joue', () async {
      await player.playTrack(a, queue: [a, b, c, _t('d', apiId: 4), _t('e', apiId: 5)]);
      await settle();
      player.toggleShuffle();
      await settle();
      final planned = engine.neighborNext!.id;
      expect(planned, isNot('a'));
      await player.next();
      await settle();
      expect(st().currentTrack?.id, planned);
    });

    test('titre ajouté en « jouer ensuite » : il devient le voisin suivant', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      await player.addToList(_t('d', apiId: 4), playNext: true);
      await settle();
      expect(engine.neighborNext?.id, 'd');
    });

    test('un seul titre : pas de voisin', () async {
      await player.playTrack(a);
      await settle();
      expect(engine.neighborNext, isNull);
      expect(engine.neighborPrevious, isNull);
    });

    test('titre externe (flux sans URL) : pas de voisin, la file enchaîne seule', () async {
      final ext = Track(
        id: 'x',
        title: 'Externe',
        artist: 'A',
        coverUrl: '',
        duration: const Duration(minutes: 3),
        audioUrl: '',
        source: 'ytm',
        pageUrl: 'https://yt/x',
      );
      await player.playTrack(a, queue: [a, ext]);
      await settle();
      expect(engine.neighborNext, isNull);
      engine.finishTrack(); // fin de a : l'enchaînement passe par la file
      await settle();
      expect(engine.loaded.map((t) => t.id), ['a', 'x']);
    });

    test('changement de titre du moteur pendant un chargement : ignoré', () async {
      await player.playTrack(a, queue: [a, b, c]);
      await settle();
      engine.loadGate = Completer<void>();
      final f = player.jumpTo(2);
      await settle();
      engine.moveToNext();
      await settle();
      expect(st().currentTrack?.id, 'c');
      engine.loadGate!.complete();
      await f;
      await settle();
      expect(st().currentTrack?.id, 'c');
    });
  });
}
