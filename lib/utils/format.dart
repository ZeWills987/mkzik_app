// Formatage de données pour l'affichage. Fonctions pures, sans dépendance à
// Flutter ni à l'API : un seul endroit pour les durées, compteurs et dates.

/// Durée en `m:ss` : 3 min 5 s → "3:05", 75 min → "75:00" (pas de format heures).
String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Formate un compteur : 12400 → "12.4k", 1200000 → "1.2M".
String formatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Date au format ISO `aaaa-mm-jj` (valeur envoyée à l'API).
String formatDateIso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Date au format français `jj/mm/aaaa` (affichage).
String formatDateFr(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// Durée écoulée depuis [date] en français : "à l'instant", "il y a une minute",
/// "il y a 3 jours", "il y a 2 mois", "il y a un an"…
String timeAgoFr(DateTime date) {
  final diff = DateTime.now().difference(date);
  // Date dans le futur ou quasi instantanée → "à l'instant"
  if (diff.inSeconds < 60) return "à l'instant";
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return m == 1 ? 'il y a une minute' : 'il y a $m minutes';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return h == 1 ? 'il y a une heure' : 'il y a $h heures';
  }
  if (diff.inDays < 30) {
    final d = diff.inDays;
    return d == 1 ? 'il y a un jour' : 'il y a $d jours';
  }
  if (diff.inDays < 365) {
    final months = (diff.inDays / 30).floor();
    return months <= 1 ? 'il y a un mois' : 'il y a $months mois';
  }
  final years = (diff.inDays / 365).floor();
  if (years < 10) return years <= 1 ? 'il y a un an' : 'il y a $years ans';
  final decades = (years / 10).floor();
  return decades <= 1 ? 'il y a une décennie' : 'il y a $decades décennies';
}
