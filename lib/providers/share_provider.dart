import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lien partagé reçu alors que l'utilisateur n'est pas connecté — conservé
/// jusqu'à la connexion, puis consommé pour rouvrir l'écran d'identification
/// (cf. ShareIntentGate). `/stream` et `/download` exigeant un JWT, on ne
/// peut pas traiter un partage tant que personne n'est authentifié.
final pendingSharedUrlProvider = StateProvider<String?>((ref) => null);
