import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'session_storage.dart';

// ─── Background message handler (top-level, required by FCM) ────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Show a local notification when the app is in the background / terminated
  await PushNotificationService._showLocalNotification(message);
}

// ─── Android notification channel ───────────────────────────────────────────
const AndroidNotificationChannel _reminderChannel = AndroidNotificationChannel(
  'calendar_reminders',
  'Calendar Reminders',
  description: 'Reminders for upcoming Calendar++ events and tasks',
  importance: Importance.max,
  playSound: true,
);

class PushNotificationService {
  PushNotificationService._();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final StreamController<Map<String, dynamic>>
      _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  static bool _initialized = false;
  static bool _firebaseReady = false;

  static Stream<Map<String, dynamic>> get notificationOpens =>
      _notificationTapController.stream;

  // ── Initialise once at app startup ────────────────────────────────────────
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      Firebase.app();
      _firebaseReady = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Push] Firebase not configured: $e');
      }
      return;
    }

    // Register the background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // ── Local notification setup ─────────────────────────────────────────
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit     = DarwinInitializationSettings(
      requestAlertPermission: false, // we request separately below
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create Android channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_reminderChannel);

    // ── Foreground message handler ───────────────────────────────────────
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _emitNotificationPayload(message.data);
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _emitNotificationPayload(initialMessage.data);
    }

    // ── Token refresh handler ────────────────────────────────────────────
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _uploadDeviceToken(newToken);
    });
  }

  // ── Request permission explicitly (call after login) ──────────────────────
  static Future<bool> requestPermission() async {
    if (!_firebaseReady) {
      return false;
    }

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (granted) {
        await registerDeviceToken();
      }
      return granted;
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] requestPermission error: $e');
      return false;
    }
  }

  // ── Get current FCM token and upload to backend ───────────────────────────
  static Future<void> registerDeviceToken() async {
    if (!_firebaseReady) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _uploadDeviceToken(token);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] registerDeviceToken error: $e');
    }
  }

  // ── Upload token to backend ───────────────────────────────────────────────
  static Future<void> _uploadDeviceToken(String token) async {
    try {
      final jwtToken = await SessionStorage.readToken();
      if (jwtToken.isEmpty) return;

      final platform = Platform.isIOS ? 'ios' : 'android';

      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/registerdevicetoken'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({'deviceToken': token, 'platform': platform}),
      );

      if (kDebugMode) {
        debugPrint('[Push] Token upload: ${res.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] _uploadDeviceToken error: $e');
    }
  }

  // ── Show a local notification from a RemoteMessage ───────────────────────
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'calendar_reminders',
      'Calendar Reminders',
      channelDescription: 'Reminders for upcoming Calendar++ events and tasks',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(message.data),
    );
  }

  // ── Handle notification tap ───────────────────────────────────────────────
  static void _onNotificationTap(NotificationResponse response) {
    if (kDebugMode) debugPrint('[Push] Notification tapped: ${response.payload}');
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        _emitNotificationPayload(decoded);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] Notification payload decode error: $e');
    }
  }

  static void _emitNotificationPayload(Map<String, dynamic> data) {
    if (!_notificationTapController.isClosed) {
      _notificationTapController.add(Map<String, dynamic>.from(data));
    }
  }

  // ── Remove token on logout ────────────────────────────────────────────────
  static Future<void> removeDeviceToken() async {
    if (!_firebaseReady) {
      await SessionStorage.clear();
      return;
    }

    try {
      final jwtToken = await SessionStorage.readToken();
      if (jwtToken.isEmpty) return;

      await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/registerdevicetoken'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] removeDeviceToken error: $e');
    } finally {
      await SessionStorage.clear();
    }
  }
}
