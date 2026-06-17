import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import '../models/track.dart';
import '../services/track_service.dart';
import 'import_provider.dart';
import 'favourites_provider.dart';

// Mode de répétition cyclique : aucune → toute la file → un seul titre
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
    this.repeatMode = RepeatMode.off,
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

  PlayerNotifier(this._ref) : super(const PlayerState()) {
    _initAudioSession();

    // Écoute de la position en temps réel
    _audio.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });

    // Écoute de la durée quand un titre est chargé
    _audio.durationStream.listen((dur) {
      if (dur != null) state = state.copyWith(duration: dur);
    });

    // Passage automatique en fin de titre (selon le mode répétition)
    _audio.playerStateStream.listen((ps) {
      if (ps.processingState == ProcessingState.completed) {
        _onTrackCompleted();
      }
      // Sync isPlaying avec l'état réel du player
      state = state.copyWith(isPlaying: ps.playing);
    });
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

  // Gère la fin d'un titre selon RepeatMode
  Future<void> _onTrackCompleted() async {
    if (state.repeatMode == RepeatMode.one) {
      await _audio.seek(Duration.zero);
      await _audio.play();
      return;
    }
    if (state.hasNext) {
      await next();
    } else if (state.repeatMode == RepeatMode.all && state.queue.isNotEmpty) {
      // Reboucle au premier titre de la file
      await playTrack(state.queue.first, queue: state.queue);
    }
  }

  Future<void> playTrack(Track track, {List<Track>? queue}) async {
    final q = [...(queue ?? [track])];
    final idx = q.indexOf(track);
    final token = ++_playToken;

    // Affichage immédiat du titre demandé (avant import/résolution)
    state = state.copyWith(
      currentTrack: track,
      queue: q,
      currentIndex: idx < 0 ? 0 : idx,
      isPlaying: true,
      isLiked: track.isFavoris,
      position: Duration.zero,
      duration: track.duration,
    );

    // Reproduit handleClicTrack : import si externe → URL signée → lecture
    final playable = await _resolvePlayable(track);
    if (token != _playToken) return; // un autre titre a été lancé entre-temps

    if (playable == null || playable.audioUrl.isEmpty) {
      debugPrint('Mkzik ▶ aucune URL audio jouable pour "${track.title}"');
      state = state.copyWith(isPlaying: false);
      return;
    }

    // Si l'import a transformé le track (externe → intégré), on met à jour
    // l'entrée correspondante dans la file et le currentTrack.
    if (!identical(playable, track)) {
      final newQueue = [...state.queue];
      final at = newQueue.indexOf(track);
      if (at >= 0) {
        newQueue[at] = playable;
      } else {
        newQueue.add(playable);
      }
      state = state.copyWith(
        currentTrack: playable,
        queue: newQueue,
        currentIndex: newQueue.indexOf(playable),
        duration: playable.duration,
      );
    }

    try {
      // Tag MediaItem → alimente la notification / l'écran verrouillé
      final source = AudioSource.uri(
        Uri.parse(playable.audioUrl),
        tag: MediaItem(
          id: playable.id,
          title: playable.title,
          artist: playable.artist,
          duration: playable.duration > Duration.zero ? playable.duration : null,
          artUri: playable.hasCover ? Uri.tryParse(playable.coverUrl) : null,
        ),
      );
      // setAudioSource laisse le moteur (ExoPlayer/AVPlayer) détecter le format .m4a
      await _audio.setAudioSource(source);
      if (token != _playToken) return;
      await _audio.play();
      // Enregistre l'écoute pour l'historique de l'utilisateur (cf. React)
      if (playable.apiId != null) {
        TrackService.recordPlay(playable.apiId!);
      }
    } catch (e) {
      debugPrint('Mkzik ▶ erreur lecture "${track.title}" : $e');
      if (token == _playToken) state = state.copyWith(isPlaying: false);
    }
  }

  /// Rend un track réellement jouable (cf. React `handleClicTrack`) :
  /// 1. externe non intégré (`needsImport`) → import via Python, on récupère le track intégré
  /// 2. si pas d'URL audio directe (http) → URL signée via `api/tracks/{id}/audio`
  Future<Track?> _resolvePlayable(Track track) async {
    var t = track;

    // 1) Import des externes non intégrés (avec notification de progression)
    if (t.needsImport) {
      final imported = await _ref.read(importProvider.notifier).startAndWait(t);
      if (imported == null) return null;
      t = imported;
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

  Future<void> togglePlayPause() async {
    if (_audio.playing) {
      await _audio.pause();
    } else {
      await _audio.play();
    }
  }

  // next/previous cycliques (cf. React : index modulo la longueur de la file)
  Future<void> next() async {
    final n = state.queue.length;
    if (n == 0) return;
    final nextIdx = (state.currentIndex + 1) % n;
    await playTrack(state.queue[nextIdx], queue: state.queue);
  }

  Future<void> previous() async {
    final n = state.queue.length;
    if (n == 0) return;
    final prevIdx = state.currentIndex == 0 ? n - 1 : state.currentIndex - 1;
    await playTrack(state.queue[prevIdx], queue: state.queue);
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
  }

  /// Saute directement à un titre de la file (tap dans la current list).
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    if (index == state.currentIndex) return;
    await playTrack(state.queue[index], queue: state.queue);
  }

  /// Retire un titre de la file. Le titre en cours n'est pas supprimable.
  void removeAt(int index) {
    if (index < 0 || index >= state.queue.length) return;
    if (index == state.currentIndex) return; // on ne retire pas le titre joué
    final list = [...state.queue]..removeAt(index);
    var idx = state.currentIndex;
    if (index < idx) idx -= 1; // décalage si on retire avant le courant
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
    state = state.copyWith(queue: list, currentIndex: newCur < 0 ? state.currentIndex : newCur);
  }

  void toggleShuffle() {
    state = state.copyWith(isShuffle: !state.isShuffle);
  }

  // Cycle entre les 3 modes de répétition
  void cycleRepeat() {
    final next = switch (state.repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    state = state.copyWith(repeatMode: next);
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }
}

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>(
  (ref) => PlayerNotifier(ref),
);
