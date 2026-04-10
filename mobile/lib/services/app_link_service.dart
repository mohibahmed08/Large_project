import 'dart:async';

class AppLinkService {
  AppLinkService._();

  static final StreamController<String> _taskOpenController =
      StreamController<String>.broadcast();
  static String? _pendingTaskId;

  static Stream<String> get taskOpens => _taskOpenController.stream;

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
}
