// Classification des erreurs de lecture. Fonctions pures : just_audio n'expose
// ni les en-têtes ni le corps de la réponse HTTP, on lit donc le texte de
// l'erreur (les plateformes le formatent différemment).

/// Le proxy `/stream` renvoie 404 + « Titre indisponible » quand la track est
/// réellement morte (supprimée, privée, géo-bloquée) et 502 pour un souci
/// transitoire. `sourceNotSupported` = format non supporté par WinRT → traité
/// comme indisponible (pas de nouvelle tentative, ça ne changera rien).
bool isTrackUnavailable(Object e) {
  final s = '$e';
  return s.contains('404') || s.contains('Titre indisponible') || s.contains('sourceNotSupported');
}

/// Code HTTP renvoyé par le proxy `/stream`, extrait du message d'erreur du
/// lecteur. Null si aucun code connu n'y figure.
int? httpStatusIn(Object e) {
  final m = RegExp(r'\b(404|409|429|502|503|504)\b').firstMatch('$e');
  return m == null ? null : int.parse(m.group(1)!);
}

/// Codes qui signalent une indisponibilité passagère (surcharge, anti-bot, passerelle).
const transientHttpStatuses = {429, 502, 503, 504};
