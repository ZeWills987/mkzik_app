import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Clé SharedPreferences : plein écran restauré au prochain lancement.
const kFullScreenPrefKey = 'window_fullscreen';

/// Contrôle du plein écran desktop (Windows/macOS/Linux). Absent sur mobile —
/// n'appeler ces méthodes que derrière un check de plateforme.
class WindowPrefs {
  static bool get supported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<bool> isFullScreen() => windowManager.isFullScreen();

  static Future<void> setFullScreen(bool value) async {
    // window_manager ne retire la barre de titre en plein écran que si le
    // style "hidden" a été activé AVANT setFullScreen (il lit title_bar_style_
    // au moment de l'appel) — sinon la fenêtre couvre l'écran mais garde sa
    // barre de titre. On la restaure à "normal" en sortant du plein écran.
    if (value) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kFullScreenPrefKey, value);
  }
}
