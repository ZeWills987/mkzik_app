import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
// SMTC : contrôles média système Windows. On masque RepeatMode (défini localement).
import 'package:smtc_windows/smtc_windows.dart' hide RepeatMode;
import '../config/api_config.dart';
import '../models/track.dart';
import '../services/external_track_service.dart';
import '../services/track_service.dart';
import '../services/radio_service.dart';
import '../utils/media.dart';
import 'import_provider.dart';
import 'favourites_provider.dart';
import 'notice_provider.dart';
import 'paginated_tracks_provider.dart' show TrackPageFetcher;
import '../utils/logger.dart';

// Mode de répétition. `off` est conservé pour compat mais n'est plus utilisé :
// on tourne toujours en boucle de file (all) ↔ répétition d'un titre (one), ce
// qui garde les boutons prev/next stables et cycliques dans la notification.
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

  // URLs signées S3 déjà obtenues, par apiId — réutilisées tant qu'elles n'expirent pas.
  final Map<int, SignedAudio> _signedCache = {};
  // Marge avant expiration : une URL qui expire dans la minute est considérée périmée.
  static const _signedExpiryMargin = Duration(seconds: 60);

  // Windows : la playlist native ne contient QUE le titre en cours. WinRT émet
  // de faux changements d'index à chaque insertion/suppression dans sa
  // playlist (titre rechargé à 0 s, bloqué puis sauté). L'enchaînement passe
  // donc entièrement par la file Dart (fin de titre → _advanceFromQueue).
  static final bool _nativeSingleItem = Platform.isWindows;

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
  static const _kNativeAhead = 3; // titres suivants préchargés dans la playlist native
  bool _toppingUpNative = false;

  // Flux Python en cours de résolution en arrière-plan (ids de track).
  final Set<String> _pendingStreams = {};
  // Change quand l'utilisateur lance une autre liste → annule les réinsertions.
  int _queueEpoch = 0;

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

  // Bannière « Chargement du flux… » actuellement affichée (import_provider) —
  // permet de la fermer EN FORCE dès qu'un nouveau titre est demandé, sans
  // attendre que la résolution obsolète se termine (ou timeout) d'elle-même.
  String? _activeStreamJobId;

  // Verrou : bloque _onCurrentIndexChanged pendant les manipulations de playlist
  // (insertions d'hydratation, reconstruction radio) pour éviter les faux "track changed".
  bool _suppressIndexChange = false;

  // Windows : flag pour distinguer un skip utilisateur (next/prev/jumpTo) d'une
  // auto-avance native déclenchée par la fin du flux HTTP (et non de l'audio).
  // WinRT avance dès que le response body est reçu, même si le buffer joue encore.
  bool _userInitiatedSkip = false;

  // Contrôles média système Windows (SMTC) — null sur mobile.
  SMTCWindows? _smtc;

  PlayerNotifier(this._ref) : super(const PlayerState()) {
    _initAudioSession();
    if (Platform.isWindows) _initSmtc();

    // Écoute de la position en temps réel
    _audio.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
      final ms = pos.inMilliseconds;
      if (_playTrack != null && ms > _playMaxMs) _playMaxMs = ms;
    }, onError: (Object e) => mkLog('Mkzik ▶ positionStream erreur : $e'));

    // Écoute de la durée quand un titre est chargé
    _audio.durationStream.listen((dur) {
      if (dur != null) state = state.copyWith(duration: dur);
    }, onError: (Object e) => mkLog('Mkzik ▶ durationStream erreur : $e'));

    // Suivi du buffering — WinRT ne supporte pas BufferingProgress (retourne
    // toujours 1.0 avec une erreur loguée). On désactive le listener sur Windows.
    if (!Platform.isWindows) {
      _audio.bufferedPositionStream.listen((buffered) {
        final dur = state.duration.inMilliseconds;
        if (dur <= 0) return;
        state = state.copyWith(
          bufferedProgress: (buffered.inMilliseconds / dur).clamp(0.0, 1.0),
        );
      }, onError: (_) {});
    }

    // Changement d'index (auto-avance, prev/next notif, fin de titre) → resync
    // de l'état Dart sur le titre réellement joué par le moteur natif.
    _audio.currentIndexStream.listen(_onCurrentIndexChanged,
        onError: (Object e) => mkLog('Mkzik ▶ indexStream erreur : $e'));

    // Sync isPlaying avec l'état réel du player
    _audio.playerStateStream.listen((ps) {
      if (ps.processingState == ProcessingState.completed && !_nativeCoversQueue) {
        unawaited(Future.microtask(_advanceFromQueue));
      }
      state = state.copyWith(isPlaying: ps.playing);
      _smtc?.setPlaybackStatus(ps.playing ? PlaybackStatus.playing : PlaybackStatus.paused);
    }, onError: (Object e) => mkLog('Mkzik ▶ playerStateStream erreur : $e'));

    // Erreurs de flux EN COURS de lecture (URL signée expirée, stream yt-dlp qui
    // meurt…) : sans ce handler la lecture s'arrête en silence. On informe
    // l'utilisateur et on tente d'enchaîner sur le titre suivant.
    _audio.playbackEventStream.listen((_) {}, onError: (Object e) {
      mkLog('Mkzik ▶ erreur de flux en lecture : $e');
      final t = state.currentTrack;
      final unavailable = _isTrackUnavailable(e);
      if (t != null && _playerTracks.length > 1) {
        _ref.read(noticeProvider.notifier).show(unavailable
            ? '« ${t.title} » indisponible — titre suivant'
            : 'Erreur réseau sur « ${t.title} » — titre suivant');
        // Microtask pour sortir du dispatch d'erreur rxdart avant d'appeler seek :
        // sinon seekToNext() tente d'émettre sur le stream qui est encore "firing"
        // → Bad state + boucle infinie.
        unawaited(Future.microtask(next));
      } else {
        _ref
            .read(noticeProvider.notifier)
            .show(unavailable ? 'Titre indisponible' : 'Lecture interrompue, réessaie');
        state = state.copyWith(isPlaying: false);
      }
    });

    // Boucle de file par défaut → prev/next cycliques et stables dans la notif.
    _audio.setLoopMode(LoopMode.all);
  }

  /// Le proxy `/stream` renvoie 404 + "Titre indisponible" quand la track est
  /// réellement morte (supprimée, privée, géo-bloquée) et 502 pour un souci
  /// transitoire. just_audio enrobe l'erreur HTTP dans son message → on matche
  /// le code/libellé dans le texte (les plateformes formatent différemment).
  /// `sourceNotSupportedError` = format non supporté par WinRT → traité comme
  /// indisponible (pas de retry réseau, ça ne changera rien).
  static bool _isTrackUnavailable(Object e) {
    final s = '$e';
    return s.contains('404') ||
        s.contains('Titre indisponible') ||
        s.contains('sourceNotSupported');
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
    // Pour les flux externes (/stream?url=...) : on passe le JWT via header
    // Authorization pour que Python puisse le relayer à Symfony et déclencher
    // le tracking d'écoute. Le user_id en query param reste mais n'est plus
    // le critère d'identité côté Symfony.
    final jwt = ApiConfig.token;
    final headers = (t.needsStream && (jwt?.isNotEmpty ?? false))
        ? <String, String>{'Authorization': 'Bearer $jwt'}
        : null;
    return AudioSource.uri(
      Uri.parse(t.audioUrl),
      headers: headers,
      tag: MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        duration: t.duration > Duration.zero ? t.duration : null,
        artUri: cover.isNotEmpty ? Uri.tryParse(cover) : null,
      ),
    );
  }

  // ── Contrôles média système Windows (SMTC) ─────────────────────────────────

  // Initialise SMTC et branche les boutons (touches média / panneau média) sur
  // le player. Windows uniquement — jamais appelé sur mobile.
  void _initSmtc() {
    _smtc = SMTCWindows(
      // Désactivé tant que rien ne joue : sinon Windows affiche une session
      // média « Mkzik » vide dès l'ouverture de l'app (avant tout play).
      enabled: false,
      config: const SMTCConfig(
        playEnabled: true,
        pauseEnabled: true,
        nextEnabled: true,
        prevEnabled: true,
        stopEnabled: false,
        fastForwardEnabled: false,
        rewindEnabled: false,
      ),
    );
    _smtc!.buttonPressStream.listen((event) {
      switch (event) {
        case PressedButton.play:
        case PressedButton.pause:
          togglePlayPause();
        case PressedButton.next:
          next();
        case PressedButton.previous:
          previous();
        default:
          break;
      }
    });
  }

  bool _smtcEnabled = false;

  // Met à jour les métadonnées affichées par Windows (titre, artiste, pochette).
  // Active la session SMTC au premier titre joué (créée désactivée au boot).
  void _updateSmtcMetadata(Track t) {
    final smtc = _smtc;
    if (smtc == null) return;
    if (!_smtcEnabled) {
      _smtcEnabled = true;
      smtc.enableSmtc();
    }
    final cover = mediaUrl(t.coverUrl);
    smtc.updateMetadata(MusicMetadata(
      title: t.title,
      artist: t.artist,
      thumbnail: cover.isNotEmpty ? cover : null,
    ));
  }

  // Resync quand le moteur change d'index (y compris via les boutons de la notif).
  void _onCurrentIndexChanged(int? i) {
    if (_suppressIndexChange) return;
    if (i == null || i < 0 || i >= _playerTracks.length) return;
    final t = _playerTracks[i];
    // Même titre (l'index a juste été décalé par une insertion d'hydratation) →
    // on ne remet pas la position à 0 et on ne ré-enregistre pas l'écoute.
    final sameTrack = t.id == state.currentTrack?.id;

    // Windows : WinRT auto-avance dès que le buffer HTTP est épuisé, même si
    // l'audio n'est pas fini de jouer. On bloque ce skip si la position est
    // inférieure à 85 % de la durée affichée ET que l'utilisateur n'a pas
    // déclenché le skip lui-même (next/prev/jumpTo).
    if (!sameTrack && Platform.isWindows && !_userInitiatedSkip) {
      final prevDur = state.duration;
      final prevPos = state.position;
      if (prevDur.inSeconds > 5 && prevPos.inSeconds < prevDur.inSeconds * 0.85) {
        mkLog('Mkzik ▶ Windows skip prématuré bloqué '
            '(pos=${prevPos.inSeconds}s / dur=${prevDur.inSeconds}s) → restitution');
        final prevTrack = state.currentTrack;
        if (prevTrack != null) {
          final prevPIdx = _playerTracks.indexWhere((x) => x.id == prevTrack.id);
          if (prevPIdx >= 0) {
            // Microtask : on est dans le dispatch de currentIndexStream, un seek
            // synchrone ré-émettrait sur le même stream → Bad state.
            unawaited(Future.microtask(() async {
              try {
                await _audio.seek(prevPos, index: prevPIdx);
                if (!_audio.playing) await _audio.play();
              } catch (e) {
                mkLog('Mkzik ▶ restitution impossible : $e');
              }
            }));
          }
        }
        return; // bloque le skip prématuré
      }
    }
    _userInitiatedSkip = false;
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
    if (qIdx >= 0 && qIdx == state.queue.length - 1 && loadedAllUpcoming) {
      unawaited(_maybeExtendWithRadio());
    }
    if (!sameTrack) {
      unawaited(_ensureWindow());
      unawaited(_topUpNative());
    }
  }

  // ── Tracking d'écoute (POST /api/plays + PATCH complete) ────────────────────

  // Démarre une écoute pour [t] (récupère le playId du backend).
  Future<void> _beginPlay(Track t) async {
    _updateSmtcMetadata(t); // met à jour le panneau média Windows (no-op ailleurs)
    _playTrack = t;
    _playMaxMs = 0;
    _playId = null;
    if (t.apiId == null) return;
    final id = await TrackService.startPlay(t.apiId!);
    if (_playTrack?.id == t.id) {
      _playId = id;
    } else if (id != null) {
      // Le titre a changé pendant l'await (skip rapide) : cette écoute ne sera
      // jamais clôturée par _finishPlay → on la clôt tout de suite à 0s pour ne
      // pas laisser d'écoute orpheline côté backend.
      unawaited(TrackService.completePlay(id, listenedSeconds: 0, completed: false));
    }
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

  bool _isSignedFresh(SignedAudio s) =>
      s.expiresAt != null && s.expiresAt!.isAfter(DateTime.now().add(_signedExpiryMargin));

  Future<String?> _signedUrlFor(int apiId) async {
    final cached = _signedCache[apiId];
    if (cached != null && _isSignedFresh(cached)) return cached.url;
    final signed = await TrackService.getSignedAudio(apiId);
    if (signed == null) return null;
    _signedCache[apiId] = signed;
    return signed.url;
  }

  Future<Map<int, String>> _signedUrlsFor(List<int> ids) async {
    final out = <int, String>{};
    final missing = <int>[];
    for (final id in ids) {
      final cached = _signedCache[id];
      if (cached != null && _isSignedFresh(cached)) {
        out[id] = cached.url;
      } else {
        missing.add(id);
      }
    }
    if (missing.isNotEmpty) {
      final fetched = await TrackService.getSignedAudioBatch(missing);
      fetched.forEach((id, s) {
        _signedCache[id] = s;
        out[id] = s.url;
      });
    }
    return out;
  }

  /// La source déjà chargée peut-elle être relue telle quelle ? Faux si c'est une
  /// URL signée expirée (ou dont l'expiration est inconnue) → il faut re-signer.
  bool _loadedSourceStillValid(Track t) {
    final id = t.apiId;
    final signed = id == null ? null : _signedCache[id];
    return signed == null || _isSignedFresh(signed);
  }

  /// Titre demandé = titre déjà chargé, URL encore valide → retour au début
  /// sans rappel API. Renvoie false s'il faut recharger.
  Future<bool> _restartCurrent(Track track) async {
    final cur = state.currentTrack;
    if (cur == null || cur.id != track.id || state.isLoading) return false;
    final ps = _audio.processingState;
    if (ps == ProcessingState.idle || ps == ProcessingState.loading) return false;
    if (!_loadedSourceStillValid(cur)) return false;
    try {
      await _audio.seek(Duration.zero);
      await _audio.play();
    } catch (e) {
      mkLog('Mkzik ▶ reprise au début impossible, rechargement : $e');
      return false;
    }
    await _finishPlay();
    unawaited(_beginPlay(cur));
    return true;
  }

  /// Code HTTP renvoyé par le proxy /stream, extrait du message d'erreur du
  /// player (just_audio n'expose ni headers ni corps de réponse).
  static int? _httpStatusIn(Object e) {
    final m = RegExp(r'\b(404|409|429|502|503|504)\b').firstMatch('$e');
    return m == null ? null : int.parse(m.group(1)!);
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
  void _deferUnresolved(Track track, List<Track> q, int idx) {
    final alone = _source.length < 2;
    if (_pendingStreams.add(track.id)) {
      unawaited(_waitForStream(track, _queueEpoch));
    }
    if (alone) {
      state = state.copyWith(isPlaying: false);
      _ref.read(noticeProvider.notifier).show('« ${track.title} » se lancera dès qu\'il est prêt');
      return;
    }
    _skipFailed(q, idx);
  }

  Future<void> _waitForStream(Track track, int epoch) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    var delay = const Duration(seconds: 3);
    var gaveUpUnavailable = false;
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (epoch != _queueEpoch) return;
        final status = await _probeStream(track);
        if (epoch != _queueEpoch) return;
        if (status == 200 || status == 206) {
          await _insertAsNext(track);
          return;
        }
        if (status == 404) {
          gaveUpUnavailable = true;
          break;
        }
        await Future.delayed(delay);
        delay = Duration(seconds: (delay.inSeconds * 2).clamp(3, 30));
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
  Future<int?> _probeStream(Track track) async {
    if (track.pageUrl.isEmpty) return 404;
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(ApiConfig.streamUrl(track.pageUrl)))
        ..headers['Range'] = 'bytes=0-1';
      final jwt = ApiConfig.token;
      if (jwt != null && jwt.isNotEmpty) req.headers['Authorization'] = 'Bearer $jwt';
      final res = await client.send(req).timeout(const Duration(seconds: 60));
      return res.statusCode;
    } catch (_) {
      return null;
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
    if (cur == null || _playlist == null) return;
    final q = [...state.queue];
    if (q.any((x) => x.id == t.id)) return;
    q.insert((state.currentIndex + 1).clamp(0, q.length), t);
    final curSrc = _source.indexWhere((x) => x.id == cur.id);
    _source.insert(curSrc < 0 ? _source.length : curSrc + 1, t);

    final pIdx = _playerTracks.indexWhere((x) => x.id == cur.id);
    _suppressIndexChange = true;
    try {
      // Un flux Python ne va JAMAIS dans la playlist native avant de devenir
      // courant (même logique que _topUpNative) — on coupe ce qui suit le
      // titre courant, l'enchaînement passera par state.queue le moment venu.
      if (pIdx >= 0 && pIdx + 1 < _playerTracks.length) {
        await _playlist!.removeRange(pIdx + 1, _playerTracks.length);
        _playerTracks = _playerTracks.sublist(0, pIdx + 1);
      }
    } catch (e) {
      mkLog('Mkzik ▶ réinsertion de "${t.title}" impossible : $e');
    } finally {
      _suppressIndexChange = false;
    }
    state = state.copyWith(queue: q);
    await _applyNativeLoopMode();
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
    _activeStreamJobId = streamJobId;

    // Démarrage IMMÉDIAT avec une playlist d'un seul titre (le titre cliqué) →
    // pas d'attente de la signature du reste de la file. Le reste est hydraté
    // en arrière-plan (cf. _hydrateQueue) sans couper la lecture.
    // 2 tentatives : les flux externes (yt-dlp) échouent parfois de façon
    // transitoire — un retry immédiat suffit souvent.
    // Ferme le job de stream (bannière) et oublie qu'il est actif — à appeler
    // sur CHAQUE sortie (succès, erreur, obsolescence) pour ne jamais laisser
    // de bannière orpheline.
    void closeStreamJob({String? errorMessage}) {
      if (streamJobId == null) return;
      if (errorMessage != null) {
        importNotifier.streamError(streamJobId, errorMessage);
      } else {
        importNotifier.dismiss(streamJobId);
      }
      if (_activeStreamJobId == streamJobId) _activeStreamJobId = null;
    }

    var started = false;
    for (var attempt = 1; attempt <= 2 && !started; attempt++) {
      try {
        _playerTracks = [current];
        _playlist = ConcatenatingAudioSource(children: [_audioSourceFor(current)]);
        // Timeout explicite : sans lui, un flux Python qui accepte la connexion
        // sans jamais répondre laisse cet await suspendu indéfiniment — aucune
        // exception, donc le catch n'est jamais atteint et la bannière
        // "Chargement du flux…" reste affichée pour toujours.
        await _audio
            .setAudioSource(_playlist!, initialIndex: 0, initialPosition: Duration.zero)
            // WinRT (Windows) initialise les streams S3/HTTPS plus lentement
            // qu'ExoPlayer → timeout doublé pour éviter les faux TimeoutException.
            .timeout(Duration(seconds: Platform.isWindows
                ? (track.needsStream ? 50 : 60)
                : (track.needsStream ? 25 : 15)));
        if (token != _playToken) {
          closeStreamJob();
          return;
        }
        await _applyNativeLoopMode();
        await _audio.setShuffleModeEnabled(state.isShuffle);
        await _audio.play();
        started = true;
        // Flux prêt → on retire le spinner.
        closeStreamJob();
        // Démarre le tracking d'écoute du titre courant (l'event d'index initial
        // est "same track" → on le démarre explicitement ici).
        unawaited(_beginPlay(current));
      } catch (e) {
        mkLog('Mkzik ▶ erreur lecture "${track.title}" (tentative $attempt/2) : $e');
        if (token != _playToken) {
          closeStreamJob();
          return;
        }
        // 404 du proxy /stream = titre réellement indisponible (supprimé,
        // privé, géo-bloqué) → inutile de retenter ; timeout/502/autres =
        // transitoire → un retry immédiat vaut le coup.
        final timedOut = e is TimeoutException;
        final unavailable = _isTrackUnavailable(e);
        final status = _httpStatusIn(e);
        if (status == 409) {
          // Requête annulée côté serveur (client parti) → silencieux.
          closeStreamJob();
          state = state.copyWith(isPlaying: false);
          return;
        }
        // Flux Python lent / anti-bot / surcharge : on n'attend pas. Le titre
        // est retiré de la file, on enchaîne, et il revient en « suivant » dès
        // que Python l'a résolu (cf. _waitForStream).
        final transient = timedOut || const {429, 502, 503, 504}.contains(status);
        if (track.needsStream && transient && !unavailable) {
          closeStreamJob();
          _deferUnresolved(track, q, selIdx);
          return;
        }
        if (unavailable && q.length > 1) {
          closeStreamJob(errorMessage: 'Titre indisponible');
          _skipFailed(q, selIdx);
          return;
        }
        if (unavailable || attempt == 2) {
          closeStreamJob(
            errorMessage: unavailable
                ? 'Titre indisponible'
                : (timedOut ? 'Le flux met trop de temps à répondre' : 'Erreur réseau, réessaie'),
          );
          state = state.copyWith(isPlaying: false);
          return;
        }
      }
    }

    // Hydrate le reste de la file en arrière-plan (signe + insère autour du
    // titre courant). Non attendu → la lecture a déjà démarré.
    unawaited(_hydrateQueue(q, selIdx, current, token).then((_) {
      if (token == _playToken) return _ensureWindow();
    }));
  }

  /// Résout (signe) les autres titres de la file et les insère autour du titre
  /// courant dans la playlist native, sans interrompre la lecture en cours.
  /// Les internes sont signés en UNE requête batch (`POST api/tracks/sign-batch`)
  /// au lieu d'un GET .../audio par titre (rafale de N requêtes sur une playlist).
  Future<void> _hydrateQueue(List<Track> q, int selIdx, Track current, int token) async {
    if (token != _playToken) return;
    await _topUpNative();
  }

  /// La playlist native ne contient que le titre courant + les [_kNativeAhead]
  /// suivants (gapless sur l'enchaînement). Elle est complétée au fil de
  /// l'écoute, jamais d'un bloc : chaque ajout coûte une signature S3 et une
  /// mutation ExoPlayer. Les précédents ne sont pas préchargés (« précédent »
  /// passe par la file, cf. previous()).
  Future<void> _topUpNative() async {
    if (_nativeSingleItem || _toppingUpNative || _playlist == null || _playerTracks.isEmpty) return;
    _toppingUpNative = true;
    try {
      final q = state.queue;
      final lastQ = q.indexWhere((t) => t.id == _playerTracks.last.id);
      if (lastQ < 0) return;
      final target = (state.currentIndex + _kNativeAhead).clamp(0, q.length - 1);
      if (lastQ >= target) return;
      final token = _playToken;
      // On ne pousse JAMAIS un flux Python (needsStream) en avance dans le
      // lecteur natif : ExoPlayer/AVPlayer précharge le média suivant d'une
      // ConcatenatingAudioSource pour l'enchaînement gapless, ce qui déclenche
      // sinon une résolution yt-dlp côté Python avant que le titre ne soit
      // réellement en cours. On s'arrête donc juste avant le premier flux
      // Python rencontré — il sera résolu à la volée quand il deviendra
      // courant (cf. _playFromSource / _advanceFromQueue).
      final all = q.sublist(lastQ + 1, target + 1);
      final streamIdx = all.indexWhere((t) => t.needsStream);
      final tracks = streamIdx < 0 ? all : all.sublist(0, streamIdx);
      if (tracks.isEmpty) return;
      final resolved = await _resolveBatch(tracks);
      if (token != _playToken || _playlist == null) return;
      // La file a pu bouger pendant la signature : on n'ajoute que si la
      // playlist native s'arrête toujours juste avant ces titres.
      final nowLast = state.queue.indexWhere((t) => t.id == _playerTracks.last.id);
      if (nowLast < 0 || nowLast + 1 >= state.queue.length || state.queue[nowLast + 1].id != tracks.first.id) {
        return;
      }
      final add = [for (final r in resolved) if (r != null && r.audioUrl.isNotEmpty) r];
      if (add.isEmpty) return;
      _suppressIndexChange = true;
      try {
        await _playlist!.addAll([for (final t in add) _audioSourceFor(t)]);
        _playerTracks = [..._playerTracks, ...add];
      } finally {
        _suppressIndexChange = false;
      }
      await _applyNativeLoopMode();
    } catch (e) {
      mkLog('Mkzik ▶ complément de la playlist native impossible : $e');
    } finally {
      _toppingUpNative = false;
    }
  }

  /// Après un réordonnancement / retrait : on coupe la playlist native après le
  /// titre courant puis on la recomplète dans le nouvel ordre de la file.
  Future<void> _resyncNativeAhead() async {
    if (_nativeSingleItem || _playlist == null) return;
    final cur = state.currentTrack;
    final pIdx = cur == null ? -1 : _playerTracks.indexWhere((t) => t.id == cur.id);
    if (pIdx < 0) return;
    if (pIdx + 1 < _playerTracks.length) {
      _suppressIndexChange = true;
      try {
        await _playlist!.removeRange(pIdx + 1, _playerTracks.length);
        _playerTracks = _playerTracks.sublist(0, pIdx + 1);
      } finally {
        _suppressIndexChange = false;
      }
    }
    await _topUpNative();
  }


  /// Rend un track réellement jouable :
  /// • `isSymfonyPlayable` (interne OU externe `in_mkzik`) → URL signée Symfony.
  /// • `needsStream` (externe pur, non dans la BD) → flux temps réel Python.
  ///   L'import S3 reste une action explicite (bouton), jamais un effet de bord du play.
  Future<Track?> _resolvePlayable(Track track) async {
    var t = track;

    if (t.needsStream) {
      if (t.pageUrl.isEmpty) return null;
      return t.copyWith(audioUrl: ApiConfig.streamUrl(t.pageUrl));
    }

    // Symfony : URL signée si l'audio n'est pas directement jouable
    if (!t.hasPlayableUrl && t.apiId != null) {
      final signed = await _signedUrlFor(t.apiId!);
      if (signed != null && signed.isNotEmpty) t = t.copyWith(audioUrl: signed);
    }

    return t.audioUrl.isNotEmpty ? t : null;
  }

  /// Résolution légère pour les autres titres de la file (préchargement).
  /// Même logique que [_resolvePlayable] : Symfony pour `isSymfonyPlayable`,
  /// flux Python pour `needsStream`. Renvoie null si injouable.
  /// Sur Windows, les flux temps réel (needsStream) ne sont pas supportés par
  /// WinRT (sourceNotSupportedError) → on les exclut de la file silencieusement.
  Future<Track?> _resolveForQueue(Track t) async {
    if (t.hasPlayableUrl) return t;
    if (t.needsStream) return null; // résolu uniquement quand la track devient courante
    if (t.apiId != null) {
      final signed = await _signedUrlFor(t.apiId!);
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
      if (!_nativeSingleItem) {
        _playerTracks = [..._playerTracks, ...resolved];
        await _playlist!.addAll(sources);
      }
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
    if (seed == null || _playlist == null) return false;
    if (_playerTracks.indexWhere((t) => t.id == seed.id) < 0) return false;
    // Les suggestions peuvent prendre ~15 s : si l'utilisateur lance un autre
    // titre pendant ce temps (_playToken changé), on abandonne — sinon on
    // opérerait la playlist native avec des index périmés.
    final token = _playToken;
    try {
      final suggestions = await RadioService.suggestionsFor(seed);
      if (token != _playToken || _playlist == null) return false;
      final seen = {RadioService.dedupKey(seed)};
      final fresh = <Track>[for (final t in suggestions) if (seen.add(RadioService.dedupKey(t))) t];
      if (fresh.isEmpty) return false;

      final resolved = <Track>[];
      final sources = <AudioSource>[];
      for (final t in fresh.take(20)) {
        final r = await _resolveForQueue(t);
        if (token != _playToken) return false;
        if (r == null || r.audioUrl.isEmpty) continue;
        resolved.add(r);
        sources.add(_audioSourceFor(r));
      }
      if (resolved.isEmpty || token != _playToken || _playlist == null) return false;

      // L'index du seed est recalculé APRÈS les awaits (l'hydratation en
      // arrière-plan a pu décaler la playlist native entre-temps).
      final pIdx = _playerTracks.indexWhere((t) => t.id == seed.id);
      if (pIdx < 0) return false;

      // Reconstruction : [seed, R1, R2, …] — on retire tout ce qui précède le
      // courant pour que LoopMode.all ne reboucle jamais sur l'ancienne playlist.
      final seedTrack = _playerTracks[pIdx];
      if (!_nativeSingleItem) {
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
      }

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
      await _applyNativeLoopMode();
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
    if (_audio.playing) {
      await _audio.pause();
    } else {
      await _audio.play();
    }
  }

  // next/previous cycliques. On préfère le seek natif (déjà en playlist) ;
  // sinon on joue directement depuis state.queue (ex: tracks needsStream pas
  // encore insérées dans la native playlist au moment du tap).
  Future<void> next() async {
    _userInitiatedSkip = true;
    if (_audio.hasNext) {
      await _audio.seekToNext();
      return;
    }
    await _advanceFromQueue();
  }

  Future<void> previous() async {
    _userInitiatedSkip = true;
    if (_audio.hasPrevious) {
      await _audio.seekToPrevious();
      return;
    }
    final cur = state.currentTrack;
    if (cur == null || _source.length < 2) return;
    final srcIdx = _source.indexWhere((t) => t.id == cur.id);
    final prevIdx = srcIdx <= 0 ? _source.length - 1 : srcIdx - 1;
    await _playFromSource(_source[prevIdx]);
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
      await _topUpNative();
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

  /// Résout des titres pour la playlist native (URL signée en lot / flux Python).
  Future<List<Track?>> _resolveBatch(List<Track> tracks) async {
    final signed = await _signedUrlsFor([
      for (final t in tracks)
        if (!t.hasPlayableUrl && !t.needsStream && t.apiId != null) t.apiId!,
    ]);
    return [
      for (final t in tracks)
        if (t.hasPlayableUrl)
          t
        else if (t.needsStream)
          (t.pageUrl.isNotEmpty ? t.copyWith(audioUrl: ApiConfig.streamUrl(t.pageUrl)) : null)
        else
          (t.apiId != null && signed[t.apiId!] != null ? t.copyWith(audioUrl: signed[t.apiId!]) : null),
    ];
  }

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

  Future<void> seekTo(Duration position) async {
    // Pas de seek tant que la source n'est pas prête (résolution yt-dlp en
    // cours) : just_audio peut lever ou seek sur la mauvaise source.
    final ps = _audio.processingState;
    if (ps == ProcessingState.idle || ps == ProcessingState.loading) return;
    try {
      await _audio.seek(position);
    } catch (e) {
      mkLog('Mkzik ▶ seek impossible : $e');
    }
  }

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
    // • externe non importé → flux temps réel Python (sinon il serait ajouté à
    //   la file UI mais PAS à la playlist native → sauté à l'auto-avance).
    var t = track;
    if (!t.hasPlayableUrl && !t.needsImport && t.apiId != null) {
      final signed = await _signedUrlFor(t.apiId!);
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

    // Reflète l'ajout dans la playlist native — jamais pour un flux Python
    // (needsStream) : ExoPlayer/AVPlayer précharge dès l'insertion, ce qui
    // appellerait Python avant que ce titre ne soit réellement courant. Il
    // sera résolu à la volée à son tour (cf. _advanceFromQueue).
    if (!_nativeSingleItem && !t.needsStream && _playlist != null && t.audioUrl.isNotEmpty) {
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
    _userInitiatedSkip = true;
    final t = state.queue[index];
    final pIdx = _playerTracks.indexWhere((x) => x.id == t.id);
    if (pIdx >= 0) {
      await _audio.seek(Duration.zero, index: pIdx); // titre déjà dans la playlist
    } else {
      await _playFromSource(t); // externe/non résolu → résout + recharge
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
    _replaceWindowInSource(state.queue, list);
    state = state.copyWith(queue: list, currentIndex: idx);

    // Reflète la suppression dans la playlist native
    final pIdx = _playerTracks.indexWhere((x) => x.id == removed.id);
    if (pIdx >= 0 && _playlist != null) {
      _playerTracks.removeAt(pIdx);
      _playlist!.removeAt(pIdx);
    }
    unawaited(_topUpNative());
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

    // La playlist native ne précharge que quelques suivants : on la recompose
    // après le titre courant dans le nouvel ordre.
    unawaited(_resyncNativeAhead());
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
    state = state.copyWith(repeatMode: next);
    await _applyNativeLoopMode();
  }

  /// Windows : la playlist native ne contient pas les flux Python (WinRT les
  /// ouvre en avance et lève des decodeError qu'on ne sait pas attribuer).
  /// Si elle ne couvre pas toute la file, la boucle native est coupée et
  /// l'enchaînement se fait depuis `state.queue` (cf. [_advanceFromQueue]).
  /// Vrai si la playlist native contient toute la liste (rien à charger en plus)
  /// → la boucle native peut gérer l'enchaînement seule.
  bool get _nativeCoversQueue =>
      _playerTracks.length >= state.queue.length &&
      state.queue.length >= _source.length &&
      !_sourceHasMore;

  Future<void> _applyNativeLoopMode() async {
    final mode = state.repeatMode == RepeatMode.one
        ? LoopMode.one
        : (_nativeCoversQueue ? _loopFor(state.repeatMode) : LoopMode.off);
    await _audio.setLoopMode(mode);
  }

  /// Titre suivant de la liste (charge la suite si besoin), en boucle.
  Future<void> _advanceFromQueue() async {
    if (state.isLoading) return;
    final cur = state.currentTrack;
    if (cur == null) return;
    var srcIdx = _source.indexWhere((t) => t.id == cur.id);
    if (srcIdx >= _source.length - 1 && _sourceHasMore) {
      await loadMoreUpcoming();
      srcIdx = _source.indexWhere((t) => t.id == cur.id);
    }
    if (_source.length < 2) return;
    final nextIdx = (srcIdx + 1) % _source.length;
    await _playFromSource(_source[nextIdx]);
  }

  @override
  void dispose() {
    unawaited(_finishPlay()); // clôt l'écoute en cours
    unawaited(_smtc?.dispose());
    _audio.dispose();
    super.dispose();
  }
}

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>(
  (ref) => PlayerNotifier(ref),
);
