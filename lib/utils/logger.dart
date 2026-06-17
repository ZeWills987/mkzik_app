import 'package:flutter/foundation.dart';

/// Journalisation de debug Mkzik.
///
/// No-op en release : les traces (`debugPrint`) ne sont émises qu'en mode debug
/// (`kDebugMode`), pour ne pas polluer la sortie ni dégrader les perfs en prod.
void mkLog(String message) {
  if (kDebugMode) debugPrint(message);
}
