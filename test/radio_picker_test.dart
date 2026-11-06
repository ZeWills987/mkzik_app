import 'package:flutter_test/flutter_test.dart';
import 'package:mkzik_app/models/track.dart';
import 'package:mkzik_app/player/core/track_resolver.dart';
import 'package:mkzik_app/player/radio_picker.dart';

Track _ext(String id) => Track(
      id: id,
      title: 'Titre $id',
      artist: 'Artiste $id',
      coverUrl: '',
      duration: Duration.zero,
      audioUrl: '',
      source: 'ytm',
      pageUrl: 'https://yt/$id',
    );

void main() {
  final seed = _ext('seed');
  late List<Track> suggestions;
  late RadioPicker picker;

  setUp(() {
    suggestions = [];
    picker = RadioPicker(suggestions: (_) async => suggestions, resolver: TrackResolver());
  });

  List<String> ids(List<Track> l) => [for (final t in l) t.id];

  test('toAppend : écarte les titres déjà dans la liste et limite à 10', () async {
    suggestions = [seed, for (var i = 0; i < 15; i++) _ext('s$i')];
    final r = await picker.toAppend(seed, existing: [seed], isStale: () => false);
    expect(r.length, 10);
    expect(ids(r), isNot(contains('seed')));
  });

  test('toReplaceUpcoming : limite à 20, écarte le titre de départ', () async {
    suggestions = [seed, for (var i = 0; i < 30; i++) _ext('s$i')];
    final r = await picker.toReplaceUpcoming(seed, isStale: () => false);
    expect(r.length, 20);
    expect(ids(r), isNot(contains('seed')));
  });

  test('les titres externes restent tels quels (résolus à la lecture)', () async {
    suggestions = [_ext('a')];
    final r = await picker.toReplaceUpcoming(seed, isStale: () => false);
    expect(r.single.audioUrl, isEmpty);
    expect(r.single.needsStream, isTrue);
  });

  test('aucune suggestion → liste vide', () async {
    expect(await picker.toReplaceUpcoming(seed, isStale: () => false), isEmpty);
  });

  test("obsolète : rien n'est renvoyé", () async {
    suggestions = [_ext('a')];
    expect(await picker.toReplaceUpcoming(seed, isStale: () => true), isEmpty);
  });
}
