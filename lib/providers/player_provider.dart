import 'dart:async';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/track.dart';
import '../player/core/audio_engine.dart';
import '../player/core/just_audio_engine.dart';
import '../player/core/platform_media_controls.dart';
import '../player/core/play_tracker.dart';
import '../player/core/playback_error.dart';
import '../player/core/player_core.dart';
import '../player/core/system_media_controls.dart';
import '../player/core/track_resolver.dart';
import '../player/queue_navigation.dart';
import '../services/external_track_service.dart';
import '../services/track_service.dart';
import '../services/radio_service.dart';
import '../utils/format.dart';
import 'import_provider.dart';
import 'favourites_provider.dart';
import 'notice_provider.dart';
import 'paginated_tracks_provider.dart' show TrackPageFetcher;
import '../utils/logger.dart';

// Mode de répétition. `off` est conservé pour compat mais n'est plus utilisé :
// on tourne toujours en boucle de file (all) ↔ répétition d'un titre (one).
enum RepeatMode { off, all, one }

// État immuable du player
class PlayerState {
  final Track? currentTrack;
  final bool isPlaying;
  final bool isLoading; // résolution + mise en tampon du titre, avant le démarrage réel
  final bool isLiked;
  final bool isShuffle;
  final RepeatMode repeatMode;
  final List<Track> queue;
  final int currentIndex;
  final Duration position;
  final Duration duration;
  final double bufferedProgress;

  const PlayerState({
    this.currentTrack,
    this.isPlaying = false,
    this.isLoading = false,
    this.isLiked = false,
    this.isShuffle = false,
    this.repeatMode = RepeatMode.all,
    this.queue = const [],
    this.currentIndex = 0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedProgress = 0.0,
  });

  PlayerState copyWith({
    Track? currentTrack,
    bool? isPlaying,
    bool? isLoading,
    bool? isLiked,
    bool? isShuffle,
    RepeatMode? repeatMode,
    List<Track>? queue,
    int? currentIndex,
    Duration? position,
    Duration? duration,
    double? bufferedProgress,
  }) {
    return PlayerState(
      currentTrack: currentTrack ?? this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      isLiked: isLiked ?? this.isLiked,
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedProgress: bufferedProgress ?? this.bufferedProgress,
    );
  }

  double get progress {
    if (duration.inMilliseconds == 0) return 0.0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  bool get hasNext => currentIndex < queue.length - 1;
  bool get hasPrevious => currentIndex > 0;
  // next/previous étant cycliques, on peut sauter dès qu'il y a >1 titre
  bool get canSkip => queue.length > 1;

  String get positionFormatted => formatDuration(position);
  String get durationFormatted => formatDuration(duration);
}

/// La file d'attente et l'état du lecteur pour l'interface.
///
/// « Jouer UN titre » (résolution de l'URL, moteur audio, suivi d'écoute,
/// contrôles média système) vit dans `lib/player/core/` : ici on ne gère que la
/// file (liste d'origine, fenêtre affichée, pagination, radio) et on décide quoi
/// faire quand un titre échoue. Le moteur ne lit qu'un titre à la fois ; la
/// file enchaîne les titres elle-même.
class PlayerNotifier extends StateNotifier<PlayerState> {
  PlayerNotifier(
    this._ref, {
    AudioEngine? engine,
    TrackResolver? resolver,
    PlayTracker? tracker,
    SystemMediaControls? mediaControls,
  })  : _resolver = resolver ?? TrackResolver(),
        _tracker = tracker ?? PlayTracker(),
        _media = mediaControls ?? createSystemMediaControls(),
        super(const PlayerState()) {
    _engine = engine ?? JustAudioEngine();
    _core = PlayerCore(engine: _engine, resolver: _resolver);
    _listenToEngine();
  }

  final Ref _ref;

  late final AudioEngine _engine;
  late final PlayerCore _core;
  final TrackResolver _resolver;
  final PlayTracker _tracker;
  final SystemMediaControls _media;
  final List<StreamSubscription<Object?>> _subs = [];

  // Jeton anti-concurrence : invalide les chargements obsolètes (taps rapides)
  int _playToken = 0;

  // Liste d'origine de la lecture (tout ce qui est connu : pages déjà chargées).
  // La file affichée (state.queue) n'en est qu'une fenêtre autour du titre courant.
  List<Track> _source = [];
  TrackPageFetcher? _sourceFetch; // page suivante de la liste (API), null si liste fixe
  int _sourcePageSize = 20;
  int _sourceFetchedCount = 0; // offset API = titres déjà reçus de la source
  bool _sourceHasMore = false;
  bool _extendingForward = false;
  bool _extendingBackward = false;
  static const _kWindow = 10; // titres chargés avant / après le titre courant

  // Flux Python en cours de résolution en arrière-plan (ids de track).
  final Set<String> _pendingStreams = {};
  // Change quand l'utilisateur lance une autre liste → annule les réinsertions.
  int _queueEpoch = 0;

  // Autoplay radio : extension de la file par suggestions en fin de liste.
  bool _radioBusy = false; // une extension est déjà en cours
  String? _radioFromId; // id du titre depuis lequel on a déjà étendu (anti-doublon)

  // Bannière « Chargement du flux… » actuellement affichée (import_provider) —
  // permet de la fermer EN FORCE dès qu'un nouveau titre est demandé, sans
  // attendre que la résolution obsolète se termine (ou timeout) d'elle-même.
  String? _activeStreamJobId;

  void _listenToEngine() {
    // Position en temps réel (alimente aussi le suivi d'écoute).
    _subs.add(_engine.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
      _tracker.onPosition(pos);
    }, onError: (Object e) => mkLog('Mkzik ▶ positionStream erreur : $e')));

    // Durée du titre quand elle est connue.
    _subs.add(_engine.durationStream.listen((dur) {
      if (dur != null) state = state.copyWith(duration: dur);
    }, onError: (Object e) => mkLog('Mkzik ▶ durationStream erreur : $e')));

    // Suivi du buffering (absent sur Windows : WinRT ne le supporte pas).
    final buffered = _engine.bufferedStream;
    if (buffered != null) {
      _subs.add(buffered.listen((b) {
        final dur = state.duration.inMilliseconds;
        if (dur <= 0) return;
        state = state.copyWith(bufferedProgress: (b.inMilliseconds / dur).clamp(0.0, 1.0));
      }, onError: (_) {}));
    }

    // Sync isPlaying avec l'état réel du lecteur.
    _subs.add(_engine.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
      _media.setPlaying(playing);
    }, onError: (Object e) => mkLog('Mkzik ▶ playingStream erreur : $e')));

    // Fin de titre → on enchaîne sur le suivant de la liste.
    _subs.add(_engine.completedStream.listen((_) {
      unawaited(Future.microtask(() => _advanceFromQueue(auto: true)));
    }, onError: (Object e) => mkLog('Mkzik ▶ completedStream erreur : $e')));

    // Erreurs de flux EN COURS de lecture (URL signée expirée, stream yt-dlp qui meurt…).
    _subs.add(_engine.errorStream.listen(_onPlaybackError));

    // Touches média du système (Windows).
    _subs.add(_media.buttons.listen((b) {
      switch (b) {
        case MediaButton.playPause:
          unawaited(togglePlayPause());
        case MediaButton.next:
          unawaited(next());
        case MediaButton.previous:
          unawaited(previous());
      }
    }));
  }

  /// Erreur de flux pendant l'écoute : sans ce handler la lecture s'arrête en
  /// silence. On informe l'utilisateur et on enchaîne sur le titre suivant s'il y en a un.
  /// Pendant le chargement d'un titre, l'erreur est déjà traitée par [_startTrack].
  void _onPlaybackError(Object e) {
    if (state.isLoading) return;
    mkLog('Mkzik ▶ erreur de flux en lecture : $e');
    final t = state.currentTrack;
    final unavailable = isTrackUnavailable(e);
    final notices = _ref.read(noticeProvider.notifier);
    if (t != null && _source.length > 1) {
      notices.show(unavailable
          ? '« ${t.title} » indisponible — titre suivant'
          : 'Erreur réseau sur « ${t.title} » — titre suivant');
      // Microtask pour sortir du dispatch d'erreur du flux avant de relancer le lecteur.
      unawaited(Future.microtask(next));
    } else {
      notices.show(unavailable ? 'Titre indisponible' : 'Lecture interrompue, réessaie');
      state = state.copyWith(isPlaying: false);
    }
  }

  // Démarre une écoute pour [t] (le suivi lui-même vit dans PlayTracker).
  Future<void> _beginPlay(Track t) async {
    _media.showTrack(t); // panneau média Windows (rien ailleurs)
    await _tracker.begin(t);
  }

  /// Titre demandé = titre déjà chargé, URL encore valide → retour au début
  /// sans rappel API. Renvoie false s'il faut recharger.
  Future<bool> _restartCurrent(Track track) async {
    final cur = state.currentTrack;
    if (cur == null || cur.id != track.id || state.isLoading) return false;
    if (!_resolver.isLoadedSourceValid(cur)) return false;
    if (!await _core.restart()) return false;
    await _tracker.finish();
    unawaited(_beginPlay(cur));
    return true;
  }

  /// Retire le titre en échec de la file et enchaîne sur le suivant.
  void _skipFailed(List<Track> q, int idx) {
    final failedId = q[idx].id;
    final srcIdx = _source.indexWhere((t) => t.id == failedId);
    if (srcIdx >= 0) _source.removeAt(srcIdx);
    final rest = [...q]..removeAt(idx);
    if (rest.isEmpty || _source.isEmpty) {
      state = state.copyWith(isPlaying: false);
      return;
    }
    final next = idx < rest.length ? rest[idx] : _source[(srcIdx < 0 ? 0 : srcIdx) % _source.length];
    state = state.copyWith(queue: rest, currentIndex: rest.indexWhere((t) => t.id == next.id));
    unawaited(Future.microtask(() => _playFromSource(next)));
  }

  /// Flux Python pas encore prêt : on enchaîne tout de suite et on surveille sa
  /// résolution en arrière-plan pour le réinsérer juste après le titre en cours.
  void _deferUnresolved(Track track, List<Track> q, int idx, {int? status}) {
    final alone = _source.length < 2;
    if (_pendingStreams.add(track.id)) {
      unawaited(_waitForStream(track, _queueEpoch, firstDelay: _firstProbeDelay(status)));
    }
    if (alone) {
      state = state.copyWith(isPlaying: false);
      _ref.read(noticeProvider.notifier).show('« ${track.title} » se lancera dès qu\'il est prêt');
      return;
    }
    _skipFailed(q, idx);
  }

  /// Chaque sonde consomme une IP de sortie côté Python (pool limité) : on ne
  /// sonde JAMAIS pendant que le pool est encore bloqué. Le serveur est seul à
  /// connaître l'état du pool → l'intervalle vient exclusivement de son
  /// `Retry-After` ; à défaut (notamment après l'échec de lecture initial, dont
  /// just_audio n'expose pas les en-têtes) : 30 s, ou 10 s après un 429.
  static const _defaultProbeWait = Duration(seconds: 30);
  static const _maxProbes = 4;

  static Duration _firstProbeDelay(int? status) =>
      status == 429 ? const Duration(seconds: 10) : _defaultProbeWait;

  Future<void> _waitForStream(Track track, int epoch, {required Duration firstDelay}) async {
    var gaveUpUnavailable = false;
    try {
      await Future<void>.delayed(firstDelay);
      for (var probes = 0; probes < _maxProbes; probes++) {
        if (epoch != _queueEpoch) return;
        final probe = await _probeStream(track);
        if (epoch != _queueEpoch) return;
        final status = probe.status;
        if (status == 200 || status == 206) {
          await _insertAsNext(track);
          return;
        }
        if (status == 404) {
          gaveUpUnavailable = true;
          break;
        }
        // 409 (requête annulée) : on n'insiste pas. 401 : jeton absent ou
        // expiré, inutile de re-solliciter le serveur.
        if (status == 409) return;
        if (status == 401) break;
        if (probes == _maxProbes - 1) break;
        await Future<void>.delayed(probe.retryAfter ?? _defaultProbeWait);
      }
      if (epoch == _queueEpoch) {
        _ref.read(noticeProvider.notifier).show(gaveUpUnavailable
            ? '« ${track.title} » indisponible'
            : '« ${track.title} » indisponible pour le moment');
      }
    } finally {
      _pendingStreams.remove(track.id);
    }
  }

  /// Sonde le proxy /stream (1er octet). Python partage la résolution en cours
  /// et met le résultat en cache → un 206 signifie que le titre est prêt.
  Future<({int? status, Duration? retryAfter})> _probeStream(Track track) async {
    if (track.pageUrl.isEmpty) return (status: 404, retryAfter: null);
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(ApiConfig.streamUrl(track.pageUrl)))
        ..headers['Range'] = 'bytes=0-1';
      final jwt = ApiConfig.token;
      if (jwt != null && jwt.isNotEmpty) req.headers['Authorization'] = 'Bearer $jwt';
      final res = await client.send(req).timeout(const Duration(seconds: 60));
      // Retry-After en secondes, borné : on ignore une valeur absurde plutôt
      // que de suspendre la surveillance ou de re-solliciter trop vite.
      final seconds = int.tryParse(res.headers['retry-after'] ?? '');
      final retryAfter = (seconds != null && seconds >= 1 && seconds <= 120) ? Duration(seconds: seconds) : null;
      return (status: res.statusCode, retryAfter: retryAfter);
    } catch (_) {
      return (status: null, retryAfter: null);
    } finally {
      client.close();
    }
  }

  /// Insère un flux désormais résolu juste après le titre en cours, sans
  /// interrompre la lecture.
  Future<void> _insertAsNext(Track track) async {
    final t = track.copyWith(audioUrl: ApiConfig.streamUrl(track.pageUrl));
    final cur = state.currentTrack;
    final notices = _ref.read(noticeProvider.notifier);

    // File d'un seul titre restée à l'arrêt sur ce titre → on le lance.
    if (cur?.id == t.id && !state.isPlaying && !state.isLoading) {
      notices.show('« ${t.title} » est prêt', icon: NoticeIcon.playNext);
      await _playFromSource(t);
      return;
    }
    if (cur == null) return;
    final q = [...state.queue];
    if (q.any((x) => x.id == t.id)) return;
    q.insert((state.currentIndex + 1).clamp(0, q.length), t);
    final curSrc = _source.indexWhere((x) => x.id == cur.id);
    _source.insert(curSrc < 0 ? _source.length : curSrc + 1, t);
    state = state.copyWith(queue: q);
    notices.show('« ${t.title} » sera joué ensuite', icon: NoticeIcon.playNext);
  }

  /// Lance [track] dans la liste [queue].
  ///
  /// La file du player ne contient qu'une **fenêtre** de la liste : jusqu'à
  /// [_kWindow] titres avant et après le titre courant. Elle s'étend au fil de
  /// l'écoute (ou du scroll de la file d'attente) depuis [queue], puis via
  /// [fetchMore] (page suivante de l'API) quand la liste chargée est épuisée.
  Future<void> playTrack(
    Track track, {
    List<Track>? queue,
    TrackPageFetcher? fetchMore,
    int pageSize = 20,
    bool hasMore = true,
  }) async {
    // Titre déjà en cours de chargement → on ignore les clics répétés.
    if (state.isLoading && state.currentTrack?.id == track.id) return;
    final list = [...(queue ?? [track])];
    if (!list.any((t) => t.id == track.id)) list.insert(0, track);

    final sameList = listEquals(
      list.map((t) => t.id).toList(),
      _source.take(list.length).map((t) => t.id).toList(),
    );
    if (!sameList) {
      // Nouvelle liste → les réinsertions en attente sont abandonnées.
      _queueEpoch++;
      _source = list;
      _sourceFetch = fetchMore;
      _sourcePageSize = pageSize;
      _sourceFetchedCount = list.length;
      _sourceHasMore = fetchMore != null && hasMore;
    } else if (fetchMore != null && _sourceFetch == null) {
      _sourceFetch = fetchMore;
      _sourcePageSize = pageSize;
      _sourceHasMore = hasMore;
    }
    if (await _restartCurrent(track)) return;
    await _playFromSource(track);
  }

  /// Lance [track] (présent dans [_source]) avec une file fenêtrée autour de lui.
  Future<void> _playFromSource(Track track) async {
    if (state.isLoading && state.currentTrack?.id == track.id) return;
    var srcIdx = _source.indexWhere((t) => t.id == track.id);
    if (srcIdx < 0) {
      _source.insert(0, track);
      srcIdx = 0;
    }
    final window = _source.sublist(
      (srcIdx - _kWindow).clamp(0, _source.length),
      (srcIdx + _kWindow + 1).clamp(0, _source.length),
    );
    final token = ++_playToken;
    state = state.copyWith(isLoading: true);
    try {
      await _startTrack(track, window, token);
    } finally {
      if (token == _playToken && state.isLoading) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _startTrack(Track track, List<Track>? queue, int token) async {
    final q = [...(queue ?? [track])];
    var selIdx = q.indexWhere((t) => t.id == track.id);
    if (selIdx < 0) {
      q.insert(0, track);
      selIdx = 0;
    }
    _radioFromId = null; // nouvelle file → autorise une nouvelle extension radio

    // Ferme EN FORCE la bannière de stream du titre précédent si elle traîne
    // encore : sa résolution est désormais obsolète (token changé), inutile
    // d'attendre qu'elle se termine ou time out d'elle-même pour la retirer.
    if (_activeStreamJobId != null) {
      _ref.read(importProvider.notifier).dismiss(_activeStreamJobId!);
      _activeStreamJobId = null;
    }

    // Affichage immédiat du titre demandé (avant import/résolution)
    state = state.copyWith(
      currentTrack: track,
      queue: q,
      currentIndex: selIdx,
      isPlaying: true,
      isLiked: track.isFavoris,
      position: Duration.zero,
      duration: track.duration,
    );

    // Clôt l'écoute du titre précédent avant d'en démarrer une nouvelle
    unawaited(_tracker.finish());

    // Ferme le job de stream (bannière « Chargement du flux… ») et oublie qu'il
    // est actif — à appeler sur CHAQUE sortie (succès, erreur, obsolescence)
    // pour ne jamais laisser de bannière orpheline.
    final importNotifier = _ref.read(importProvider.notifier);
    String? streamJobId;
    void closeStreamJob({String? errorMessage}) {
      final id = streamJobId;
      if (id == null) return;
      if (errorMessage != null) {
        importNotifier.streamError(id, errorMessage);
      } else {
        importNotifier.dismiss(id);
      }
      if (_activeStreamJobId == id) _activeStreamJobId = null;
    }

    // Le noyau résout l'URL, charge le titre (2 tentatives) et lance la lecture.
    final result = await _core.load(
      track,
      isStale: () => token != _playToken,
      repeatOne: state.repeatMode == RepeatMode.one,
      onResolved: (current) {
        // Si l'import a transformé le track (externe → intégré), on met à jour la file
        if (current.id != track.id || !identical(current, track)) {
          q[selIdx] = current;
          state = state.copyWith(queue: q, currentTrack: current, duration: current.duration);
        }
        // Spinner « Chargement du flux… » pendant que yt-dlp résout l'audio et que
        // la mise en tampon se fait. Un externe avec une URL de page se lit toujours
        // en stream temps réel (jamais d'import auto au play).
        streamJobId = (track.needsImport && track.pageUrl.isNotEmpty) ? importNotifier.startStream(track) : null;
        _activeStreamJobId = streamJobId;
      },
    );

    switch (result) {
      case LoadStale():
        closeStreamJob();
      case LoadNoSource():
        mkLog('Mkzik ▶ aucune URL audio jouable pour "${track.title}"');
        state = state.copyWith(isPlaying: false);
      case LoadStarted(:final track):
        // Flux prêt → on retire le spinner et on démarre le suivi d'écoute.
        closeStreamJob();
        unawaited(_beginPlay(track));
        _afterTrackStarted();
      case LoadFailed(:final kind, :final status):
        switch (kind) {
          case LoadFailureKind.cancelledByServer:
            // Requête annulée côté serveur (client parti) → silencieux.
            closeStreamJob();
            state = state.copyWith(isPlaying: false);
          case LoadFailureKind.streamNotReady:
            // Flux Python lent / anti-bot / surcharge : on n'attend pas. Le titre
            // est retiré de la file, on enchaîne, et il revient en « suivant » dès
            // que Python l'a résolu (cf. _waitForStream).
            closeStreamJob();
            _deferUnresolved(track, q, selIdx, status: status);
          case LoadFailureKind.unavailable:
            closeStreamJob(errorMessage: 'Titre indisponible');
            if (q.length > 1) {
              _skipFailed(q, selIdx);
            } else {
              state = state.copyWith(isPlaying: false);
            }
          case LoadFailureKind.timeout:
            closeStreamJob(errorMessage: 'Le flux met trop de temps à répondre');
            state = state.copyWith(isPlaying: false);
          case LoadFailureKind.network:
            closeStreamJob(errorMessage: 'Erreur réseau, réessaie');
            state = state.copyWith(isPlaying: false);
        }
    }
  }

  /// Une fois un titre lancé : radio en fin de liste, puis extension de la fenêtre.
  void _afterTrackStarted() {
    // Autoplay radio : quand le titre courant est le DERNIER de la liste, on
    // précharge des suggestions et on les ajoute pour enchaîner sans coupure.
    if (state.queue.isNotEmpty && state.currentIndex == state.queue.length - 1 && loadedAllUpcoming) {
      unawaited(_maybeExtendWithRadio());
    }
    unawaited(_ensureWindow());
  }

  // ── Autoplay radio (suggestions en fin de file) ─────────────────────────────

  /// Étend la file avec des suggestions liées au dernier titre, pour enchaîner
  /// sans coupure (façon radio). Si aucune suggestion → la liste reboucle depuis
  /// le début. Gardé derrière `EXTERNAL_STREAM` car c'est l'autoplay radio que ce
  /// flag active (les suggestions sont streamées).
  Future<void> _maybeExtendWithRadio() async {
    if (!ApiConfig.externalStream || _radioBusy) return;
    final seed = state.currentTrack;
    if (seed == null) return;
    if (_radioFromId == seed.id) return; // déjà étendu depuis ce titre
    _radioBusy = true;
    _radioFromId = seed.id;
    final token = _playToken;
    try {
      final suggestions = await RadioService.suggestionsFor(seed);
      if (token != _playToken) return;

      // Dédup contre ce qui est déjà dans la liste.
      final seen = {for (final t in _source) RadioService.dedupKey(t)};
      final fresh = <Track>[];
      for (final t in suggestions) {
        if (seen.add(RadioService.dedupKey(t))) fresh.add(t);
      }
      if (fresh.isEmpty) return; // → la liste reboucle

      // Résout (URLs de stream) puis ajoute à la suite, sans couper la lecture.
      final resolved = <Track>[];
      for (final t in fresh.take(10)) {
        final r = await _resolver.resolveForQueue(t);
        if (r == null || r.audioUrl.isEmpty) continue;
        resolved.add(r);
      }
      if (token != _playToken || resolved.isEmpty) return;
      _source.addAll(resolved);
      state = state.copyWith(queue: [...state.queue, ...resolved]);
      mkLog('Mkzik 📻 radio +${resolved.length} titres (seed "${seed.title}")');
    } catch (e) {
      mkLog('Mkzik 📻 radio erreur : $e');
    } finally {
      _radioBusy = false;
    }
  }

  /// Active le **mode radio** à la demande (depuis la file d'attente) : remplace
  /// tout ce qui suit le titre courant par des suggestions du même mood, sans
  /// couper la lecture en cours. Renvoie `true` si la radio a démarré.
  Future<bool> startRadio() async {
    final seed = state.currentTrack;
    if (seed == null) return false;
    // Les suggestions peuvent prendre ~15 s : si l'utilisateur lance un autre
    // titre pendant ce temps (_playToken changé), on abandonne.
    final token = _playToken;
    try {
      final suggestions = await RadioService.suggestionsFor(seed);
      if (token != _playToken) return false;
      final seen = {RadioService.dedupKey(seed)};
      final fresh = <Track>[for (final t in suggestions) if (seen.add(RadioService.dedupKey(t))) t];
      if (fresh.isEmpty) return false;

      final resolved = <Track>[];
      for (final t in fresh.take(20)) {
        final r = await _resolver.resolveForQueue(t);
        if (token != _playToken) return false;
        if (r == null || r.audioUrl.isEmpty) continue;
        resolved.add(r);
      }
      if (resolved.isEmpty || token != _playToken) return false;

      // La file Dart garde les titres déjà écoutés (affichés dans la file
      // d'attente) : on ne remplace que ce qui suit le titre courant.
      final history = state.queue.sublist(0, state.currentIndex.clamp(0, state.queue.length));
      final newQueue = [...history, seed, ...resolved];
      // La radio remplace tout ce qui suit le titre courant, y compris la suite
      // de la liste d'origine non encore chargée.
      final seedSrc = _source.indexWhere((t) => t.id == seed.id);
      final firstSrc = history.isEmpty ? seedSrc : _source.indexWhere((t) => t.id == history.first.id);
      _source = [if (firstSrc > 0) ..._source.sublist(0, firstSrc), ...newQueue];
      _sourceFetch = null;
      _sourceHasMore = false;
      state = state.copyWith(
        queue: newQueue,
        currentIndex: history.length,
      );
      _radioFromId = null; // autorise l'extension auto quand on atteindra la fin
      mkLog('Mkzik 📻 mode radio : ${resolved.length} titres (seed "${seed.title}")');
      return true;
    } catch (e) {
      mkLog('Mkzik 📻 mode radio erreur : $e');
      return false;
    }
  }

  Future<void> togglePlayPause() async {
    if (state.isLoading) return;
    await _core.togglePlayPause();
  }

  // next/previous cycliques : on enchaîne toujours depuis la liste d'origine.
  Future<void> next() => _advanceFromQueue();

  Future<void> previous() async {
    final cur = state.currentTrack;
    if (cur == null || _source.length < 2) return;
    final srcIdx = _source.indexWhere((t) => t.id == cur.id);
    await _playFromSource(_source[previousSourceIndex(length: _source.length, current: srcIdx)]);
  }

  // ── File fenêtrée : extension progressive ───────────────────────────────────

  /// Étend la fenêtre si le titre courant approche d'un bord.
  Future<void> _ensureWindow() async {
    final q = state.queue;
    if (q.isEmpty) return;
    if (state.currentIndex >= q.length - 3) await loadMoreUpcoming();
    if (state.currentIndex < 3) await loadMorePrevious();
  }

  /// Ajoute jusqu'à [_kWindow] titres suivants à la file : depuis la liste déjà
  /// connue, sinon via la page suivante de l'API.
  Future<void> loadMoreUpcoming() async {
    if (_extendingForward || state.queue.isEmpty) return;
    _extendingForward = true;
    final epoch = _queueEpoch;
    try {
      var lastSrc = _source.indexWhere((t) => t.id == state.queue.last.id);
      if (lastSrc < 0) return;
      if (lastSrc + 1 >= _source.length && _sourceFetch != null && _sourceHasMore) {
        final page = await _sourceFetch!(limit: _sourcePageSize, offset: _sourceFetchedCount);
        if (epoch != _queueEpoch) return;
        _sourceFetchedCount += page.length;
        _sourceHasMore = page.length >= _sourcePageSize;
        final known = {for (final t in _source) t.id};
        _source.addAll(page.where((t) => known.add(t.id)));
        lastSrc = _source.indexWhere((t) => t.id == state.queue.last.id);
        if (lastSrc < 0) return;
      }
      final more = _source.sublist(lastSrc + 1, (lastSrc + 1 + _kWindow).clamp(0, _source.length));
      if (more.isEmpty) return;
      state = state.copyWith(queue: [...state.queue, ...more]);
    } catch (e) {
      mkLog('Mkzik ▶ extension de la file impossible : $e');
    } finally {
      _extendingForward = false;
    }
  }

  /// Ajoute jusqu'à [_kWindow] titres précédents (toujours déjà connus).
  Future<void> loadMorePrevious() async {
    if (_extendingBackward || state.queue.isEmpty) return;
    _extendingBackward = true;
    try {
      final firstSrc = _source.indexWhere((t) => t.id == state.queue.first.id);
      if (firstSrc <= 0) return;
      final more = _source.sublist((firstSrc - _kWindow).clamp(0, firstSrc), firstSrc);
      state = state.copyWith(
        queue: [...more, ...state.queue],
        currentIndex: state.currentIndex + more.length,
      );
    } finally {
      _extendingBackward = false;
    }
  }

  bool get loadedAllPrevious =>
      state.queue.isEmpty || _source.indexWhere((t) => t.id == state.queue.first.id) <= 0;

  bool get loadedAllUpcoming =>
      state.queue.isEmpty ||
      (!_sourceHasMore && _source.indexWhere((t) => t.id == state.queue.last.id) >= _source.length - 1);

  /// Remplace la portion de [_source] couverte par [oldWindow] par [newWindow]
  /// (après un ajout / retrait / réordonnancement dans la file affichée).
  void _replaceWindowInSource(List<Track> oldWindow, List<Track> newWindow) {
    if (oldWindow.isEmpty) {
      _source = [...newWindow];
      return;
    }
    final start = _source.indexWhere((t) => t.id == oldWindow.first.id);
    final end = _source.indexWhere((t) => t.id == oldWindow.last.id);
    if (start < 0 || end < start) return;
    final ids = {for (final t in newWindow) t.id};
    _source = [
      ..._source.sublist(0, start).where((t) => !ids.contains(t.id)),
      ...newWindow,
      ..._source.sublist(end + 1).where((t) => !ids.contains(t.id)),
    ];
  }

  Future<void> seekTo(Duration position) => _core.seek(position);

  /// Like optimiste + appel API.
  /// Track externe (needsStream) → POST /api/external-tracks/likes.
  /// Track cataloguée (apiId) → POST /api/tracks/{id}/likes.
  Future<void> toggleLike() async {
    final t = state.currentTrack;
    if (t == null) return;
    state = state.copyWith(isLiked: !state.isLiked);

    if (t.needsStream) {
      final key = t.externalLikeKey;
      if (key == null) {
        state = state.copyWith(isLiked: !state.isLiked); // rollback
        return;
      }
      final res = await ExternalTrackService.toggleLike(
        platform: key.platform,
        externalId: key.externalId,
        title: t.title,
        artist: t.artist,
        thumbnailUrl: t.coverUrl.isNotEmpty ? t.coverUrl : null,
      );
      if (!res.ok) {
        state = state.copyWith(isLiked: !state.isLiked);
      } else {
        state = state.copyWith(isLiked: res.isLiked);
      }
      return;
    }

    if (t.apiId == null) {
      state = state.copyWith(isLiked: !state.isLiked); // rollback
      return;
    }
    final res = await TrackService.toggleLike(t.apiId!);
    if (!res.ok) {
      state = state.copyWith(isLiked: !state.isLiked);
      return;
    }
    state = state.copyWith(isLiked: res.isLiked);
    _ref.invalidate(favouritesProvider);
  }

  /// Ajoute un track à la file courante (cf. React addToList).
  /// [playNext] = true → insère juste après le titre courant ("Jouer ensuite"),
  /// sinon ajoute en fin de file ("Ajouter à la liste courante").
  Future<void> addToList(Track track, {bool playNext = false}) async {
    // Rend le titre jouable sans importer :
    // • interne → URL signée Symfony ;
    // • externe non importé → flux temps réel Python.
    var t = track;
    if (!t.hasPlayableUrl && !t.needsImport && t.apiId != null) {
      final signed = await _resolver.signedUrlFor(t.apiId!);
      if (signed != null && signed.isNotEmpty) t = t.copyWith(audioUrl: signed);
    } else if (t.needsStream && t.pageUrl.isNotEmpty && !t.hasPlayableUrl) {
      t = t.copyWith(audioUrl: ApiConfig.streamUrl(t.pageUrl));
    }

    final list = [...state.queue];
    if (list.any((x) => x.id == t.id)) return; // déjà présent
    final insertAt = playNext
        ? (state.currentIndex + 1).clamp(0, list.length)
        : list.length;
    list.insert(insertAt, t);

    // L'index courant peut se décaler si on insère avant lui
    var idx = state.currentIndex;
    if (insertAt <= idx) idx += 1;
    _replaceWindowInSource(state.queue, list);
    state = state.copyWith(queue: list, currentIndex: idx);
  }

  /// Saute directement à un titre de la file (tap dans la current list).
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    if (index == state.currentIndex) return;
    await _playFromSource(state.queue[index]);
  }

  /// Retire un titre de la file. Le titre en cours n'est pas supprimable.
  void removeAt(int index) {
    if (index < 0 || index >= state.queue.length) return;
    if (index == state.currentIndex) return; // on ne retire pas le titre joué
    final list = [...state.queue]..removeAt(index);
    var idx = state.currentIndex;
    if (index < idx) idx -= 1; // décalage si on retire avant le courant
    _replaceWindowInSource(state.queue, list);
    state = state.copyWith(queue: list, currentIndex: idx);
  }

  /// Réordonne la file (drag & drop) en gardant le titre courant synchronisé.
  void reorder(int oldIndex, int newIndex) {
    final list = [...state.queue];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    // Convention ReorderableListView : ajuster newIndex si on descend l'élément
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    // Recalcule l'index courant via l'id du titre joué
    final curId = state.currentTrack?.id;
    final newCur = curId == null ? state.currentIndex : list.indexWhere((t) => t.id == curId);
    _replaceWindowInSource(state.queue, list);
    state = state.copyWith(queue: list, currentIndex: newCur < 0 ? state.currentIndex : newCur);
  }

  /// Mode aléatoire : le prochain titre est tiré au hasard dans la liste d'origine.
  void toggleShuffle() {
    state = state.copyWith(isShuffle: !state.isShuffle);
  }

  // Bascule entre boucle de file (all) et répétition d'un titre (one).
  // Pas d'état "off" → prev/next restent cycliques.
  Future<void> cycleRepeat() async {
    final next = state.repeatMode == RepeatMode.one ? RepeatMode.all : RepeatMode.one;
    state = state.copyWith(repeatMode: next);
    await _core.setRepeatOne(next == RepeatMode.one);
  }

  /// Titre suivant de la liste (charge la suite si besoin), en boucle ou au hasard.
  /// [auto] : enchaînement à la fin d'un titre (ignoré pendant un chargement, pour
  /// ne pas enchaîner deux fois) ; un « suivant » demandé par l'utilisateur passe
  /// toujours, même pendant un chargement.
  Future<void> _advanceFromQueue({bool auto = false}) async {
    if (auto && state.isLoading) return;
    final cur = state.currentTrack;
    if (cur == null) return;
    var srcIdx = _source.indexWhere((t) => t.id == cur.id);
    if (srcIdx >= _source.length - 1 && _sourceHasMore) {
      await loadMoreUpcoming();
      srcIdx = _source.indexWhere((t) => t.id == cur.id);
    }
    if (_source.length < 2) {
      // Un seul titre : on le rejoue (la liste boucle sur elle-même).
      if (!await _restartCurrent(cur)) await _playFromSource(cur);
      return;
    }
    final nextIdx = nextSourceIndex(length: _source.length, current: srcIdx, shuffle: state.isShuffle);
    await _playFromSource(_source[nextIdx]);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_tracker.finish()); // clôt l'écoute en cours
    unawaited(_media.dispose());
    unawaited(_core.dispose());
    super.dispose();
  }
}

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>(
  (ref) => PlayerNotifier(ref),
);
