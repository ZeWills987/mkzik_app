import 'dart:async';
import 'dart:io' show Platform;
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../../config/api_config.dart';
import '../../models/track.dart';
import '../../utils/logger.dart';
import '../../utils/media.dart';
import 'audio_engine.dart';

/// Réglages qui diffèrent selon la plateforme.
class EngineProfile {
  /// Délai pour charger un flux temps réel Python (`/stream`).
  final Duration streamLoadTimeout;

  /// Délai pour charger une URL signée (fichier).
  final Duration fileLoadTimeout;

  /// La plateforme fournit-elle la position mise en tampon ? WinRT ne supporte
  /// pas BufferingProgress (renvoie toujours 1.0 avec une erreur loguée).
  final bool hasBufferedPosition;

  /// Peut-on tenir le titre précédent / suivant prêts dans le moteur ?
  final bool supportsNeighbors;

  const EngineProfile({
    required this.streamLoadTimeout,
    required this.fileLoadTimeout,
    required this.hasBufferedPosition,
    required this.supportsNeighbors,
  });

  /// Sans lui, un flux Python qui accepte la connexion sans jamais répondre
  /// laisserait le chargement suspendu indéfiniment.
  Duration loadTimeoutFor(Track t) => t.needsStream ? streamLoadTimeout : fileLoadTimeout;

  static const mobile = EngineProfile(
    streamLoadTimeout: Duration(seconds: 25),
    fileLoadTimeout: Duration(seconds: 15),
    hasBufferedPosition: true,
    supportsNeighbors: true,
  );

  /// WinRT initialise les streams S3/HTTPS plus lentement qu'ExoPlayer : délais
  /// augmentés pour éviter les faux TimeoutException.
  static const windows = EngineProfile(
    streamLoadTimeout: Duration(seconds: 50),
    fileLoadTimeout: Duration(seconds: 60),
    hasBufferedPosition: false,
    supportsNeighbors: false, // WinRT : on garde un seul titre, comme avant
  );

  factory EngineProfile.forPlatform() => Platform.isWindows ? windows : mobile;
}

/// [AudioEngine] basé sur just_audio (+ just_audio_background pour la
/// notification / l'écran verrouillé sur mobile).
///
/// Le titre courant est enveloppé dans une `ConcatenatingAudioSource` (comme
/// avant sur Windows). Là où c'est supporté, [setNeighbors] y ajoute le titre
/// précédent et le suivant : la notification affiche alors suivant / précédent
/// et l'enchaînement est sans coupure. L'ordre des titres reste décidé par la file.
class JustAudioEngine implements AudioEngine {
  JustAudioEngine({EngineProfile? profile}) : profile = profile ?? EngineProfile.forPlatform() {
    unawaited(_initAudioSession());
    // Erreurs de flux EN COURS de lecture : sans ce relais la lecture s'arrête
    // en silence.
    _audio.playbackEventStream.listen((_) {}, onError: (Object e) => _errors.add(e));
    _audio.currentIndexStream.listen((_) => _checkMoved());
  }

  final EngineProfile profile;
  final AudioPlayer _audio = AudioPlayer();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  final StreamController<Track> _moved = StreamController<Track>.broadcast();

  // Ce que contient `_playlist`, enfant par enfant (même ordre) : en général
  // [précédent?, courant, suivant?], avec des restes après un enchaînement.
  ConcatenatingAudioSource? _playlist;
  List<Track> _items = [];
  int _idx = 0; // index attendu du titre courant dans `_playlist`
  bool _editing = false; // modification de `_playlist` en cours
  // Juste après une modification, l'index du lecteur peut avoir une longueur de
  // retard : on n'y voit pas un changement de titre tant qu'il n'a pas rattrapé
  // `_idx` (ou qu'un court délai n'est pas écoulé).
  bool _settling = false;
  Timer? _settleTimer;
  Future<void> _editQueue = Future.value();

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

  @override
  Stream<Duration> get positionStream => _audio.positionStream;

  @override
  Stream<Duration?> get durationStream => _audio.durationStream;

  @override
  Stream<Duration>? get bufferedStream => profile.hasBufferedPosition ? _audio.bufferedPositionStream : null;

  @override
  Stream<bool> get playingStream => _audio.playingStream;

  @override
  Stream<void> get completedStream =>
      _audio.processingStateStream.where((s) => s == ProcessingState.completed);

  @override
  Stream<Object> get errorStream => _errors.stream;

  @override
  bool get playing => _audio.playing;

  @override
  bool get canSeek {
    final ps = _audio.processingState;
    return ps != ProcessingState.idle && ps != ProcessingState.loading;
  }

  // Construit une source audio taguée (alimente la notification / lockscreen).
  // La pochette est nettoyée (mediaUrl) → URL propre haute résolution : le système
  // l'affiche en grand et en extrait les couleurs pour teinter la notif.
  AudioSource _sourceFor(Track t) {
    final cover = mediaUrl(t.coverUrl);
    // Flux externes (/stream?url=...) : on passe le JWT en en-tête Authorization
    // pour que Python puisse le relayer à Symfony et déclencher le suivi d'écoute.
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

  @override
  Future<void> load(Track track) async {
    final playlist = ConcatenatingAudioSource(children: [_sourceFor(track)]);
    _playlist = playlist;
    _items = [track];
    _idx = 0;
    await _audio
        .setAudioSource(playlist, initialIndex: 0, initialPosition: Duration.zero)
        .timeout(profile.loadTimeoutFor(track));
  }

  @override
  bool get supportsNeighbors => profile.supportsNeighbors;

  @override
  Stream<Track> get movedToNeighbor => _moved.stream;

  @override
  Future<void> setNeighbors({Track? previous, Track? next}) {
    if (!supportsNeighbors) return Future.value();
    // Les modifications se font l'une après l'autre : deux appels rapprochés
    // ne doivent pas se croiser sur la même liste.
    return _editQueue = _editQueue.then((_) => _applyNeighbors(previous, next)).catchError((Object e) {
      mkLog('Mkzik ▶ voisins impossibles : $e');
    });
  }

  Future<void> _applyNeighbors(Track? previous, Track? next) async {
    final playlist = _playlist;
    if (playlist == null || _items.isEmpty) return;
    _editing = true;
    try {
      // Restes d'un enchaînement : on ne garde qu'un voisin de chaque côté.
      while (_items.length > _idx + 2) {
        await playlist.removeAt(_items.length - 1);
        _items.removeLast();
      }
      while (_idx > 1) {
        await playlist.removeAt(0);
        _items.removeAt(0);
        _idx--;
      }
      // Suivant : retirer l'ancien enfant s'il diffère, puis ajouter le nouveau.
      if (_idx + 1 < _items.length && _items[_idx + 1].id != next?.id) {
        await playlist.removeAt(_idx + 1);
        _items.removeAt(_idx + 1);
      }
      if (_idx + 1 >= _items.length && next != null) {
        await playlist.add(_sourceFor(next));
        _items.add(next);
      }
      // Précédent : retirer / insérer en tête décale l'index du titre courant.
      if (_idx > 0 && _items[_idx - 1].id != previous?.id) {
        await playlist.removeAt(0);
        _items.removeAt(0);
        _idx--;
      }
      if (_idx == 0 && previous != null) {
        await playlist.insert(0, _sourceFor(previous));
        _items.insert(0, previous);
        _idx++;
      }
    } finally {
      _editing = false;
      _settling = true;
      _settleTimer?.cancel();
      _settleTimer = Timer(const Duration(milliseconds: 1500), () {
        _settling = false;
        _checkMoved(); // un vrai changement survenu pendant l'attente
      });
    }
  }

  /// Le lecteur est passé sur un autre enfant que `_idx` sans qu'on le demande :
  /// enchaînement sans coupure ou bouton de la notification.
  void _checkMoved() {
    if (_editing || _playlist == null) return;
    final i = _audio.currentIndex;
    if (i == null || i < 0 || i >= _items.length) return;
    if (i == _idx) {
      _settling = false; // l'index a rattrapé nos modifications
      return;
    }
    if (_settling || (i - _idx).abs() != 1) return;
    _idx = i;
    _moved.add(_items[i]);
  }

  /// Le Future de `AudioPlayer.play()` ne se termine qu'à la FIN du titre (ou à la
  /// pause) : on ne l'attend jamais, sinon l'appelant resterait bloqué pendant
  /// toute l'écoute.
  @override
  void play() {
    unawaited(_audio.play().catchError((Object e) {
      mkLog('Mkzik ▶ play() erreur : $e');
    }));
  }

  @override
  Future<void> pause() => _audio.pause();

  @override
  Future<void> seek(Duration position) => _audio.seek(position);

  @override
  Future<void> setRepeatOne(bool value) => _audio.setLoopMode(value ? LoopMode.one : LoopMode.off);

  @override
  Future<void> dispose() async {
    _settleTimer?.cancel();
    await _errors.close();
    await _moved.close();
    await _audio.dispose();
  }
}
