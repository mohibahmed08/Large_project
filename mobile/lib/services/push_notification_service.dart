import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'platform_runtime.dart';
import 'session_storage.dart';

class _NotificationContent {
  const _NotificationContent({
    required this.title,
    required this.body,
    this.subtitle,
  });

  final String title;
  final String body;
  final String? subtitle;
}

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

class PushDebugSnapshot {
  const PushDebugSnapshot({
    required this.initialized,
    required this.initializationInFlight,
    required this.firebaseReady,
    required this.platform,
    required this.authorizationStatus,
    required this.nativeAuthorizationStatus,
    required this.nativeRegistrationState,
    required this.apnsTokenPresent,
    required this.apnsTokenPreview,
    required this.fcmTokenPresent,
    required this.fcmTokenPreview,
    required this.activeStep,
    required this.lastCompletedStep,
    required this.failingStep,
    required this.lastUploadStatusCode,
    required this.lastUploadPlatform,
    required this.lastUploadResponsePreview,
    required this.lastUploadError,
    required this.lastInitError,
    required this.recentEvents,
  });

  final bool initialized;
  final bool initializationInFlight;
  final bool firebaseReady;
  final String platform;
  final String authorizationStatus;
  final String nativeAuthorizationStatus;
  final String nativeRegistrationState;
  final bool apnsTokenPresent;
  final String apnsTokenPreview;
  final bool fcmTokenPresent;
  final String fcmTokenPreview;
  final String activeStep;
  final String lastCompletedStep;
  final String failingStep;
  final int? lastUploadStatusCode;
  final String? lastUploadPlatform;
  final String? lastUploadResponsePreview;
  final String? lastUploadError;
  final String? lastInitError;
  final List<String> recentEvents;
}

class PushNotificationService {
  PushNotificationService._();
  static const String _reminderTitle = 'Calendar++';
  static const Duration _messagingTimeout = Duration(seconds: 8);
  static const Duration _tokenRetryDelay = Duration(seconds: 2);
  static const int _maxTokenRegistrationAttempts = 3;
  static const MethodChannel _nativeDebugChannel = MethodChannel(
    'calendarplusplus/push_debug',
  );

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final StreamController<Map<String, dynamic>>
  _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  static bool _initialized = false;
  static bool _firebaseReady = false;
  static Future<void>? _initializationFuture;
  static String _activeStep = 'idle';
  static String _lastCompletedStep = 'none';
  static String _failingStep = 'none';
  static String _nativeAuthorizationStatus = 'unknown';
  static String _nativeRegistrationState = 'unknown';
  static int? _lastUploadStatusCode;
  static String? _lastUploadPlatform;
  static String? _lastUploadResponsePreview;
  static String? _lastUploadError;
  static String? _lastInitError;
  static final List<String> _recentEvents = <String>[];

  static Stream<Map<String, dynamic>> get notificationOpens =>
      _notificationTapController.stream;

  // ── Initialise once at app startup ────────────────────────────────────────
  static Future<void> init() async {
    if (_initialized) return;
    final inFlight = _initializationFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    _initializationFuture = _performInitialization();
    try {
      await _initializationFuture;
    } finally {
      _initializationFuture = null;
    }
  }

  static Future<void> _performInitialization() async {
    _log('init start');
    try {
      Firebase.app();
      _firebaseReady = true;
      _lastInitError = null;
      _completeStep('firebase/app');
    } catch (e) {
      _firebaseReady = false;
      _lastInitError = e.toString();
      _failStep('firebase/app', e);
      return;
    }

    // Register the background handler
    _startStep('firebase/onBackgroundMessage');
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    _completeStep('firebase/onBackgroundMessage');

    // ── Local notification setup ─────────────────────────────────────────
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    _startStep('localNotifications/initialize');
    await _withTimeout(
      _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: _onNotificationTap,
      ),
      'localNotifications.initialize',
    );
    _completeStep('localNotifications/initialize');

    _startStep('localNotifications/createAndroidChannel');
    final androidNotifications = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidNotifications != null) {
      await _withTimeout(
        androidNotifications.createNotificationChannel(_reminderChannel),
        'createNotificationChannel',
      );
    }
    _completeStep('localNotifications/createAndroidChannel');

    _startStep('firebase/onMessage.listen');
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _log('onMessage received title=${message.notification?.title ?? 'none'}');
      _showLocalNotification(message);
    });
    _completeStep('firebase/onMessage.listen');

    _startStep('firebase/onMessageOpenedApp.listen');
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _log('onMessageOpenedApp taskId=${message.data['taskId'] ?? 'none'}');
      _emitNotificationPayload(message.data);
    });
    _completeStep('firebase/onMessageOpenedApp.listen');

    RemoteMessage? initialMessage;
    try {
      _startStep('firebase/getInitialMessage');
      initialMessage = await _withTimeoutNullable(
        FirebaseMessaging.instance.getInitialMessage(),
        'getInitialMessage',
      );
      _completeStep('firebase/getInitialMessage');
      if (initialMessage != null) {
        _log(
          'initial message found taskId=${initialMessage.data['taskId'] ?? 'none'}',
        );
        _emitNotificationPayload(initialMessage.data);
      }
    } catch (e) {
      _lastInitError = 'getInitialMessage failed during init: $e';
      _failStep('firebase/getInitialMessage', e);
      _log(
        'continuing initialization after getInitialMessage failure so permission/token flow can proceed',
      );
    }

    _startStep('firebase/onTokenRefresh.listen');
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _log('onTokenRefresh token=${_tokenPreview(newToken)}');
      _uploadDeviceToken(newToken);
    });
    _completeStep('firebase/onTokenRefresh.listen');

    await _refreshNativeStatus(reason: 'init_complete');

    _initialized = true;
    _log('init complete');
  }

  // ── Request permission explicitly (call after login) ──────────────────────
  static Future<bool> requestPermission() async {
    _startStep('requestPermission/start');
    if (!_initialized) {
      await init();
    }

    if (!_firebaseReady) {
      _log('requestPermission skipped because Firebase is not ready');
      return false;
    }

    try {
      await _refreshNativeStatus(reason: 'before_requestPermission');
      _startStep('requestPermission/getNotificationSettings');
      final existingSettings = await _withTimeout(
        FirebaseMessaging.instance.getNotificationSettings(),
        'getNotificationSettings',
      );
      _completeStep('requestPermission/getNotificationSettings');
      _log(
        'existing authorization status=${existingSettings.authorizationStatus.name}',
      );

      if (existingSettings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          existingSettings.authorizationStatus ==
              AuthorizationStatus.provisional) {
        await _debugRegisterForRemoteNotifications(
          reason: 'already_authorized',
        );
        await registerDeviceToken();
        return true;
      }

      if (existingSettings.authorizationStatus == AuthorizationStatus.denied) {
        _completeStep('requestPermission/denied');
        return false;
      }

      _startStep('requestPermission/prompt');
      final settings = await _withTimeout(
        FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        ),
        'requestPermission',
      );
      _completeStep('requestPermission/prompt');
      _log('requestPermission result=${settings.authorizationStatus.name}');
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (granted) {
        await _debugRegisterForRemoteNotifications(
          reason: 'permission_granted',
        );
        await registerDeviceToken();
      }
      await _refreshNativeStatus(reason: 'after_requestPermission');
      return granted;
    } catch (e) {
      _failStep('requestPermission', e);
      return false;
    }
  }

  // ── Get current FCM token and upload to backend ───────────────────────────
  static Future<void> registerDeviceToken({int attempt = 1}) async {
    _startStep('registerDeviceToken/start');
    if (!_initialized) {
      await init();
    }

    if (!_firebaseReady) {
      _log('registerDeviceToken skipped because Firebase is not ready');
      return;
    }

    try {
      await _refreshNativeStatus(reason: 'before_registerDeviceToken');
      if (isNativeIOS) {
        await _debugRegisterForRemoteNotifications(
          reason: 'registerDeviceToken',
        );
        _startStep('registerDeviceToken/getAPNSToken');
        final apnsToken = await _withTimeoutNullable(
          FirebaseMessaging.instance.getAPNSToken(),
          'getAPNSToken',
        );
        _completeStep('registerDeviceToken/getAPNSToken');
        _log(
          'APNs token present=${apnsToken != null && apnsToken.isNotEmpty} token=${_tokenPreview(apnsToken)}',
        );
      }

      _startStep('registerDeviceToken/getFCMToken');
      final token = await _withTimeoutNullable(
        FirebaseMessaging.instance.getToken(),
        'getToken',
      );
      _completeStep('registerDeviceToken/getFCMToken');
      if (token != null && token.isNotEmpty) {
        await _uploadDeviceToken(token);
      } else {
        _log(
          'registerDeviceToken FCM token was null attempt=$attempt/$_maxTokenRegistrationAttempts',
        );
        if (attempt < _maxTokenRegistrationAttempts) {
          await Future<void>.delayed(_tokenRetryDelay);
          await registerDeviceToken(attempt: attempt + 1);
          return;
        }
        _lastUploadError = 'FCM token was null after $attempt attempts';
        _failStep(
          'registerDeviceToken/getFCMToken',
          'FCM token was null after $attempt attempts',
        );
      }
      await _refreshNativeStatus(reason: 'after_registerDeviceToken');
    } catch (e) {
      _lastUploadError = e.toString();
      _failStep('registerDeviceToken', e);
    }
  }

  // ── Upload token to backend ───────────────────────────────────────────────
  static Future<void> _uploadDeviceToken(String token) async {
    try {
      _startStep('uploadDeviceToken/readSession');
      final jwtToken = await SessionStorage.readToken();
      _completeStep('uploadDeviceToken/readSession');
      if (jwtToken.isEmpty) {
        _lastUploadError = 'Missing JWT token';
        _failStep('uploadDeviceToken/readSession', 'Missing JWT token');
        return;
      }

      final platform = deviceRegistrationPlatform;
      _log(
        'uploading device token platform=$platform token=${_tokenPreview(token)}',
      );

      _startStep('uploadDeviceToken/httpPost');
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/registerdevicetoken'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jwtToken',
            },
            body: jsonEncode({'deviceToken': token, 'platform': platform}),
          )
          .timeout(
            _messagingTimeout,
            onTimeout: () {
              throw TimeoutException('Timed out waiting for token upload');
            },
          );
      _completeStep('uploadDeviceToken/httpPost');
      _lastUploadStatusCode = res.statusCode;
      _lastUploadPlatform = platform;
      _lastUploadResponsePreview = _truncate(res.body);
      _log(
        'token upload response status=${res.statusCode} body=${_truncate(res.body)}',
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(
          'registerdevicetoken failed with status ${res.statusCode}',
        );
      }
      _lastUploadError = null;
    } catch (e) {
      _lastUploadError = e.toString();
      _failStep('uploadDeviceToken', e);
    }
  }

  static Future<PushDebugSnapshot> getDebugSnapshot() async {
    if (!_initialized) {
      try {
        await init().timeout(
          _messagingTimeout,
          onTimeout: () {
            throw TimeoutException('Timed out waiting for init()');
          },
        );
      } catch (e) {
        _lastInitError = 'Snapshot init error: $e';
        _failStep('getDebugSnapshot/init', e);
      }
    }

    AuthorizationStatus? authorizationStatus;
    String? apnsToken;
    String? fcmToken;

    if (_firebaseReady) {
      try {
        _startStep('snapshot/getNotificationSettings');
        final settings = await _withTimeout(
          FirebaseMessaging.instance.getNotificationSettings(),
          'getNotificationSettings',
        );
        authorizationStatus = settings.authorizationStatus;
        _completeStep('snapshot/getNotificationSettings');
      } catch (e) {
        _lastInitError = 'Notification settings error: $e';
        _failStep('snapshot/getNotificationSettings', e);
      }

      if (isNativeIOS) {
        try {
          _startStep('snapshot/getAPNSToken');
          apnsToken = await _withTimeoutNullable(
            FirebaseMessaging.instance.getAPNSToken(),
            'getAPNSToken',
          );
          _completeStep('snapshot/getAPNSToken');
        } catch (e) {
          _lastInitError = 'APNs token error: $e';
          _failStep('snapshot/getAPNSToken', e);
        }
      }

      try {
        _startStep('snapshot/getFCMToken');
        fcmToken = await _withTimeoutNullable(
          FirebaseMessaging.instance.getToken(),
          'getToken',
        );
        _completeStep('snapshot/getFCMToken');
      } catch (e) {
        _lastInitError = 'FCM token error: $e';
        _failStep('snapshot/getFCMToken', e);
      }
    }

    await _refreshNativeStatus(reason: 'getDebugSnapshot');

    return PushDebugSnapshot(
      initialized: _initialized,
      initializationInFlight: _initializationFuture != null,
      firebaseReady: _firebaseReady,
      platform: platformRuntimeLabel,
      authorizationStatus:
          authorizationStatus?.name ??
          (_firebaseReady ? 'unavailable' : 'firebase_not_ready'),
      nativeAuthorizationStatus: _nativeAuthorizationStatus,
      nativeRegistrationState: _nativeRegistrationState,
      apnsTokenPresent: apnsToken != null && apnsToken.isNotEmpty,
      apnsTokenPreview: _tokenPreview(apnsToken),
      fcmTokenPresent: fcmToken != null && fcmToken.isNotEmpty,
      fcmTokenPreview: _tokenPreview(fcmToken),
      activeStep: _activeStep,
      lastCompletedStep: _lastCompletedStep,
      failingStep: _failingStep,
      lastUploadStatusCode: _lastUploadStatusCode,
      lastUploadPlatform: _lastUploadPlatform,
      lastUploadResponsePreview: _lastUploadResponsePreview,
      lastUploadError: _lastUploadError,
      lastInitError: _lastInitError,
      recentEvents: List<String>.unmodifiable(_recentEvents),
    );
  }

  static String _tokenPreview(String? token) {
    if (token == null || token.isEmpty) {
      return 'none';
    }
    if (token.length <= 16) {
      return token;
    }
    return '${token.substring(0, 8)}...${token.substring(token.length - 8)}';
  }

  static String _truncate(String value, {int maxLength = 160}) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }

  static Future<T> _withTimeout<T>(Future<T> future, String label) {
    return future.timeout(
      _messagingTimeout,
      onTimeout: () {
        _failStep(label, TimeoutException('Timed out waiting for $label'));
        throw TimeoutException('Timed out waiting for $label');
      },
    );
  }

  static Future<T?> _withTimeoutNullable<T>(Future<T?> future, String label) {
    return future.timeout(
      _messagingTimeout,
      onTimeout: () {
        _failStep(label, TimeoutException('Timed out waiting for $label'));
        throw TimeoutException('Timed out waiting for $label');
      },
    );
  }

  static Future<void> _refreshNativeStatus({required String reason}) async {
    if (!isNativeIOS) {
      _nativeAuthorizationStatus = 'not_ios';
      _nativeRegistrationState = 'not_ios';
      return;
    }

    try {
      _startStep('nativeStatus/$reason');
      final result = await _withTimeoutNullable(
        _nativeDebugChannel.invokeMapMethod<String, dynamic>('getNativeStatus'),
        'native/getNativeStatus',
      );
      _completeStep('nativeStatus/$reason');
      final authorizationStatus =
          result?['authorizationStatus']?.toString() ?? 'unknown';
      final registered =
          result?['isRegisteredForRemoteNotifications']?.toString() ??
          'unknown';
      final alertSetting = result?['alertSetting']?.toString() ?? 'unknown';
      _nativeAuthorizationStatus = authorizationStatus;
      _nativeRegistrationState =
          'registered=$registered alert=$alertSetting bg=${result?['backgroundRefreshStatus'] ?? 'unknown'}';
      _log(
        'native status reason=$reason auth=$authorizationStatus registered=$registered alert=$alertSetting',
      );
    } catch (e) {
      _nativeAuthorizationStatus = 'error';
      _nativeRegistrationState = 'error';
      _lastInitError = 'Native status error: $e';
      _failStep('nativeStatus/$reason', e);
    }
  }

  static Future<void> _debugRegisterForRemoteNotifications({
    required String reason,
  }) async {
    if (!isNativeIOS) {
      return;
    }

    try {
      _startStep('nativeRegister/$reason');
      final result = await _withTimeoutNullable(
        _nativeDebugChannel.invokeMapMethod<String, dynamic>(
          'registerForRemoteNotifications',
        ),
        'native/registerForRemoteNotifications',
      );
      _completeStep('nativeRegister/$reason');
      _log(
        'native register requested reason=$reason result=${result?.toString() ?? 'null'}',
      );
    } catch (e) {
      _failStep('nativeRegister/$reason', e);
    }
  }

  static void _startStep(String step) {
    _activeStep = step;
    _log('START $step');
  }

  static void _completeStep(String step) {
    _activeStep = 'idle';
    _lastCompletedStep = step;
    _log('DONE $step');
  }

  static void _failStep(String step, Object error) {
    _activeStep = 'idle';
    _failingStep = '$step: $error';
    _lastInitError ??= error.toString();
    _log('FAIL $step: $error');
  }

  static void _log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final entry = '$timestamp $message';
    _recentEvents.insert(0, entry);
    if (_recentEvents.length > 12) {
      _recentEvents.removeRange(12, _recentEvents.length);
    }
    debugPrint('[Push] $entry');
  }

  // ── Show a local notification from a RemoteMessage ───────────────────────
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final content = _buildNotificationContent(message);
    if (content == null) return;
    final normalizedTaskId = _extractTaskId(message.data);
    final payload = <String, dynamic>{
      ...message.data,
      ...?((normalizedTaskId == null) ? null : {'taskId': normalizedTaskId}),
      'notificationTitle': content.title,
      'notificationBody': content.body,
      if (content.subtitle != null) 'notificationSubtitle': content.subtitle,
    };
    final bodyForExpansion = content.subtitle == null
        ? content.body
        : '${content.subtitle}\n${content.body}';

    final androidDetails = AndroidNotificationDetails(
      'calendar_reminders',
      'Calendar Reminders',
      channelDescription: 'Reminders for upcoming Calendar++ events and tasks',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.reminder,
      styleInformation: BigTextStyleInformation(bodyForExpansion),
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      subtitle: content.subtitle,
      interruptionLevel: InterruptionLevel.active,
      categoryIdentifier: 'calendar_reminder',
    );

    await _localNotifications.show(
      Object.hash(content.title, content.body, message.messageId),
      content.title,
      content.body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(payload),
    );
  }

  static _NotificationContent? _buildNotificationContent(
    RemoteMessage message,
  ) {
    final data = message.data;
    final notification = message.notification;
    final itemTitle = _firstNonEmptyString(<Object?>[
      data['taskTitle'],
      data['eventTitle'],
      data['title'],
      data['notificationTitle'],
      notification?.title,
    ]);
    final description = _firstNonEmptyString(<Object?>[
      data['description'],
      data['taskDescription'],
      data['body'],
      data['message'],
      notification?.body,
    ]);
    final location = _firstNonEmptyString(<Object?>[
      data['location'],
      data['taskLocation'],
      data['place'],
    ]);
    final reminderMinutes = _parseInt(data['reminderMinutesBefore']);
    final startDate = _parseDateTime(
      _firstNonEmptyString(<Object?>[
        data['startDate'],
        data['dueDate'],
        data['scheduledFor'],
        data['scheduledAt'],
      ]),
    );

    final cleanItemTitle = itemTitle ?? 'Upcoming item';
    final timingText = _buildTimingText(
      startDate: startDate,
      reminderMinutesBefore: reminderMinutes,
    );
    final body = _buildReminderBody(
      itemTitle: cleanItemTitle,
      startDate: startDate,
      reminderMinutesBefore: reminderMinutes,
    );
    final subtitle = _joinParts(<String?>[
      _buildScheduleLine(startDate),
      location,
    ], separator: '  •  ');

    return _NotificationContent(
      title: _reminderTitle,
      body: body,
      subtitle: subtitle ?? timingText ?? description,
    );
  }

  static String? _extractTaskId(Map<String, dynamic> data) {
    return _firstNonEmptyString(<Object?>[
      data['taskId'],
      data['taskID'],
      data['calendarTaskId'],
      data['eventId'],
      data['id'],
    ]);
  }

  static String? _buildTimingText({
    DateTime? startDate,
    int? reminderMinutesBefore,
  }) {
    if (startDate == null) {
      if (reminderMinutesBefore == null) {
        return null;
      }
      if (reminderMinutesBefore <= 0) {
        return 'Starting now';
      }
      if (reminderMinutesBefore == 60) {
        return 'Starts in 1 hour';
      }
      if (reminderMinutesBefore > 60 && reminderMinutesBefore % 60 == 0) {
        return 'Starts in ${reminderMinutesBefore ~/ 60} hours';
      }
      return 'Starts in $reminderMinutesBefore min';
    }

    final localStart = startDate.toLocal();
    final formattedDate = '${localStart.month}/${localStart.day}';
    final formattedTime = _formatTime(localStart);
    final now = DateTime.now();
    final isToday =
        localStart.year == now.year &&
        localStart.month == now.month &&
        localStart.day == now.day;
    final dayPrefix = isToday ? 'Today' : formattedDate;

    if (reminderMinutesBefore == null || reminderMinutesBefore <= 0) {
      return '$dayPrefix at $formattedTime';
    }
    return '$dayPrefix at $formattedTime';
  }

  static String _buildReminderBody({
    required String itemTitle,
    DateTime? startDate,
    int? reminderMinutesBefore,
  }) {
    final cleanTitle = itemTitle.trim().isEmpty
        ? 'Upcoming item'
        : itemTitle.trim();

    if (startDate != null) {
      final minutesUntilStart = startDate.difference(DateTime.now()).inMinutes;
      if (minutesUntilStart <= 1 ||
          (reminderMinutesBefore != null && reminderMinutesBefore <= 0)) {
        return '$cleanTitle is starting now';
      }
    }

    if (reminderMinutesBefore != null && reminderMinutesBefore > 0) {
      if (reminderMinutesBefore == 60) {
        return '$cleanTitle begins in 1 hour';
      }
      if (reminderMinutesBefore > 60 && reminderMinutesBefore % 60 == 0) {
        return '$cleanTitle begins in ${reminderMinutesBefore ~/ 60} hours';
      }
      return '$cleanTitle begins in $reminderMinutesBefore min';
    }

    if (startDate != null) {
      return '$cleanTitle\n${_buildScheduleLine(startDate) ?? _formatTime(startDate)}';
    }

    return cleanTitle;
  }

  static String? _buildScheduleLine(DateTime? startDate) {
    if (startDate == null) {
      return null;
    }

    final localStart = startDate.toLocal();
    final now = DateTime.now();
    final isToday =
        localStart.year == now.year &&
        localStart.month == now.month &&
        localStart.day == now.day;

    if (isToday) {
      return 'Today at ${_formatTime(localStart)}';
    }

    return '${localStart.month}/${localStart.day} at ${_formatTime(localStart)}';
  }

  static DateTime? _parseDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(value.trim())?.toLocal();
  }

  static int? _parseInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString().trim());
  }

  static String? _firstNonEmptyString(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  static String? _joinParts(List<String?> values, {String separator = ' '}) {
    final filtered = values
        .map((value) => value?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
    if (filtered.isEmpty) {
      return null;
    }
    return filtered.join(separator);
  }

  static String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  // ── Handle notification tap ───────────────────────────────────────────────
  static void _onNotificationTap(NotificationResponse response) {
    if (kDebugMode) {
      debugPrint('[Push] Notification tapped: ${response.payload}');
    }
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
      if (kDebugMode) {
        debugPrint('[Push] Notification payload decode error: $e');
      }
    }
  }

  static void _emitNotificationPayload(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    final taskId = _extractTaskId(normalized);
    if (taskId != null) {
      normalized['taskId'] = taskId;
    }
    if (!_notificationTapController.isClosed) {
      _notificationTapController.add(normalized);
    }
  }

  // ── Remove token on logout ────────────────────────────────────────────────
  static Future<void> removeDeviceToken() async {
    if (!_firebaseReady) {
      await SessionStorage.clearSession();
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
      await SessionStorage.clearSession();
    }
  }
}
