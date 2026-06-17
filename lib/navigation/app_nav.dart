import 'package:flutter/widgets.dart';
import '../models/track.dart';

/// Abstraction de navigation — découple les **widgets** des **écrans**.
///
/// Les widgets réutilisables (cards, lignes, mini-player) appellent
/// `appNav.openProfile(...)` sans importer les écrans → plus d'imports
/// circulaires widgets ↔ screens. L'implémentation concrète ([app_nav_impl])
/// est injectée au démarrage dans [appNav].
abstract interface class AppNav {
  Future<void> openProfile(BuildContext context, String username);
  Future<void> openTrack(BuildContext context, Track track);
  Future<void> openPlayer(BuildContext context);
}

/// Implémentation courante (initialisée dans `main()`).
late AppNav appNav;
