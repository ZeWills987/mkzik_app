/// Résultat du check de version distant (`GET /api/app-version`).
enum UpdateStatus {
  upToDate, // version installée OK
  available, // une version plus récente existe (maj soft, dismissible)
  required_, // version installée < min_supported (maj bloquante)
}

/// Infos de version renvoyées par l'API : dernière version publiée, version
/// minimale supportée, et lien de mise à jour (store).
class AppVersionInfo {
  final String latest;
  final String minSupported;
  final String? storeUrl;

  const AppVersionInfo({required this.latest, required this.minSupported, this.storeUrl});

  factory AppVersionInfo.fromJson(Map<String, dynamic> j) => AppVersionInfo(
        latest: (j['latest'] ?? '').toString(),
        minSupported: (j['min_supported'] ?? j['minSupported'] ?? '').toString(),
        storeUrl: (j['store_url'] ?? j['storeUrl'])?.toString(),
      );

  /// Statut de [current] (version installée, ex: "1.0.0") vis-à-vis de ces infos.
  UpdateStatus statusFor(String current) {
    if (minSupported.isNotEmpty && compareVersions(current, minSupported) < 0) {
      return UpdateStatus.required_;
    }
    if (latest.isNotEmpty && compareVersions(current, latest) < 0) {
      return UpdateStatus.available;
    }
    return UpdateStatus.upToDate;
  }
}

/// Compare deux versions sémantiques "x.y.z" → négatif si a<b, 0 si égal, positif
/// si a>b. Tolérant aux longueurs différentes ("1.0" == "1.0.0") et aux segments
/// non numériques (ignorés → 0).
int compareVersions(String a, String b) {
  final pa = a.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
  final pb = b.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
