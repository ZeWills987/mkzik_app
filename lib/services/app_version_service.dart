import '../config/api_config.dart';
import '../models/app_version.dart';
import 'api_client.dart';

/// Accès à la route de version d'app.
/// `GET api/app-version` → { latest, min_supported, store_url }
class AppVersionService {
  static Future<AppVersionInfo?> fetch() async {
    final res = await ApiClient.getUri(Uri.parse('${ApiConfig.baseUrl}api/app-version'), auth: false);
    final data = res.orElse(null);
    return data is Map<String, dynamic> ? AppVersionInfo.fromJson(data) : null;
  }
}
