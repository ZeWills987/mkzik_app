import '../../config/api_config.dart';
import '../../models/track.dart';
import '../../services/track_service.dart';

typedef SignOne = Future<SignedAudio?> Function(int apiId);
typedef SignMany = Future<Map<int, SignedAudio>> Function(List<int> apiIds);

/// Transforme un [Track] en titre réellement jouable (avec une `audioUrl`) :
///  • `needsStream` (externe pur, pas dans la BD) → flux temps réel Python `/stream?url=` ;
///  • sinon, URL signée S3 demandée à Symfony, mise en cache tant qu'elle n'expire pas.
///
/// L'import S3 d'un titre externe reste une action explicite (bouton), jamais un
/// effet de bord de la lecture.
///
/// Aucune dépendance au lecteur audio ni à la file : les appels réseau sont
/// injectables (par défaut [TrackService] / [ApiConfig]) pour pouvoir tester
/// sans API.
class TrackResolver {
  TrackResolver({
    SignOne? signOne,
    SignMany? signMany,
    String Function(String pageUrl)? streamUrl,
    DateTime Function()? now,
    Duration expiryMargin = const Duration(seconds: 60),
  })  : _signOne = signOne ?? TrackService.getSignedAudio,
        _signMany = signMany ?? TrackService.getSignedAudioBatch,
        _streamUrl = streamUrl ?? ApiConfig.streamUrl,
        _now = now ?? DateTime.now,
        _margin = expiryMargin;

  final SignOne _signOne;
  final SignMany _signMany;
  final String Function(String) _streamUrl;
  final DateTime Function() _now;

  /// Marge avant expiration : une URL qui expire dans la minute est considérée périmée.
  final Duration _margin;

  /// URLs signées déjà obtenues, par apiId — réutilisées tant qu'elles sont fraîches.
  final Map<int, SignedAudio> _cache = {};

  bool _isFresh(SignedAudio s) => s.expiresAt != null && s.expiresAt!.isAfter(_now().add(_margin));

  /// URL signée d'un titre (cache ou appel API). Null si Symfony ne la fournit pas.
  Future<String?> signedUrlFor(int apiId) async {
    final cached = _cache[apiId];
    if (cached != null && _isFresh(cached)) return cached.url;
    final signed = await _signOne(apiId);
    if (signed == null) return null;
    _cache[apiId] = signed;
    return signed.url;
  }

  /// URLs signées de plusieurs titres : les fraîches viennent du cache, les autres
  /// sont demandées en UNE requête batch. Les ids non signables sont absents.
  Future<Map<int, String>> signedUrlsFor(List<int> ids) async {
    final out = <int, String>{};
    final missing = <int>[];
    for (final id in ids) {
      final cached = _cache[id];
      if (cached != null && _isFresh(cached)) {
        out[id] = cached.url;
      } else {
        missing.add(id);
      }
    }
    if (missing.isNotEmpty) {
      final fetched = await _signMany(missing);
      fetched.forEach((id, s) {
        _cache[id] = s;
        out[id] = s.url;
      });
    }
    return out;
  }

  /// La source déjà chargée peut-elle être relue telle quelle ? Faux si c'est une
  /// URL signée expirée (ou dont l'expiration est inconnue) → il faut re-signer.
  bool isLoadedSourceValid(Track t) {
    final id = t.apiId;
    final signed = id == null ? null : _cache[id];
    return signed == null || _isFresh(signed);
  }

  /// Rend un titre réellement jouable, ou null s'il ne l'est pas.
  Future<Track?> resolvePlayable(Track track) async {
    var t = track;

    if (t.needsStream) {
      if (t.pageUrl.isEmpty) return null;
      return t.copyWith(audioUrl: _streamUrl(t.pageUrl));
    }

    // Symfony : URL signée si l'audio n'est pas directement jouable
    if (!t.hasPlayableUrl && t.apiId != null) {
      final signed = await signedUrlFor(t.apiId!);
      if (signed != null && signed.isNotEmpty) t = t.copyWith(audioUrl: signed);
    }

    return t.audioUrl.isNotEmpty ? t : null;
  }

  /// Résolution légère pour les autres titres de la file (préchargement).
  /// Même logique que [resolvePlayable] sauf pour les flux Python (`needsStream`) :
  /// renvoie null — ils ne sont résolus que quand ils deviennent le titre courant.
  Future<Track?> resolveForQueue(Track t) async {
    if (t.hasPlayableUrl) return t;
    if (t.needsStream) return null;
    if (t.apiId != null) {
      final signed = await signedUrlFor(t.apiId!);
      if (signed != null && signed.isNotEmpty) return t.copyWith(audioUrl: signed);
    }
    return null;
  }

  /// Résout plusieurs titres d'un coup (URL signées en un seul batch / flux Python).
  /// Un élément null = titre injouable. L'ordre de [tracks] est conservé.
  Future<List<Track?>> resolveBatch(List<Track> tracks) async {
    final signed = await signedUrlsFor([
      for (final t in tracks)
        if (!t.hasPlayableUrl && !t.needsStream && t.apiId != null) t.apiId!,
    ]);
    return [
      for (final t in tracks)
        if (t.hasPlayableUrl)
          t
        else if (t.needsStream)
          (t.pageUrl.isNotEmpty ? t.copyWith(audioUrl: _streamUrl(t.pageUrl)) : null)
        else
          (t.apiId != null && signed[t.apiId!] != null ? t.copyWith(audioUrl: signed[t.apiId!]) : null),
    ];
  }
}
