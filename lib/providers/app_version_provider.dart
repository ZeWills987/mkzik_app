import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_version.dart';
import '../services/app_version_service.dart';

/// État du check de version : statut + lien store éventuel.
class AppVersionState {
  final UpdateStatus status;
  final String? storeUrl;
  const AppVersionState(this.status, {this.storeUrl});

  static const ok = AppVersionState(UpdateStatus.upToDate);
}

/// Compare la version installée (lue à l'exécution) à la version distante.
/// En cas d'échec réseau / route absente → `upToDate` (jamais bloquant par erreur).
final appVersionProvider = FutureProvider<AppVersionState>((ref) async {
  final info = await AppVersionService.fetch();
  if (info == null || info.latest.isEmpty) return AppVersionState.ok;

  final pkg = await PackageInfo.fromPlatform();
  final status = info.statusFor(pkg.version); // pkg.version = versionName (ex: "1.0.0")
  return AppVersionState(status, storeUrl: info.storeUrl);
});
