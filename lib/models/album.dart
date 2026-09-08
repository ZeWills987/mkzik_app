import 'track.dart';

class Album {
  final int id;
  final String title;
  final String description;
  final String coverUrl;
  final String releaseDate;
  final String status;
  final List<String> genres;
  final List<Track> tracks;
  final int trackCount;
  final String artistUsername;

  const Album({
    required this.id,
    required this.title,
    this.description = '',
    this.coverUrl = '',
    this.releaseDate = '',
    this.status = 'PUBLIC',
    this.genres = const [],
    this.tracks = const [],
    this.trackCount = 0,
    this.artistUsername = '',
  });

  bool get hasCover => coverUrl.isNotEmpty;

  int get displayTrackCount => tracks.isNotEmpty ? tracks.length : trackCount;

  String get countLabel {
    final n = displayTrackCount;
    return n <= 1 ? '$n titre' : '$n titres';
  }

  Duration get totalDuration => tracks.fold(
        Duration.zero,
        (sum, t) => sum + t.duration,
      );

  factory Album.fromJson(Map<String, dynamic> j) {
    final rawTracks = j['tracks'] is List ? j['tracks'] as List : const [];
    final uploaderRaw = j['uploader'];
    String username = '';
    if (uploaderRaw is List && uploaderRaw.isNotEmpty && uploaderRaw.first is Map) {
      username = (uploaderRaw.first as Map)['username']?.toString() ?? '';
    } else if (uploaderRaw is Map) {
      username = uploaderRaw['username']?.toString() ?? '';
    } else if (uploaderRaw is String) {
      username = uploaderRaw;
    }

    final rawGenres = j['genres'] is List ? j['genres'] as List : const [];

    return Album(
      id: (j['id'] as num?)?.toInt() ?? 0,
      title: (j['title'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      coverUrl: (j['cover_url'] ?? j['cover'] ?? '').toString(),
      releaseDate: (j['release_date'] ?? '').toString(),
      status: (j['status'] ?? 'PUBLIC').toString(),
      genres: rawGenres.map((g) => g.toString()).toList(),
      tracks: rawTracks
          .whereType<Map<String, dynamic>>()
          .map(Track.fromJson)
          .toList(),
      trackCount: (j['nb_tracks'] ?? j['track_count'] ?? rawTracks.length as num?)?.toInt() ?? rawTracks.length,
      artistUsername: username,
    );
  }
}
