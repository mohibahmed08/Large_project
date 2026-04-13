import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter bridge for iOS 16.2+ Live Activities (Lock Screen + Dynamic Island).
///
/// Usage after a task is about to start:
/// ```dart
/// final id = await LiveActivityService.startActivity(
///   taskId:    task.id,
///   taskType:  task.type,        // 'task' | 'plan' | 'event' | 'ical'
///   title:     task.title,
///   startTime: task.startDate,
///   endTime:   task.endDate,
///   location:  task.location,
/// );
/// // Store `id` to update/end later.
/// ```
class LiveActivityService {
  LiveActivityService._();

  static const MethodChannel _channel =
      MethodChannel('com.calendarpp/live_activity');

  // ── Check if Live Activities are supported on this device ─────────────────
  static Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    try {
      final supported = await _channel.invokeMethod<bool>('isSupported');
      return supported ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[LiveActivity] isSupported error: $e');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveActivity] isSupported fatal: $e');
      return false;
    }
  }

  // ── Start a Live Activity for a task ──────────────────────────────────────
  /// Returns the native activity ID, or null on failure.
  static Future<String?> startActivity({
    required String taskId,
    required String taskType,
    required String title,
    required DateTime startTime,
    DateTime? endTime,
    String? description,
    String? location,
  }) async {
    if (!Platform.isIOS) return null;
    try {
      final id = await _channel.invokeMethod<String>('startActivity', {
        'taskId':    taskId,
        'taskType':  taskType,
        'title':     title,
        'startTime': startTime.millisecondsSinceEpoch.toDouble(),
        if (endTime != null) 'endTime': endTime.millisecondsSinceEpoch.toDouble(),
        ...?(description == null ? null : {'description': description}),
        ...?(location == null ? null : {'location': location}),
      });
      if (kDebugMode) debugPrint('[LiveActivity] started: $id');
      return id;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[LiveActivity] startActivity error: $e');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveActivity] startActivity fatal: $e');
      return null;
    }
  }

  // ── Update an active Live Activity ────────────────────────────────────────
  static Future<void> updateActivity({
    required String activityId,
    required String title,
    required DateTime startTime,
    DateTime? endTime,
    String? description,
    String? location,
    bool isCompleted = false,
  }) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('updateActivity', {
        'activityId':  activityId,
        'title':       title,
        'startTime':   startTime.millisecondsSinceEpoch.toDouble(),
        if (endTime != null) 'endTime': endTime.millisecondsSinceEpoch.toDouble(),
        ...?(description == null ? null : {'description': description}),
        ...?(location == null ? null : {'location': location}),
        'isCompleted': isCompleted,
      });
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[LiveActivity] updateActivity error: $e');
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveActivity] updateActivity fatal: $e');
    }
  }

  // ── End / dismiss a Live Activity ─────────────────────────────────────────
  static Future<void> endActivity(String activityId) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('endActivity', {
        'activityId': activityId,
      });
      if (kDebugMode) debugPrint('[LiveActivity] ended: $activityId');
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[LiveActivity] endActivity error: $e');
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveActivity] endActivity fatal: $e');
    }
  }

  static Future<void> endAllActivities() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('endAllActivities');
      if (kDebugMode) debugPrint('[LiveActivity] ended all activities');
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[LiveActivity] endAllActivities error: $e');
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveActivity] endAllActivities fatal: $e');
    }
  }
}
