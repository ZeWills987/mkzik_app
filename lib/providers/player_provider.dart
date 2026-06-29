import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import '../config/api_config.dart';
import '../models/track.dart';
import '../services/track_service.dart';
import '../services/radio_service.dart';
import '../utils/media.dart';
import 'import_provider.dart';
import 'favourites_provider.dart';
import '../utils/logger.dart';

// Mode de répétition. `off` est conservé pour compat mais n'est plus utilisé :
// on tourne toujours en boucle de file (all) ↔ répétition d'un titre (one), ce
// qui garde les boutons prev/next stables et cycliques dans la notification.
enum RepeatMode { off, all, one }

// État immuable du player
class PlayerState {
  final Track? currentTrack;
  final bool isPlaying;
  final bool isLiked;
  final bool isShuffle;
  final RepeatMode repeatMode;
  final List<Track> queue;
  final int currentIndex;
  final Duration position;
  final Duration duration;

  const PlayerState({
    this.currentTrack,
    this.isPlaying = false,
    this.isLiked = false,
    this.isShuffle = false,
    this.repeatMode = RepeatMode.all,
    this.queue = const [],
    this.currentIndex = 0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  PlayerState copyWith({
    Track? currentTrack,
    bool? isPlaying,
    bool? isLiked,
    bool? isShuffle,
    RepeatMode? repeatMode,
    List<Track>? queue,
    int? currentIndex,
    Duration? position,
    Duration? duration,
  }) {
    return PlayerState(
      currentTrack: currentTrack ?? this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
      isLiked: isLiked ?? this.isLiked,
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      position: position ?? this.position,
      duration: duration ?? this.duration,
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

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get positionFormatted => _fmt(position);
  String get durationFormatted => _fmt(duration);
}

class PlayerNotifier extends StateNotifier<PlayerState> {
  final Ref _ref;
  final AudioPlayer _audio = AudioPlayer();
  // Jeton anti-concurrence : invalide les chargements obsolètes (taps rapides)
  int _playToken = 0;

  // Playlist native ExoPlayer/AVPlayer : sa séquence reflète la file Dart, ce
  // qui fait fonctionner prev/next nativement (notification + écran verrouillé).
  ConcatenatingAudioSource? _playlist;
  // Titres réellement présents dans _playlist (sous-ensemble jouable de la file :
  // les externes non importés en sont exclus). Parallèle aux enfants de _playlist.
  List<Track> _playerTracks = [];
  // Tracking d'écoute (POST /api/plays + PATCH complete)
  int? _playId; // playId de l'écoute en cours
  Track? _playTrack; // titre suivi par cette écoute
  int _playMaxMs = 0; // position max atteinte → listenedSeconds

  // Autoplay radio : extension de la file par suggestions en fin de liste.
  bool _radioBusy = false; // une extension est déjà en cours
  String? _radioFromId; // id du titre depuis lequel on a déjà étendu (anti-doublon)

  // Verrou : bloque _onCurrentIndexChanged pendant les manipulations de playlist
  // (insertions d'hydratation, reconstruction radio) pour éviter les faux "track changed".
  bool _suppressIndexChange = false;

  PlayerNotifier(this._ref) : super(const PlayerState()) {
    _initAudioSession();

    // Écoute de la position en temps réel
    _audio.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
      final ms = pos.inMilliseconds;
      if (_playTrack != null && ms > _playMaxMs) _playMaxMs = ms;
    });

    // Écoute de la durée quand un titre est chargé
    _audio.durationStream.listen((dur) {
      if (dur != null) state = state.copyWith(duration: dur);
    });

    // Changement d'index (auto-avance, prev/next notif, fin de titre) → resync
    // de l'état Dart sur le titre réellement joué par le moteur natif.
    _audio.currentIndexStream.listen(_onCurrentIndexChanged);

    // Sync isPlaying avec l'état réel du player
    _audio.playerStateStream.listen((ps) {
      state = state.copyWith(isPlaying: ps.playing);
    });

    // Boucle de file par défaut → prev/next cycliques et stables dans la notif.
    _audio.setLoopMode(LoopMode.all);
  }

  // Configure la session audio (catégorie musique) — requis pour une lecture
  // fiable en arrière-plan et avec les formats type .m4a/AAC.
  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {
      // Sans session configurée la lecture reste possible sur la plupart des appareils
    }
  }

  // Traduit notre RepeatMode vers le LoopMode natif de just_audio.
  LoopMode _loopFor(RepeatMode m) => switch (m) {
        RepeatMode.off => LoopMode.off,
        RepeatMode.all => LoopMode.all,
        RepeatMode.one => LoopMode.one,
      };

  // Construit une source audio taguée (alimente la notification / lockscreen).
  // La pochette est nettoyée (mediaUrl) → URL propre haute résolution : le système
  // l'affiche en grand et en extrait les couleurs pour teinter la notif (cf. Spotify).
  AudioSource _audioSourceFor(Track t) {
    final cover = mediaUrl(t.coverUrl);
    return AudioSource.uri(
      Uri.parse(t.audioUrl),
      tag: MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        duration: t.duration > Duration.zero ? t.duration : null,
        artUri: cover.isNotEmpty ? Uri.tryParse(cover) : null,
      ),
    );
  }

  // Resync quand le moteur change d'index (y compris via les boutons de la notif).
  void _onCurrentIndexChanged(int? i) {
    if (_suppressIndexChange) return;
    if (i == null || i < 0 || i >= _playerTracks.length) return;
    final t = _playerTracks[i];
    // Même titre (l'index a juste été décalé par une insertion d'hydratation) →
    // on ne remet pas la position à 0 et on ne ré-enregistre pas l'écoute.
    final sameTrack = t.id == state.currentTrack?.id;
    final qIdx = state.queue.indexWhere((x) => x.id == t.id);
    state = state.copyWith(
      currentTrack: t,
      currentIndex: qIdx < 0 ? state.currentIndex : qIdx,
      isLiked: t.isFavoris,
      position: sameTrack ? state.position : Duration.zero,
    );
    // Vrai changement de titre (auto-avance / skip) → clôt l'écoute précédente
    // et démarre la nouvelle.
    if (!sameTrack) {
      unawaited(_finishPlay());
      unawaited(_beginPlay(t));
    }
    // Autoplay radio : quand le titre courant est le DERNIER de la file, on
    // précharge des suggestions et on les ajoute pour enchaîner sans coupure.
    // (On se base sur la file Dart complète, pas sur _playerTracks qui peut être
    // partiel pendant l'hydratation en arrière-plan.)
    if (qIdx >= 0 && qIdx == state.queue.length - 1) {
      unawaited(_maybeExtendWithRadio());
    }
  }

  // ── Tracking d'écoute (POST /api/plays + PATCH complete) ────────────────────

  // Démarre une écoute pour [t] (récupère le playId du backend).
  Future<void> _beginPlay(Track t) async {
    _playTrack = t;
    _playMaxMs = 0;
    _playId = null;
    if (t.apiId == null) return;
    _playId = await TrackService.startPlay(t.apiId!);
  }

  // Clôt l'écoute en cours : envoie les secondes écoutées + si terminée (~90%).
  Future<void> _finishPlay() async {
    final id = _playId;
    final t = _playTrack;
    final maxMs = _playMaxMs;
    _playId = null;
    _playTrack = null;
    _playMaxMs = 0;
    if (id == null || t == null) return;
    final durMs = t.duration.inMilliseconds;
    final completed = durMs > 0 && maxMs >= durMs * 0.9;
    await TrackService.completePlay(id, listenedSeconds: maxMs / 1000.0, completed: completed);
  }

  Future<void> playTrack(Track track, {List<Track>? queue}) async {
    final q = [...(queue ?? [track])];
    var selIdx = q.indexWhere((t) => t.id == track.id);
    if (selIdx < 0) {
      q.insert(0, track);
      selIdx = 0;
    }
    final token = ++_playToken;
    _radioFromId = null; // nouvelle file → autorise une nouvelle extension radio

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
    unawaited(_finishPlay());

    // Résout le titre sélectionné (import si externe → URL signée)
    final current = await _resolvePlayable(track);
    if (token != _playToken) return;

    if (current == null || current.audioUrl.isEmpty) {
      mkLog('Mkzik ▶ aucune URL audio jouable pour "${track.title}"');
      state = state.copyWith(isPlaying: false);
      return;
    }

    // Si l'import a transformé le track (externe → intégré), on met à jour la file
    if (current.id != track.id || !identical(current, track)) {
      q[selIdx] = current;
      state = state.copyWith(queue: q, currentTrack: current, duration: current.duration);
    }

    // Spinner « Chargement du flux… » pendant que yt-dlp résout l'audio et que
    // la mise en mémoire tampon se fait (setAudioSource). Un externe avec une URL
    // de page se lit toujours en stream temps réel (jamais d'import auto au play).
    final importNotifier = _ref.read(importProvider.notifier);
    final streamJobId = (track.needsImport && track.pageUrl.isNotEmpty)
        ? importNotifier.startStream(track)
        : null;

    // Démarrage IMMÉDIAT avec une playlist d'un seul titre (le titre cliqué) →
    // pas d'attente de la signature du reste de la file. Le reste est hydraté
    // en arrière-plan (cf. _hydrateQueue) sans couper la lecture.
    try {
      _playerTracks = [current];
      _playlist = ConcatenatingAudioSource(children: [_audioSourceFor(current)]);
      await _audio.setAudioSource(_playlist!, initialIndex: 0, initialPosition: Duration.zero);
      if (token != _playToken) {
        if (streamJobId != null) importNotifier.dismiss(streamJobId);
        return;
      }
      await _audio.setLoopMode(_loopFor(state.repeatMode));
      await _audio.setShuffleModeEnabled(state.isShuffle);
      await _audio.play();
      // Flux prêt → on retire le spinner.
      if (streamJobId != null) importNotifier.dismiss(streamJobId);
      // Démarre le tracking d'écoute du titre courant (l'event d'index initial
      // est "same track" → on le démarre explicitement ici).
      unawaited(_beginPlay(current));
    } catch (e) {
      mkLog('Mkzik ▶ erreur lecture "${track.title}" : $e');
      if (streamJobId != null) importNotifier.streamError(streamJobId, 'Flux indisponible, réessaie');
      if (token == _playToken) state = state.copyWith(isPlaying: false);
      return;
    }

    // Hydrate le reste de la file en arrière-plan (signe + insère autour du
    // titre courant). Non attendu → la lecture a déjà démarré.
    unawaited(_hydrateQueue(q, selIdx, current, token));
  }

  /// Résout (signe) les autres titres de la file et les insère autour du titre
  /// courant dans la playlist native, sans interrompre la lecture en cours.
  Future<void> _hydrateQueue(List<Track> q, int selIdx, Track current, int token) async {
    if (q.length < 2) return;
    final resolved = await Future.wait([
      for (var i = 0; i < q.length; i++)
        i == selIdx ? Future.value(current) : _resolveForQueue(q[i]),
    ]);
    if (token != _playToken || _playlist == null) return;

    // Sépare les titres jouables avant / après le titre courant
    final before = <Track>[];
    final beforeSources = <AudioSource>[];
    for (var i = 0; i < selIdx; i++) {
      final rt = resolved[i];
      if (rt == null || rt.audioUrl.isEmpty) continue;
      before.add(rt);
      beforeSources.add(_audioSourceFor(rt));
    }
    final after = <Track>[];
    final afterSources = <AudioSource>[];
    for (var i = selIdx + 1; i < q.length; i++) {
      final rt = resolved[i];
      if (rt == null || rt.audioUrl.isEmpty) continue;
      after.add(rt);
      afterSources.add(_audioSourceFor(rt));
    }
    if (before.isEmpty && after.isEmpty) return;

    // Met à jour _playerTracks APRÈS les insertions pour que _onCurrentIndexChanged
    // ne mappe jamais un index natif en transition sur le mauvais titre.
    // Le verrou supprime les événements d'index pendant la manipulation.
    _suppressIndexChange = true;
    try {
      if (before.isNotEmpty) await _playlist!.insertAll(0, beforeSources);
      if (after.isNotEmpty) await _playlist!.addAll(afterSources);
      _playerTracks = [...before, current, ...after];
    } finally {
      _suppressIndexChange = false;
      // Resync : l'index natif a pu changer (insertion de `before` en tête).
      final ni = _audio.currentIndex;
      if (ni != null && ni >= 0 && ni < _playerTracks.length) {
        final t = _playerTracks[ni];
        final qIdx = state.queue.indexWhere((x) => x.id == t.id);
        if (qIdx >= 0 && qIdx != state.currentIndex) {
          state = state.copyWith(currentIndex: qIdx);
        }
      }
    }
  }

  /// Rend un track réellement jouable (cf. React `handleClicTrack`) :
  /// 1. externe non intégré (`needsImport`) → **lecture en stream temps réel**
  ///    (`GET /stream?url=`), jamais d'import S3 automatique. L'import dans Mkzik
  ///    reste une action explicite (bouton "Importer"), pas un effet de bord du play.
  /// 2. si pas d'URL audio directe (http) → URL signée via `api/tracks/{id}/audio`
  Future<Track?> _resolvePlayable(Track track) async {
    var t = track;

    // 1) Externes non intégrés → stream direct depuis l'URL de page (pas d'import).
    if (t.needsImport) {
      if (t.pageUrl.isEmpty) return null; // injouable en stream sans URL d'origine
      return t.copyWith(audioUrl: ApiConfig.streamUrl(t.pageUrl));
    }

    // 2) URL signée si l'audio n'est pas directement jouable
    if (!t.hasPlayableUrl && t.apiId != null) {
      final signed = await TrackService.getSignedAudioUrl(t.apiId!);
      if (signed != null && signed.isNotEmpty) {
        t = t.copyWith(audioUrl: signed);
      }
    }

    return t.audioUrl.isNotEmpty ? t : null;
  }

  /// Résolution légère pour les autres titres de la file (préchargement) : signe
  /// l'URL des internes et donne aux externes leur URL de flux temps réel (jamais
  /// d'import). Renvoie null pour les titres injouables → exclus de la playlist.
  Future<Track?> _resolveForQueue(Track t) async {
    if (t.hasPlayableUrl) return t;
    if (t.needsImport) {
      if (t.pageUrl.isNotEmpty) {
        return t.copyWith(audioUrl: ApiConfig.streamUrl(t.pageUrl));
      }
      return null; // externe sans URL d'origine → injouable en stream
    }
    if (t.apiId != null) {
      final signed = await TrackService.getSignedAudioUrl(t.apiId!);
      if (signed != null && signed.isNotEmpty) return t.copyWith(audioUrl: signed);
    }
    return null;
  }

  // ── Autoplay radio (suggestions en fin de file) ─────────────────────────────

  /// Étend la file avec des suggestions liées au dernier titre, pour enchaîner
  /// sans coupure (façon radio). Si aucune suggestion → on laisse la boucle de
  /// file (LoopMode.all) reprendre depuis le début. Gardé derrière `EXTERNAL_STREAM`
  /// car c'est l'autoplay radio que ce flag active (les suggestions sont streamées).
  Future<void> _maybeExtendWithRadio() async {
    if (!ApiConfig.externalStream || _radioBusy || _playlist == null) return;
    final seed = state.currentTrack;
    if (seed == null) return;
    if (_radioFromId == seed.id) return; // déjà étendu depuis ce titre
    _radioBusy = true;
    _radioFromId = seed.id;
    final token = _playToken;
    try {
      final suggestions = await RadioService.suggestionsFor(seed);
      if (token != _playToken || _playlist == null) return;

      // Dédup contre ce qui est déjà dans la file.
      final seen = {for (final t in _playerTracks) RadioService.dedupKey(t)};
      final fresh = <Track>[];
      for (final t in suggestions) {
        if (seen.add(RadioService.dedupKey(t))) fresh.add(t);
      }
      if (fresh.isEmpty) return; // → fallback : boucle de file

      // Résout (URLs de stream) puis insère à la suite, sans couper la lecture.
      final resolved = <Track>[];
      final sources = <AudioSource>[];
      for (final t in fresh.take(10)) {
        final r = await _resolveForQueue(t);
        if (r == null || r.audioUrl.isEmpty) continue;
        resolved.add(r);
        sources.add(_audioSourceFor(r));
      }
      if (token != _playToken || _playlist == null || resolved.isEmpty) return;
      _playerTracks = [..._playerTracks, ...resolved];
      await _playlist!.addAll(sources);
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
    if (seed == null || _playlist == null) return false;
    final pIdx = _playerTracks.indexWhere((t) => t.id == seed.id);
    if (pIdx < 0) return false;
    try {
      final suggestions = await RadioService.suggestionsFor(seed);
      final seen = {RadioService.dedupKey(seed)};
      final fresh = <Track>[for (final t in suggestions) if (seen.add(RadioService.dedupKey(t))) t];
      if (fresh.isEmpty) return false;

      final resolved = <Track>[];
      final sources = <AudioSource>[];
      for (final t in fresh.take(20)) {
        final r = await _resolveForQueue(t);
        if (r == null || r.audioUrl.isEmpty) continue;
        resolved.add(r);
        sources.add(_audioSourceFor(r));
      }
      if (resolved.isEmpty || _playlist == null) return false;

      // Reconstruction : [seed, R1, R2, …] — on retire tout ce qui précède le
      // courant pour que LoopMode.all ne reboucle jamais sur l'ancienne playlist.
      final seedTrack = _playerTracks[pIdx];
      _suppressIndexChange = true;
      try {
        // 1) Retire les titres APRÈS le courant
        if (pIdx + 1 < _playerTracks.length) {
          await _playlist!.removeRange(pIdx + 1, _playerTracks.length);
        }
        // 2) Retire les titres AVANT le courant (courant passe en index 0)
        if (pIdx > 0) {
          await _playlist!.removeRange(0, pIdx);
        }
        // 3) Ajoute les suggestions radio
        await _playlist!.addAll(sources);
        _playerTracks = [seedTrack, ...resolved];
      } finally {
        _suppressIndexChange = false;
      }

      state = state.copyWith(
        queue: [seed, ...resolved],
        currentIndex: 0,
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
    if (_audio.playing) {
      await _audio.pause();
    } else {
      await _audio.play();
    }
  }

  // next/previous cycliques, délégués au moteur natif (cohérent avec la notif).
  Future<void> next() async {
    final n = _playerTracks.length;
    if (n < 2) return;
    if (_audio.hasNext) {
      await _audio.seekToNext();
    } else {
      await _audio.seek(Duration.zero, index: 0); // reboucle au début
    }
  }

  Future<void> previous() async {
    final n = _playerTracks.length;
    if (n < 2) return;
    if (_audio.hasPrevious) {
      await _audio.seekToPrevious();
    } else {
      await _audio.seek(Duration.zero, index: n - 1); // reboucle à la fin
    }
  }

  Future<void> seekTo(Duration position) async {
    await _audio.seek(position);
  }

  /// Like optimiste + appel API (cf. React useLikeTrack → toggleLikeTrack(id)).
  Future<void> toggleLike() async {
    final t = state.currentTrack;
    state = state.copyWith(isLiked: !state.isLiked);
    if (t?.apiId == null) return;
    final res = await TrackService.toggleLike(t!.apiId!);
    if (!res.ok) {
      // Rollback si l'API a échoué
      state = state.copyWith(isLiked: !state.isLiked);
      return;
    }
    // Synchronise avec l'état réel + rafraîchit la librairie
    state = state.copyWith(isLiked: res.isLiked);
    _ref.invalidate(favouritesProvider);
  }

  /// Ajoute un track à la file courante (cf. React addToList).
  /// [playNext] = true → insère juste après le titre courant ("Jouer ensuite"),
  /// sinon ajoute en fin de file ("Ajouter à la liste courante").
  Future<void> addToList(Track track, {bool playNext = false}) async {
    // Signe l'URL si nécessaire (sans importer — comme addToList côté React)
    var t = track;
    if (!t.hasPlayableUrl && !t.needsImport && t.apiId != null) {
      final signed = await TrackService.getSignedAudioUrl(t.apiId!);
      if (signed != null && signed.isNotEmpty) t = t.copyWith(audioUrl: signed);
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
    state = state.copyWith(queue: list, currentIndex: idx);

    // Reflète l'ajout dans la playlist native si le titre est jouable sans import
    if (_playlist != null && t.audioUrl.isNotEmpty && !t.needsImport) {
      final playerInsert = playNext
          ? ((_audio.currentIndex ?? 0) + 1).clamp(0, _playerTracks.length)
          : _playerTracks.length;
      _playerTracks.insert(playerInsert, t);
      await _playlist!.insert(playerInsert, _audioSourceFor(t));
    }
  }

  /// Saute directement à un titre de la file (tap dans la current list).
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    if (index == state.currentIndex) return;
    final t = state.queue[index];
    final pIdx = _playerTracks.indexWhere((x) => x.id == t.id);
    if (pIdx >= 0) {
      await _audio.seek(Duration.zero, index: pIdx); // titre déjà dans la playlist
    } else {
      await playTrack(t, queue: state.queue); // externe/non résolu → résout + recharge
    }
  }

  /// Retire un titre de la file. Le titre en cours n'est pas supprimable.
  void removeAt(int index) {
    if (index < 0 || index >= state.queue.length) return;
    if (index == state.currentIndex) return; // on ne retire pas le titre joué
    final removed = state.queue[index];
    final list = [...state.queue]..removeAt(index);
    var idx = state.currentIndex;
    if (index < idx) idx -= 1; // décalage si on retire avant le courant
    state = state.copyWith(queue: list, currentIndex: idx);

    // Reflète la suppression dans la playlist native
    final pIdx = _playerTracks.indexWhere((x) => x.id == removed.id);
    if (pIdx >= 0 && _playlist != null) {
      _playerTracks.removeAt(pIdx);
      _playlist!.removeAt(pIdx);
    }
  }

  /// Réordonne la file (drag & drop) en gardant le titre courant synchronisé.
  void reorder(int oldIndex, int newIndex) {
    final list = [...state.queue];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    // Convention ReorderableListView : ajuster newIndex si on descend l'élément
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= list.length) return;
    final mirrors = _playlist != null && _playerTracks.length == list.length;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    // Recalcule l'index courant via l'id du titre joué
    final curId = state.currentTrack?.id;
    final newCur = curId == null ? state.currentIndex : list.indexWhere((t) => t.id == curId);
    state = state.copyWith(queue: list, currentIndex: newCur < 0 ? state.currentIndex : newCur);

    // Applique le même déplacement à la playlist native (si elle reflète la file 1:1)
    if (mirrors) {
      final moved = _playerTracks.removeAt(oldIndex);
      _playerTracks.insert(newIndex, moved);
      _playlist!.move(oldIndex, newIndex);
    }
  }

  Future<void> toggleShuffle() async {
    final v = !state.isShuffle;
    await _audio.setShuffleModeEnabled(v);
    state = state.copyWith(isShuffle: v);
  }

  // Bascule entre boucle de file (all) et répétition d'un titre (one).
  // Pas d'état "off" → prev/next restent cycliques et stables dans la notif.
  Future<void> cycleRepeat() async {
    final next = state.repeatMode == RepeatMode.one ? RepeatMode.all : RepeatMode.one;
    await _audio.setLoopMode(_loopFor(next));
    state = state.copyWith(repeatMode: next);
  }

  @override
  void dispose() {
    unawaited(_finishPlay()); // clôt l'écoute en cours
    _audio.dispose();
    super.dispose();
  }
}

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>(
  (ref) => PlayerNotifier(ref),
);
