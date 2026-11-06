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

  const EngineProfile({
    required this.streamLoadTimeout,
    required this.fileLoadTimeout,
    required this.hasBufferedPosition,
  });

  /// Sans lui, un flux Python qui accepte la connexion sans jamais répondre
  /// laisserait le chargement suspendu indéfiniment.
  Duration loadTimeoutFor(Track t) => t.needsStream ? streamLoadTimeout : fileLoadTimeout;

  static const mobile = EngineProfile(
    streamLoadTimeout: Duration(seconds: 25),
    fileLoadTimeout: Duration(seconds: 15),
    hasBufferedPosition: true,
  );

  /// WinRT initialise les streams S3/HTTPS plus lentement qu'ExoPlayer : délais
  /// augmentés pour éviter les faux TimeoutException.
  static const windows = EngineProfile(
    streamLoadTimeout: Duration(seconds: 50),
    fileLoadTimeout: Duration(seconds: 60),
    hasBufferedPosition: false,
  );

  factory EngineProfile.forPlatform() => Platform.isWindows ? windows : mobile;
}

/// [AudioEngine] basé sur just_audio (+ just_audio_background pour la
/// notification / l'écran verrouillé sur mobile).
///
/// Un seul titre est chargé à la fois. Il est enveloppé dans une
/// `ConcatenatingAudioSource` d'un seul enfant (comme avant sur Windows) pour ne
/// pas changer le comportement des moteurs natifs.
class JustAudioEngine implements AudioEngine {
  JustAudioEngine({EngineProfile? profile}) : profile = profile ?? EngineProfile.forPlatform() {
    unawaited(_initAudioSession());
    // Erreurs de flux EN COURS de lecture : sans ce relais la lecture s'arrête
    // en silence.
    _audio.playbackEventStream.listen((_) {}, onError: (Object e) => _errors.add(e));
  }

  final EngineProfile profile;
  final AudioPlayer _audio = AudioPlayer();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

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
    await _audio
        .setAudioSource(playlist, initialIndex: 0, initialPosition: Duration.zero)
        .timeout(profile.loadTimeoutFor(track));
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
    await _errors.close();
    await _audio.dispose();
  }
}
