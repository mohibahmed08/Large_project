import 'dart:async';

class AppLinkService {
  AppLinkService._();

  static final StreamController<String> _taskOpenController =
      StreamController<String>.broadcast();
  static final StreamController<String> _themeOpenController =
      StreamController<String>.broadcast();
  static String? _pendingTaskId;
  static String? _pendingThemeShareValue;

  static Stream<String> get taskOpens => _taskOpenController.stream;
  static Stream<String> get themeOpens => _themeOpenController.stream;

  static bool handleTaskId(String? taskId) {
    final normalized = taskId?.trim() ?? '';
    if (normalized.isEmpty) {
      return false;
    }

    _pendingTaskId = normalized;
    _taskOpenController.add(normalized);
    return true;
  }

  static String? takePendingTaskId() {
    final pending = _pendingTaskId;
    _pendingTaskId = null;
    return pending;
  }

  static void clearPendingTaskId(String taskId) {
    if (_pendingTaskId == taskId) {
      _pendingTaskId = null;
    }
  }

  static bool handleThemeShareValue(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return false;
    }

    _pendingThemeShareValue = normalized;
    _themeOpenController.add(normalized);
    return true;
  }

  static String? takePendingThemeShareValue() {
    final pending = _pendingThemeShareValue;
    _pendingThemeShareValue = null;
    return pending;
  }

  static void clearPendingThemeShareValue(String value) {
    if (_pendingThemeShareValue == value) {
      _pendingThemeShareValue = null;
    }
  }
}
