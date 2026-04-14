import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/app_bootstrap_screen.dart';
import 'screens/reset_password_screen.dart';
import 'services/app_link_service.dart';
import 'services/push_notification_service.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeService().load();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final AppLinks _appLinks = AppLinks();
  final ThemeService _themeService = ThemeService();
  StreamSubscription<Uri>? _linkSubscription;
  String? _initialResetToken;
  bool _initialLinkResolved = true;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeServices());
    unawaited(_resolveInitialLink());
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleIncomingLink,
      onError: (_) {},
    );
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize optional native services after the first frame can render.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      await PushNotificationService.init();
    } catch (error) {
      debugPrint('[Main] Firebase/push init failed: $error');
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _resolveInitialLink() async {
    try {
      final initialUri = await _appLinks.getInitialLink().timeout(
        const Duration(seconds: 2),
      );
      final initialTaskId = _extractTaskId(initialUri);
      if (initialTaskId != null) {
        AppLinkService.handleTaskId(initialTaskId);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _initialResetToken = _extractResetToken(initialUri);
        _initialLinkResolved = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _initialLinkResolved = true;
      });
    }
  }

  String? _extractResetToken(Uri? uri) {
    if (uri == null) {
      return null;
    }

    final token = uri.queryParameters['token']?.trim();
    if (token == null || token.isEmpty) {
      return null;
    }

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final segments = uri.pathSegments.map((segment) => segment.toLowerCase());
    final isResetLink =
        host == 'reset-password' ||
        host == 'resetpassword' ||
        path == '/reset-password' ||
        path == '/resetpassword' ||
        segments.contains('reset-password') ||
        segments.contains('resetpassword');

    return isResetLink ? token : null;
  }

  void _handleIncomingLink(Uri uri) {
    final taskId = _extractTaskId(uri);
    if (taskId != null) {
      AppLinkService.handleTaskId(taskId);
    }

    final token = _extractResetToken(uri);
    if (token == null || token.isEmpty) {
      return;
    }

    if (!_initialLinkResolved) {
      setState(() {
        _initialResetToken = token;
        _initialLinkResolved = true;
      });
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(
          token: token,
          onDone: () {
            navigator.pop();
          },
        ),
      ),
    );
  }

  String? _extractTaskId(Uri? uri) {
    if (uri == null) {
      return null;
    }

    final taskIdFromQuery = uri.queryParameters['taskId']?.trim();
    if (taskIdFromQuery != null && taskIdFromQuery.isNotEmpty) {
      return taskIdFromQuery;
    }

    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments;
    if (host == 'task' && segments.isNotEmpty) {
      final taskId = segments.first.trim();
      return taskId.isEmpty ? null : taskId;
    }

    if (segments.length >= 2 && segments.first.toLowerCase() == 'task') {
      final taskId = segments[1].trim();
      return taskId.isEmpty ? null : taskId;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeService,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Calendar++',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        builder: (context, child) => DecoratedBox(
          decoration: AppTheme.backgroundDecoration(),
          child: child ?? const SizedBox.shrink(),
        ),
        home: _initialLinkResolved
            ? AppBootstrapScreen(initialResetToken: _initialResetToken)
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}
