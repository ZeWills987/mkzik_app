/// Modèle de domaine d'une track — **données pures**, sans dépendance Flutter.
/// Tout l'habillage visuel (couleurs, décor) vit dans `track_visuals.dart`.
class Track {
  final String id;
  final int? apiId; // id numérique de l'API (pour like / audio signé)
  final String title;
  final String artist;
  final String coverUrl; // = thumbnails (URL image réseau), '' si absente
  final String pageUrl; // = url (page d'origine, requise pour l'import externe)
  final Duration duration;
  final String audioUrl;
  final int likesCount; // nombre de likes brut
  final int listen; // nombre d'écoutes
  final bool isFavoris; // déjà liké par l'utilisateur
  final String source; // '' = interne/intégré ; 'ytm'/'sc'/... = externe à importer
  final List<String> platforms; // ex: ['youtube'], ['soundcloud']
  final DateTime? publishedAt; // date de publication (null si inconnue)

  const Track({
    required this.id,
    this.apiId,
    required this.title,
    required this.artist,
    required this.coverUrl,
    this.pageUrl = '',
    required this.duration,
    required this.audioUrl,
    this.likesCount = 0,
    this.listen = 0,
    this.isFavoris = false,
    this.source = '',
    this.platforms = const [],
    this.publishedAt,
  });

  bool get hasCover => coverUrl.isNotEmpty;

  /// Externe non intégré : possède une `source` → doit être importé avant lecture.
  /// (cf. React : `if (track.source)`). Les tracks internes/intégrés ont source vide.
  bool get needsImport => source.isNotEmpty;
  bool get isExternal => needsImport;

  /// URL audio directement jouable ? (sinon il faut une URL signée)
  bool get hasPlayableUrl => audioUrl.startsWith('http');

  /// Seed stable pour dériver couleurs / décor (cf. track_visuals.dart).
  int get visualSeed => apiId ?? id.hashCode;

  String get durationFormatted {
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Likes formatés pour l'affichage : 12400 → "12.4k".
  String get likesLabel => formatCount(likesCount);

  /// Date de publication en relatif français : "il y a 3 jours" (null si inconnue).
  String? get publishedLabel => publishedAt == null ? null : timeAgoFr(publishedAt!);

  /// Construit un Track depuis le JSON de l'API Mkzik.
  /// Format (cf. interface/Track.tsx) : { id, title, audio_url, thumbnails,
  /// authors:[{username}], uploader:[{username}], duration(s), listen, likes,
  /// is_favoris, source, platforms, url }
  factory Track.fromJson(Map<String, dynamic> j) {
    // ⚠️ Symfony renvoie `uploader` en LISTE [{username}], Python en STRING
    // ("Drake"). On garde des gardes `is List`/`is String` tolérantes aux deux.
    final authors = j['authors'] is List ? j['authors'] as List : const [];
    final uploaderRaw = j['uploader'];
    String artist = '';
    if (authors.isNotEmpty && authors.first is Map) {
      artist = (authors.first['username'] ?? '').toString();
    } else if (uploaderRaw is List && uploaderRaw.isNotEmpty && uploaderRaw.first is Map) {
      artist = (uploaderRaw.first['username'] ?? '').toString();
    } else if (uploaderRaw is String) {
      artist = uploaderRaw; // format Python (externe)
    }

    final rawId = j['id'];
    final apiId = rawId is int ? rawId : int.tryParse('$rawId');

    return Track(
      // Les externes (ytm/sc) n'ont pas d'id → url comme id stable
      id: rawId?.toString() ??
          (j['url']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString()),
      apiId: apiId,
      title: (j['title'] ?? '').toString(),
      artist: artist,
      coverUrl: (j['thumbnails'] ?? '').toString(),
      pageUrl: (j['url'] ?? '').toString(),
      duration: Duration(seconds: (j['duration'] as num?)?.toInt() ?? 0),
      audioUrl: (j['audio_url'] ?? '').toString(),
      likesCount: (j['likes'] as num?)?.toInt() ?? 0,
      listen: (j['listen'] as num?)?.toInt() ?? 0,
      isFavoris: j['is_favoris'] == true,
      source: (j['source'] ?? '').toString(),
      platforms: (j['platforms'] is List ? j['platforms'] as List : const [])
          .where((p) => p != null)
          .map((p) => p.toString())
          .toList(),
      publishedAt: _parseDate(j['publication_date']),
    );
  }

  /// Parse la date de publication, tolérante aux deux formats de l'API :
  /// - objet PHP `\DateTime` sérialisé : `{date: "2024-06-17 10:00:00.000000", ...}`
  /// - chaîne ISO (source externe / Python).
  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    if (v is Map && v['date'] is String) return DateTime.tryParse(v['date'] as String);
    return null;
  }

  Track copyWith({bool? isFavoris, String? audioUrl}) => Track(
        id: id,
        apiId: apiId,
        title: title,
        artist: artist,
        coverUrl: coverUrl,
        pageUrl: pageUrl,
        duration: duration,
        audioUrl: audioUrl ?? this.audioUrl,
        likesCount: likesCount,
        listen: listen,
        isFavoris: isFavoris ?? this.isFavoris,
        source: source,
        platforms: platforms,
        publishedAt: publishedAt,
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Plateforme externe d'origine d'un titre (recherche YouTube Music / SoundCloud).
enum ExtPlatform { youtubeMusic, soundcloud, other }

extension TrackExtPlatform on Track {
  /// Déduit la plateforme externe depuis `source` ('ytm'/'sc') ou `platforms`.
  ExtPlatform get extPlatform {
    final s = source.toLowerCase();
    final p = platforms.map((e) => e.toLowerCase()).join(',');
    if (s == 'ytm' || s.contains('youtube') || p.contains('youtube')) {
      return ExtPlatform.youtubeMusic;
    }
    if (s == 'sc' || s.contains('soundcloud') || s.contains('sound') ||
        p.contains('soundcloud') || p.contains('sound')) {
      return ExtPlatform.soundcloud;
    }
    return ExtPlatform.other;
  }
}

/// Formate un compteur : 12400 → "12.4k", 1200000 → "1.2M". (Utilitaire pur.)
String formatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

/// Durée écoulée depuis [date] en français : "à l'instant", "il y a une minute",
/// "il y a 3 jours", "il y a 2 mois", "il y a un an"… (Utilitaire pur.)
String timeAgoFr(DateTime date) {
  final diff = DateTime.now().difference(date);
  // Date dans le futur ou quasi instantanée → "à l'instant"
  if (diff.inSeconds < 60) return "à l'instant";
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return m == 1 ? 'il y a une minute' : 'il y a $m minutes';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return h == 1 ? 'il y a une heure' : 'il y a $h heures';
  }
  if (diff.inDays < 30) {
    final d = diff.inDays;
    return d == 1 ? 'il y a un jour' : 'il y a $d jours';
  }
  if (diff.inDays < 365) {
    final months = (diff.inDays / 30).floor();
    return months <= 1 ? 'il y a un mois' : 'il y a $months mois';
  }
  final years = (diff.inDays / 365).floor();
  if (years < 10) return years <= 1 ? 'il y a un an' : 'il y a $years ans';
  final decades = (years / 10).floor();
  return decades <= 1 ? 'il y a une décennie' : 'il y a $decades décennies';
}

// ── Données de démonstration (utilisées seulement si DEMO=true) ───────────────

Track _demo(String id, String title, String artist, int min, int sec, int n) => Track(
      id: id,
      title: title,
      artist: artist,
      coverUrl: '',
      duration: Duration(minutes: min, seconds: sec),
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-$id.mp3',
      likesCount: n,
      listen: n * 4,
    );

final kDemoTracks = [
  _demo('1', 'Blinding Lights', 'The Weeknd', 3, 20, 12400),
  _demo('2', 'Levitating', 'Dua Lipa', 3, 23, 9800),
  _demo('3', 'Midnight City', 'M83', 4, 1, 12400),
  _demo('4', 'Stay', 'Kid LAROI', 2, 21, 7100),
  _demo('5', 'Good 4 U', 'Olivia Rodrigo', 2, 58, 5600),
];

final kDemoFeatured = _demo('6', 'After Dark', 'Mr.Kitty', 3, 47, 12400);

/// Artiste de démo (repli pour "Artistes recommandés").
class Artist {
  final String id;
  final String name;
  final String avatarUrl;
  const Artist({required this.id, required this.name, this.avatarUrl = ''});
}

final kDemoArtists = [
  const Artist(id: 'a1', name: 'The Weeknd'),
  const Artist(id: 'a2', name: 'Dua Lipa'),
  const Artist(id: 'a3', name: 'Billie E.'),
  const Artist(id: 'a4', name: 'Drake'),
  const Artist(id: 'a5', name: 'Beyoncé'),
];
