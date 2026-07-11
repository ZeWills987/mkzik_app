import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track_source.dart';
import '../services/track_service.dart';

/// Sources (originaux) d'un track dérivé, chargées à la demande (par apiId).
/// Liste vide = original → pas de section "Sources".
final trackSourcesProvider =
    FutureProvider.family<List<TrackSource>, int>((ref, trackId) async {
  return TrackService.getSources(trackId);
});
