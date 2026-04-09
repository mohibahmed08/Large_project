import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';

class SessionStorage {
  SessionStorage._();

  static const _jwtTokenKey = 'jwtToken';
  static const _biometricUnlockEnabledKey = 'biometricUnlockEnabled';
  static const _biometricLoginEnabledKey = 'biometricLoginEnabled';
  static const _liveActivityIdKey = 'liveActivityId';
  static const _liveActivityTaskIdKey = 'liveActivityTaskId';
  static const _weatherWidgetModeKey = 'weatherWidgetMode';

  static Future<void> saveSession(UserSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_jwtTokenKey, session.accessToken);
  }

  static Future<String> readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_jwtTokenKey) ?? '';
  }

  static Future<void> setBiometricUnlockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricUnlockEnabledKey, enabled);
  }

  static Future<bool> isBiometricUnlockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricUnlockEnabledKey) ?? false;
  }

  static Future<void> setBiometricLoginEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricLoginEnabledKey, enabled);
  }

  static Future<bool> isBiometricLoginEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricLoginEnabledKey) ?? false;
  }

  static Future<void> setWeatherWidgetMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_weatherWidgetModeKey, mode);
  }

  static Future<String> readWeatherWidgetMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_weatherWidgetModeKey) ?? 'future';
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_jwtTokenKey);
  }

  static Future<void> saveLiveActivity({
    required String activityId,
    required String taskId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_liveActivityIdKey, activityId);
    await prefs.setString(_liveActivityTaskIdKey, taskId);
  }

  static Future<({String? activityId, String? taskId})> readLiveActivity() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      activityId: prefs.getString(_liveActivityIdKey),
      taskId: prefs.getString(_liveActivityTaskIdKey),
    );
  }

  static Future<void> clearLiveActivity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_liveActivityIdKey);
    await prefs.remove(_liveActivityTaskIdKey);
  }
}
