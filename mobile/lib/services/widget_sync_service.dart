import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/task_model.dart';

class WidgetSyncService {
  WidgetSyncService._();

  static const MethodChannel _channel =
      MethodChannel('com.calendarpp/widget_data');

  static Future<void> updateTasks(List<CalendarTask> tasks) async {
    if (!Platform.isIOS) return;

    final payload = tasks
        .where((task) => !task.isCompleted && task.startDate != null)
        .toList()
      ..sort((a, b) => a.startDate!.compareTo(b.startDate!));

    final upcoming = payload.take(3).map((task) {
      return <String, Object>{
        'id': task.id,
        'title': task.title.trim().isEmpty ? 'Untitled item' : task.title.trim(),
        'taskType': _taskType(task),
        'startTime': task.startDate!.millisecondsSinceEpoch.toDouble(),
        'isCompleted': task.isCompleted,
        'reminderEnabled': task.reminderEnabled,
        'reminderMinutesBefore': task.reminderMinutesBefore,
        if (task.location.trim().isNotEmpty) 'location': task.location.trim(),
        if (task.endDate != null)
          'endTime': task.endDate!.millisecondsSinceEpoch.toDouble(),
      };
    }).toList();

    try {
      if (kDebugMode) {
        debugPrint('[WidgetSync] updateTasks count=${upcoming.length}');
      }
      await _channel.invokeMethod<void>('updateWidgetData', {
        'tasks': upcoming,
      });
      if (kDebugMode) {
        debugPrint('[WidgetSync] updateTasks done');
      }
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint('[WidgetSync] updateWidgetData error: $error');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[WidgetSync] updateWidgetData fatal: $error');
      }
    }
  }

  static Future<void> clear() async {
    if (!Platform.isIOS) return;

    try {
      await _channel.invokeMethod<void>('clearWidgetData');
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint('[WidgetSync] clearWidgetData error: $error');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[WidgetSync] clearWidgetData fatal: $error');
      }
    }
  }

  static String _taskType(CalendarTask task) {
    switch (task.source.toLowerCase()) {
      case 'plan':
        return 'plan';
      case 'event':
        return 'event';
      case 'ical':
        return 'ical';
      case 'task':
      case 'manual':
      default:
        return 'task';
    }
  }
}
