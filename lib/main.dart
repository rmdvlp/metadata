import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/fcm_background_handler.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/core/navigation/app_navigator.dart';
import 'package:metadata/repositories/bank_chat_repository.dart';
import 'package:metadata/screens/splash_screen.dart';
import 'package:metadata/themes/app_theme.dart';
import 'package:metadata/widgets/pending_sync_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  AppLoading.configure();

  // Bank Chat's store. Resolved here so every read of it is synchronous —
  // the entries are a handful of local records, and making the screen render
  // a loading state over them would be noise. Cheap: this is a single
  // platform-channel round trip before the first frame.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Metadata',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
      builder: (context, child) {
        return Stack(
          children: [
            EasyLoading.init()(context, child),
            const Align(
              alignment: Alignment.topCenter,
              child: PendingSyncBanner(),
            ),
          ],
        );
      },
    );
  }
}
