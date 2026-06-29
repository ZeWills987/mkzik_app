import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'navigation/app_nav.dart';
import 'navigation/app_nav_impl.dart';
import 'screens/auth/auth_gate.dart';
import 'widgets/app_version_gate.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Injection de la navigation (découple widgets ↔ écrans)
  appNav = const AppNavImpl();

  // Charge les variables d'environnement (URLs API) depuis .env.
  // fileNotFound ignoré → on retombe sur les valeurs par défaut d'ApiConfig.
  await dotenv.load(fileName: '.env', isOptional: true);

  // Contrôles média lockscreen + notification (just_audio_background)
  await JustAudioBackground.init(
    androidNotificationChannelId: 'fr.mkzik.audio',
    androidNotificationChannelName: 'Lecture Mkzik',
    androidNotificationOngoing: true,
    androidNotificationIcon: 'mipmap/ic_launcher',
  );

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(
    const ProviderScope(child: MkzikApp()),
  );
}

class MkzikApp extends StatelessWidget {
  const MkzikApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mkzik',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppVersionGate(child: AuthGate()),
    );
  }
}
