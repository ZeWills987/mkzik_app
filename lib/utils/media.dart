import '../config/api_config.dart';

/// Nettoie une URL d'image renvoyée par l'API avant affichage :
/// - placeholder "unknow.jpg" → '' (pas d'image → fallback dégradé)
/// - hôte localhost/127.0.0.1 (URLs stockées en dev) → réécrit vers la base API
/// - chemin relatif (uploads/…) → préfixé par la base API
/// - URL S3 sans clé d'objet (racine du bucket) → '' (invalide)
String mediaUrl(String raw) {
  if (raw.isEmpty) return '';

  final lower = raw.toLowerCase();
  if (lower.endsWith('unknow.jpg') || lower.endsWith('unknown.jpg') || lower.endsWith('default.jpg')) {
    return '';
  }

  var url = raw;
  final local = RegExp(r'^https?://(localhost|127\.0\.0\.1)(:\d+)?/');
  if (local.hasMatch(url)) {
    // Réécrit l'hôte local (stocké en dev) vers la vraie base API
    url = url.replaceFirst(local, ApiConfig.baseUrl);
  } else if (!url.startsWith('http')) {
    // Chemin relatif → préfixe base API
    url = '${ApiConfig.baseUrl}${url.startsWith('/') ? url.substring(1) : url}';
  }

  final uri = Uri.tryParse(url);
  if (uri != null && uri.host.contains('s3.') && (uri.path.isEmpty || uri.path == '/')) {
    return ''; // bucket S3 sans objet → invalide
  }
  return url;
}
