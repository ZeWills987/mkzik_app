class YtPlaylist {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final int? trackCount;

  const YtPlaylist({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.trackCount,
  });

  factory YtPlaylist.fromJson(Map<String, dynamic> j) => YtPlaylist(
        id: (j['id'] ?? j['playlist_id'] ?? '').toString(),
        title: (j['title'] ?? j['name'] ?? '').toString(),
        thumbnailUrl: j['thumbnail']?.toString() ?? j['thumbnails']?.toString(),
        trackCount: (j['track_count'] ?? j['item_count'] ?? j['count'] as num?)?.toInt(),
      );
}
