import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mkzik_app/models/track.dart';
import 'package:mkzik_app/screens/home/home_hero.dart';

Track _t(String id, String title, String artist, {int? apiId, int listen = 0, DateTime? at}) => Track(
      id: id,
      apiId: apiId,
      title: title,
      artist: artist,
      coverUrl: '',
      duration: const Duration(minutes: 3, seconds: 24),
      audioUrl: '',
      listen: listen,
      publishedAt: at,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, List<Track> tracks, {double width = 360}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HomeHero(tracks: tracks)))),
    ));
    // Les polices ne sont pas téléchargeables en test : on ignore cette erreur-là,
    // mais un débordement de mise en page doit faire échouer le test.
    final e = tester.takeException();
    expect(e?.toString() ?? '', isNot(contains('overflowed')));
  }

  testWidgets('hero : artiste, titre et chiffres affichés', (tester) async {
    await pump(tester, [
      _t('1', 'Nocturne', 'PNM', apiId: 14, listen: 184200, at: DateTime(2025, 3, 1)),
      _t('2', 'Ciel bas', 'RYVS', apiId: 13),
      _t('3', 'Vénus', 'Likuella', apiId: 12),
    ]);
    expect(find.text('PNM'), findsOneWidget);
    expect(find.text('signe « Nocturne »'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('184.2k'), findsOneWidget);
    expect(find.text('MKZ-014'), findsOneWidget);
  });

  testWidgets('hero : un seul titre, nom d\'artiste très long, écran étroit', (tester) async {
    await pump(tester, [_t('1', 'Un titre avec un nom vraiment très très long pour tester', 'Twistone Vibration Orchestra Collective')], width: 320);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Twistone'), findsWidgets);
  });

  testWidgets('hero : sans artiste, le titre prend la place du nom', (tester) async {
    await pump(tester, [_t('1', 'Sans artiste', '')]);
    expect(find.text('Sans artiste'), findsWidgets);
    expect(find.textContaining('signe'), findsNothing);
  });
}
