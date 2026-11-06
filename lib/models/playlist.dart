/// Modèle d'une playlist utilisateur (cf. `GET /api/playlists`).
/// L'API ne fournit que les métadonnées (id, titre, nombre de titres) — il
/// n'existe pas de route pour le contenu détaillé d'une playlist.
class Playlist {
  final int id;
  final String title;
  final int nbTracks;

  const Playlist({required this.id, required this.title, this.nbTracks = 0});

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        nbTracks: (j['nb_tracks'] as num?)?.toInt() ?? 0,
      );

  String get countLabel => nbTracks <= 1 ? '$nbTracks titre' : '$nbTracks titres';
}
