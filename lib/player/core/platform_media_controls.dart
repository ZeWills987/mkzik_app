import 'dart:async';
import 'dart:io' show Platform;
import 'package:smtc_windows/smtc_windows.dart';
import '../../models/track.dart';
import '../../utils/media.dart';
import 'system_media_controls.dart';

/// Contrôles média système Windows (SMTC) : touches média et panneau média.
class WindowsMediaControls implements SystemMediaControls {
  WindowsMediaControls() {
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
    _sub = _smtc.buttonPressStream.listen((event) {
      switch (event) {
        case PressedButton.play:
        case PressedButton.pause:
          _buttons.add(MediaButton.playPause);
        case PressedButton.next:
          _buttons.add(MediaButton.next);
        case PressedButton.previous:
          _buttons.add(MediaButton.previous);
        default:
          break;
      }
    });
  }

  late final SMTCWindows _smtc;
  late final StreamSubscription<PressedButton> _sub;
  final StreamController<MediaButton> _buttons = StreamController<MediaButton>.broadcast();
  bool _enabled = false;

  @override
  Stream<MediaButton> get buttons => _buttons.stream;

  // Active la session SMTC au premier titre joué (créée désactivée au boot).
  @override
  void showTrack(Track track) {
    if (!_enabled) {
      _enabled = true;
      _smtc.enableSmtc();
    }
    final cover = mediaUrl(track.coverUrl);
    _smtc.updateMetadata(MusicMetadata(
      title: track.title,
      artist: track.artist,
      thumbnail: cover.isNotEmpty ? cover : null,
    ));
  }

  @override
  void setPlaying(bool playing) =>
      _smtc.setPlaybackStatus(playing ? PlaybackStatus.playing : PlaybackStatus.paused);

  @override
  Future<void> dispose() async {
    await _sub.cancel();
    await _buttons.close();
    await _smtc.dispose();
  }
}

/// Le bon contrôle média selon la plateforme.
SystemMediaControls createSystemMediaControls() =>
    Platform.isWindows ? WindowsMediaControls() : NoopMediaControls();
