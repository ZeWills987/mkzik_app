import 'dart:async';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/track.dart';

/// Résultat d'une sonde du proxy /stream.
typedef StreamProbe = ({int? status, Duration? retryAfter});

/// Sonde le proxy /stream (1er octet). Python partage la résolution en cours et
/// met le résultat en cache → un 206 signifie que le titre est prêt.
Future<StreamProbe> probeStream(Track track) async {
  if (track.pageUrl.isEmpty) return (status: 404, retryAfter: null);
  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(ApiConfig.streamUrl(track.pageUrl)))
      ..headers['Range'] = 'bytes=0-1';
    final jwt = ApiConfig.token;
    if (jwt != null && jwt.isNotEmpty) req.headers['Authorization'] = 'Bearer $jwt';
    final res = await client.send(req).timeout(const Duration(seconds: 60));
    // Retry-After en secondes, borné : on ignore une valeur absurde plutôt que
    // de suspendre la surveillance ou de re-solliciter trop vite.
    final seconds = int.tryParse(res.headers['retry-after'] ?? '');
    final retryAfter = (seconds != null && seconds >= 1 && seconds <= 120) ? Duration(seconds: seconds) : null;
    return (status: res.statusCode, retryAfter: retryAfter);
  } catch (_) {
    return (status: null, retryAfter: null);
  } finally {
    client.close();
  }
}

/// Surveille en arrière-plan un flux Python pas encore prêt, jusqu'à ce qu'il
/// le soit (→ [watch] appelle `onReady`) ou qu'on abandonne (→ `onGiveUp`).
///
/// Chaque sonde consomme une IP de sortie côté Python (pool limité) : on ne
/// sonde JAMAIS pendant que le pool est encore bloqué. Le serveur est seul à
/// connaître l'état du pool → l'intervalle vient exclusivement de son
/// `Retry-After` ; à défaut (notamment après l'échec de lecture initial, dont
/// just_audio n'expose pas les en-têtes) : 30 s, ou 10 s après un 429.
class StreamReadinessWatcher {
  StreamReadinessWatcher({
    Future<StreamProbe> Function(Track track)? probe,
    Future<void> Function(Duration d)? wait,
    this.defaultWait = const Duration(seconds: 30),
    this.maxProbes = 4,
  })  : _probe = probe ?? probeStream,
        _wait = wait ?? ((d) => Future<void>.delayed(d));

  final Future<StreamProbe> Function(Track track) _probe;
  final Future<void> Function(Duration d) _wait;
  final Duration defaultWait;
  final int maxProbes;
  final Set<String> _pending = {};

  /// Délai avant la première sonde, selon le code de l'échec de lecture initial.
  Duration firstDelay(int? status) => status == 429 ? const Duration(seconds: 10) : defaultWait;

  bool isWatching(String trackId) => _pending.contains(trackId);

  /// Lance la surveillance de [track] (sans effet si elle est déjà en cours).
  /// [isCurrent] devient faux quand l'utilisateur lance une autre liste : on
  /// abandonne alors sans rien signaler.
  Future<void> watch(
    Track track, {
    required Duration firstDelay,
    required bool Function() isCurrent,
    required Future<void> Function(Track track) onReady,
    required void Function(bool unavailable) onGiveUp,
  }) async {
    if (!_pending.add(track.id)) return;
    var unavailable = false;
    try {
      await _wait(firstDelay);
      for (var probes = 0; probes < maxProbes; probes++) {
        if (!isCurrent()) return;
        final probe = await _probe(track);
        if (!isCurrent()) return;
        final status = probe.status;
        if (status == 200 || status == 206) {
          await onReady(track);
          return;
        }
        if (status == 404) {
          unavailable = true;
          break;
        }
        // 409 (requête annulée) : on n'insiste pas. 401 : jeton absent ou
        // expiré, inutile de re-solliciter le serveur.
        if (status == 409) return;
        if (status == 401) break;
        if (probes == maxProbes - 1) break;
        await _wait(probe.retryAfter ?? defaultWait);
      }
      if (isCurrent()) onGiveUp(unavailable);
    } finally {
      _pending.remove(track.id);
    }
  }
}
