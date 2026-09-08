import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/album.dart';
import '../services/album_service.dart';

/// Albums d'un utilisateur (GET api/albums?username=).
final albumsProvider = FutureProvider.family<List<Album>, String>((ref, username) async {
  return AlbumService.getByUsername(username);
});

/// Détail d'un album avec ses tracks (GET api/albums/{id}).
final albumDetailProvider = FutureProvider.family<Album?, int>((ref, id) async {
  return AlbumService.getById(id);
});
