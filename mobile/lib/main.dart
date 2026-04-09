import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'screens/login_screen.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialise Firebase when native config is present.
    await Firebase.initializeApp();
    await PushNotificationService.init();
  } catch (error) {
    if (kDebugMode) {
      debugPrint('[Main] Firebase init skipped: $error');
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calendar++',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const LoginScreen(),
    );
  }
}
