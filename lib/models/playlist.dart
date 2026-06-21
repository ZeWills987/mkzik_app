/// Modèle d'une playlist utilisateur (cf. `GET /api/playlist`).
/// L'API ne fournit que les métadonnées (id, titre, nombre de favoris) — il
/// n'existe pas de route pour le contenu détaillé d'une playlist.
class Playlist {
  final int id;
  final String title;
  final int nbFavoris; // nombre de titres dans la playlist

  const Playlist({required this.id, required this.title, this.nbFavoris = 0});

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        nbFavoris: (j['nb_favoris'] as num?)?.toInt() ?? 0,
      );

  String get countLabel => nbFavoris <= 1 ? '$nbFavoris titre' : '$nbFavoris titres';
}
