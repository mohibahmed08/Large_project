import 'dart:convert';
import 'dart:async';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/task_model.dart';
import '../models/user_model.dart';
import '../services/ai_service.dart';
import '../services/app_link_service.dart';
import '../services/calendar_service.dart';
import '../services/live_activity_service.dart';
import '../services/push_notification_service.dart';
import '../services/session_storage.dart';
import '../services/widget_sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/day_grid.dart';
import 'ai_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'task_editor_screen.dart';

enum _WeatherWidgetMode { future, futureAndHourly, hourly }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.initialSession});

  final UserSession initialSession;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const Duration _liveActivityFutureWindow = Duration(hours: 4);
  static const Duration _liveActivityMinimumUpcomingWindow = Duration(
    minutes: 10,
  );

  final AiService _aiService = AiService();
  final CalendarService _calendarService = CalendarService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _quickTaskController = TextEditingController();
  final TextEditingController _quickAddController = TextEditingController();
  final PageController _monthPageController = PageController(initialPage: 1200);

  late UserSession _session;
  Timer? _liveActivityTimer;
  StreamSubscription<String>? _appLinkTaskSubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationOpenSubscription;
  String? _liveActivityId;
  String? _liveActivityTaskId;
  bool _liveActivitySupported = false;
  bool _liveActivityReady = false;
  DateTime _currentDate = DateTime.now();
  DateTime _displayMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  Map<String, dynamic>? _weatherData;
  String? _weatherLocationName;
  List<CalendarTask> _tasks = [];
  List<CalendarTask> _visibleTasks = [];
  bool _isLoading = true;
  bool _iosSideEffectsStarted = false;
  int _selectedIndex = 0; // 0=Calendar, 1=Day, 2=AI
  _WeatherWidgetMode _weatherWidgetMode = _WeatherWidgetMode.future;
  final Set<String> _expandedDayTaskIds = <String>{};

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[CalendarStartup] $message');
    }
  }

  List<String> get _existingGroups {
    final counts = <String, int>{};
    for (final task in _tasks) {
      final group = task.group.trim();
      if (group.isEmpty) continue;
      counts.update(group, (value) => value + 1, ifAbsent: () => 1);
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((entry) => entry.key).toList();
  }

  String get _defaultGroupForNewTask =>
      _existingGroups.isNotEmpty ? _existingGroups.first : '';

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _debugLog('initState start');
    unawaited(SessionStorage.saveSession(_session));
    _notificationOpenSubscription = PushNotificationService.notificationOpens
        .listen((data) {
          unawaited(_handleNotificationOpen(data));
        });
    _appLinkTaskSubscription = AppLinkService.taskOpens.listen((taskId) {
      unawaited(_openTaskById(taskId));
    });
    _loadMonth(showLoader: true);
    _fetchWeather();
    unawaited(_restoreWeatherWidgetMode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingTaskId = AppLinkService.takePendingTaskId();
      if (pendingTaskId != null) {
        unawaited(_openTaskById(pendingTaskId));
      }
    });
  }

  @override
  void dispose() {
    _liveActivityTimer?.cancel();
    _appLinkTaskSubscription?.cancel();
    _notificationOpenSubscription?.cancel();
    _searchController.dispose();
    _quickTaskController.dispose();
    _quickAddController.dispose();
    _monthPageController.dispose();
    super.dispose();
  }

  Future<void> _handleNotificationOpen(Map<String, dynamic> data) async {
    final taskId = data['taskId']?.toString() ?? '';
    if (taskId.isEmpty) {
      return;
    }

    await _openTaskById(taskId, openedFromNotification: true);
  }

  Future<void> _openTaskById(
    String taskId, {
    bool openedFromNotification = false,
  }) async {
    AppLinkService.clearPendingTaskId(taskId);
    CalendarTask? task = _taskById(taskId);
    if (task == null) {
      await _loadMonth(showLoader: false);
      task = _taskById(taskId);
    }

    if (!mounted || task == null) {
      return;
    }

    if (task.startDate != null) {
      final selectedDay = DateUtils.dateOnly(task.startDate!);
      setState(() {
        _selectedDate = selectedDay;
        _currentDate = DateTime(selectedDay.year, selectedDay.month, 1);
        _selectedIndex = 1;
      });

      final now = DateTime.now();
      final monthOffset =
          (selectedDay.year - now.year) * 12 + (selectedDay.month - now.month);
      _monthPageController.jumpToPage(1200 + monthOffset);
    } else {
      setState(() {
        _selectedIndex = 1;
      });
    }
    final resolvedTask = task;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        _showTaskDetailsSheet(
          resolvedTask,
          openedFromNotification: openedFromNotification,
        ),
      );
    });
  }

  Future<void> _initializeLiveActivityState() async {
    _debugLog('live activity init start');
    try {
      _liveActivitySupported = await LiveActivityService.isSupported();
    } catch (_) {
      _liveActivitySupported = false;
    }

    final saved = await SessionStorage.readLiveActivity();
    _liveActivityId = saved.activityId;
    _liveActivityTaskId = saved.taskId;
    _liveActivityReady = true;
    _debugLog(
      'live activity init ready supported=$_liveActivitySupported restored=${_liveActivityId != null && _liveActivityTaskId != null}',
    );
    await _syncLiveActivitySafely();
  }

  Future<void> _startIosSideEffectsIfNeeded() async {
    if (_iosSideEffectsStarted) {
      return;
    }
    _iosSideEffectsStarted = true;
    _debugLog('starting deferred iOS side effects');

    unawaited(PushNotificationService.requestPermission());
    unawaited(_initializeLiveActivityState());
    _liveActivityTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_syncLiveActivitySafely()),
    );
  }

  Future<void> _syncLiveActivitySafely() async {
    try {
      _debugLog('live activity sync start');
      await _syncLiveActivity();
      _debugLog('live activity sync done');
    } catch (_) {
      _debugLog('live activity sync failed and was cleared');
      _liveActivityId = null;
      _liveActivityTaskId = null;
      await SessionStorage.clearLiveActivity();
    }
  }

  String _liveActivityTaskType(CalendarTask task) {
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

  DateTime _effectiveEndDate(CalendarTask task) {
    return task.endDate ??
        task.startDate?.add(const Duration(hours: 1)) ??
        DateTime.now();
  }

  Duration _liveActivityUpcomingWindowForTask(CalendarTask task) {
    final reminderWindow =
        task.reminderEnabled && task.reminderMinutesBefore > 0
        ? Duration(minutes: task.reminderMinutesBefore)
        : Duration.zero;

    return reminderWindow > _liveActivityMinimumUpcomingWindow
        ? reminderWindow
        : _liveActivityMinimumUpcomingWindow;
  }

  String? _liveActivityDescriptionPreview(CalendarTask task) {
    final trimmed = task.description.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length <= 90) {
      return trimmed;
    }
    return '${trimmed.substring(0, 87).trimRight()}...';
  }

  CalendarTask? _liveActivityCandidate() {
    final now = DateTime.now();
    final candidates =
        _tasks.where((task) {
          if (task.isCompleted || task.startDate == null) {
            return false;
          }

          final start = task.startDate!;
          final end = _effectiveEndDate(task);
          final isOngoing = !now.isBefore(start) && !now.isAfter(end);
          final isFuture =
              start.isAfter(now) &&
              start.difference(now) <= _liveActivityFutureWindow;
          final isUpcoming =
              start.isAfter(now) &&
              start.difference(now) <= _liveActivityUpcomingWindowForTask(task);

          return isOngoing || isUpcoming || isFuture;
        }).toList()..sort((a, b) {
          final aStart = a.startDate!;
          final bStart = b.startDate!;
          final aOngoing =
              !now.isBefore(aStart) && !now.isAfter(_effectiveEndDate(a));
          final bOngoing =
              !now.isBefore(bStart) && !now.isAfter(_effectiveEndDate(b));

          if (aOngoing != bOngoing) {
            return aOngoing ? -1 : 1;
          }

          return aStart.compareTo(bStart);
        });

    return candidates.isEmpty ? null : candidates.first;
  }

  CalendarTask? _taskById(String taskId) {
    for (final task in _tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  Future<void> _showTaskDetailsSheet(
    CalendarTask task, {
    bool openedFromNotification = false,
  }) async {
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        final accentColor = _taskDisplayColor(task);
        final fullDescription = task.description.trim();
        final location = task.location.trim();
        final showReminderBadge =
            task.reminderEnabled && task.reminderDelivery != 'email';

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              20 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (openedFromNotification)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Text(
                        'Opened from reminder',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (openedFromNotification) const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title.trim().isEmpty
                                  ? 'Untitled item'
                                  : task.title.trim(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _taskDateTimeSummary(task),
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (fullDescription.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      fullDescription,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _buildTaskMetaRow(
                      icon: Icons.place_outlined,
                      label: location,
                    ),
                  ],
                  const SizedBox(height: 14),
                  _buildTaskMetaRow(
                    icon: Icons.category_outlined,
                    label: _taskSourceLabel(task.source),
                  ),
                  if (task.group.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildTaskMetaRow(
                      icon: Icons.folder_outlined,
                      label: task.group.trim(),
                    ),
                  ],
                  if (showReminderBadge) ...[
                    const SizedBox(height: 10),
                    _buildTaskMetaRow(
                      icon: Icons.notifications_active_outlined,
                      label: _reminderSummary(task),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _openTaskDialog(task: task);
                          },
                          child: const Text('Edit'),
                        ),
                      ),
                      if (task.source.toLowerCase() == 'task') ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _toggleTask(task, !task.isCompleted);
                            },
                            child: Text(
                              task.isCompleted ? 'Mark Active' : 'Complete',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTaskMetaRow({
    required IconData icon,
    required String label,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.72)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  String _taskDateTimeSummary(CalendarTask task) {
    if (task.startDate == null) {
      return 'No scheduled time';
    }

    final start = task.startDate!;
    final dateText = '${start.month}/${start.day}/${start.year}';
    if (_isAllDayTask(task)) {
      return '$dateText • All day';
    }
    if (task.endDate != null) {
      return '$dateText • ${_formatTime(start)} - ${_formatTime(task.endDate!)}';
    }
    return '$dateText • ${_formatTime(start)}';
  }

  String _taskSourceLabel(String source) {
    switch (source.toLowerCase()) {
      case 'plan':
        return 'Plan';
      case 'event':
        return 'Event';
      case 'ical':
        return 'Imported calendar';
      case 'task':
        return 'Task';
      case 'manual':
      default:
        return 'Manual item';
    }
  }

  String _reminderSummary(CalendarTask task) {
    final timingLabel = switch (task.reminderMinutesBefore) {
      0 => 'At time of event',
      60 => '1 hour before',
      1440 => '1 day before',
      final minutes when minutes > 60 && minutes % 60 == 0 =>
        '${minutes ~/ 60} hours before',
      final minutes => '$minutes minutes before',
    };

    final deliveryLabel = switch (task.reminderDelivery) {
      'both' => 'email and push',
      'push' => 'push',
      _ => 'email',
    };

    return '$timingLabel via $deliveryLabel';
  }

  Future<void> _syncLiveActivity() async {
    if (!_liveActivityReady || !_liveActivitySupported) {
      return;
    }

    final candidate = _liveActivityCandidate();

    if (candidate == null) {
      if (_liveActivityId != null) {
        await LiveActivityService.endActivity(_liveActivityId!);
        _liveActivityId = null;
        _liveActivityTaskId = null;
        await SessionStorage.clearLiveActivity();
      }
      return;
    }

    final candidateStart = candidate.startDate!;
    final candidateEnd = candidate.endDate;
    final candidateLocation = candidate.location.trim().isEmpty
        ? null
        : candidate.location.trim();
    final candidateDescription = _liveActivityDescriptionPreview(candidate);
    final candidateTitle = candidate.title.trim().isEmpty
        ? 'Untitled item'
        : candidate.title.trim();

    if (_liveActivityId != null && _liveActivityTaskId == candidate.id) {
      await LiveActivityService.updateActivity(
        activityId: _liveActivityId!,
        title: candidateTitle,
        startTime: candidateStart,
        endTime: candidateEnd,
        description: candidateDescription,
        location: candidateLocation,
        isCompleted: candidate.isCompleted,
      );
      return;
    }

    if (_liveActivityId != null) {
      await LiveActivityService.endActivity(_liveActivityId!);
      _liveActivityId = null;
      _liveActivityTaskId = null;
      await SessionStorage.clearLiveActivity();
    }

    final activityId = await LiveActivityService.startActivity(
      taskId: candidate.id,
      taskType: _liveActivityTaskType(candidate),
      title: candidateTitle,
      startTime: candidateStart,
      endTime: candidateEnd,
      description: candidateDescription,
      location: candidateLocation,
    );

    if (activityId == null) {
      return;
    }

    _liveActivityId = activityId;
    _liveActivityTaskId = candidate.id;
    await SessionStorage.saveLiveActivity(
      activityId: activityId,
      taskId: candidate.id,
    );
  }

  void _cacheSession(UserSession session) {
    _session = session;
    unawaited(SessionStorage.saveSession(session));
  }

  Future<void> _restoreWeatherWidgetMode() async {
    final savedMode = await SessionStorage.readWeatherWidgetMode();
    if (!mounted) {
      return;
    }

    setState(() {
      _weatherWidgetMode = switch (savedMode) {
        'futureAndHourly' => _WeatherWidgetMode.futureAndHourly,
        'hourly' => _WeatherWidgetMode.hourly,
        _ => _WeatherWidgetMode.future,
      };
    });
  }

  Future<void> _setWeatherWidgetMode(_WeatherWidgetMode mode) async {
    if (_weatherWidgetMode == mode) {
      return;
    }

    setState(() {
      _weatherWidgetMode = mode;
    });

    await SessionStorage.setWeatherWidgetMode(switch (mode) {
      _WeatherWidgetMode.future => 'future',
      _WeatherWidgetMode.futureAndHourly => 'futureAndHourly',
      _WeatherWidgetMode.hourly => 'hourly',
    });
  }

  Future<void> _loadMonth({bool showLoader = false}) async {
    _debugLog('loadMonth start showLoader=$showLoader month=${_currentDate.year}-${_currentDate.month}');
    if (showLoader) {
      setState(() {
        _isLoading = true;
      });
    }

    final range = _monthRange(_currentDate);
    try {
      final result = await _calendarService.loadCalendar(
        session: _session,
        startDate: range.$1,
        endDate: range.$2,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _cacheSession(result.session);
        _tasks = result.tasks;
        _visibleTasks = result.tasks;
      });
      _debugLog('loadMonth success tasks=${result.tasks.length}');
      unawaited(_startIosSideEffectsIfNeeded());
      if (_iosSideEffectsStarted) {
        unawaited(_syncLiveActivitySafely());
      }
    } catch (error) {
      _debugLog('loadMonth error $error');
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && showLoader) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _setDisplayedMonth(
    DateTime month, {
    bool animatePage = false,
    DateTime? selectedDateOverride,
  }) async {
    final normalizedMonth = DateTime(month.year, month.month);
    final daysInMonth = DateTime(
      normalizedMonth.year,
      normalizedMonth.month + 1,
      0,
    ).day;
    final baseSelectedDate = selectedDateOverride ?? _selectedDate;
    final nextSelectedDay = baseSelectedDate.day > daysInMonth
        ? daysInMonth
        : baseSelectedDate.day;
    final nextSelectedDate = DateUtils.dateOnly(
      DateTime(normalizedMonth.year, normalizedMonth.month, nextSelectedDay),
    );
    if (_displayMonth.year == normalizedMonth.year &&
        _displayMonth.month == normalizedMonth.month &&
        _currentDate.year == normalizedMonth.year &&
        _currentDate.month == normalizedMonth.month &&
        DateUtils.isSameDay(_selectedDate, nextSelectedDate)) {
      return;
    }
    final today = DateTime.now();
    final monthOffset =
        (normalizedMonth.year - today.year) * 12 +
        (normalizedMonth.month - today.month);

    setState(() {
      _displayMonth = normalizedMonth;
      _currentDate = normalizedMonth;
      _selectedDate = nextSelectedDate;
      _expandedDayTaskIds.clear();
    });

    if (animatePage && _monthPageController.hasClients) {
      await _monthPageController.animateToPage(
        1200 + monthOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }

    await _loadMonth(showLoader: false);
  }

  Future<Map<String, dynamic>?> _loadWeatherForecast({
    required double latitude,
    required double longitude,
  }) async {
    final today = DateTime.now();
    final start = _formatDate(today);
    final end = _formatDate(today.add(const Duration(days: 10)));
    final response = await http.get(
      Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude&start_date=$start&end_date=$end&hourly=temperature_2m,weathercode&daily=weathercode,temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit',
      ),
    );

    if (response.statusCode != 200) {
      return null;
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _fetchWeather() async {
    _debugLog('weather fetch start');
    const fallbackLatitude = 28.5383;
    const fallbackLongitude = -81.3792;

    try {
      final fallbackForecast = await _loadWeatherForecast(
        latitude: fallbackLatitude,
        longitude: fallbackLongitude,
      );
      if (mounted && fallbackForecast != null) {
        setState(() {
          _weatherData = fallbackForecast;
          _weatherLocationName = 'Orlando, Florida';
        });
        _debugLog('weather fallback loaded');
      }
    } catch (_) {
      // Keep going and still try device-location weather below.
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final localForecast = await _loadWeatherForecast(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted || localForecast == null) {
        return;
      }

      setState(() {
        _weatherData = localForecast;
        _weatherLocationName = 'Current location';
      });
      _debugLog('weather current location loaded');
    } catch (_) {
      // Keep the fallback weather if location lookup fails.
    }
  }

  Future<void> _openTaskDialog({
    CalendarTask? task,
    String? newTaskSource,
    String? initialGroup,
    String? initialTitle,
    DateTime? initialDate,
  }) async {
    final baseDate = task?.startDate ?? initialDate ?? _selectedDate;
    final initialEndDate =
        task?.endDate ??
        (task?.startDate ?? initialDate ?? _selectedDate).add(
          const Duration(hours: 1),
        );

    final result = await Navigator.push<TaskEditorResult>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskEditorScreen(
          initialTitle: task?.title ?? initialTitle ?? '',
          initialDescription: task?.description ?? '',
          initialLocation: task?.location ?? '',
          initialColor: task?.color ?? '',
          initialGroup: task?.group ?? initialGroup ?? _defaultGroupForNewTask,
          existingGroups: _existingGroups,
          initialStartDate: baseDate,
          initialEndDate: initialEndDate,
          initialReminderEnabled: task?.reminderEnabled ?? false,
          initialReminderMinutesBefore: task?.reminderMinutesBefore ?? 30,
          initialReminderDelivery: task?.reminderDelivery ?? 'email',
          isEditing: task != null,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    if (result.action == TaskEditorAction.delete) {
      if (task == null || task.id.trim().isEmpty) {
        _showSnackBar('This item cannot be deleted yet.');
        return;
      }
      await _deleteTask(task);
      return;
    }

    if (result.title.isEmpty) {
      return;
    }

    try {
      final nextSession = await _calendarService.saveTask(
        session: _session,
        taskId: task?.id,
        title: result.title,
        description: result.description,
        startDate: result.startDate,
        endDate: result.endDate,
        location: result.location,
        source: task?.source ?? newTaskSource ?? 'manual',
        color: result.color,
        group: result.group,
        isCompleted: task?.isCompleted ?? false,
        reminderEnabled: result.reminderEnabled,
        reminderMinutesBefore: result.reminderMinutesBefore,
        reminderDelivery: result.reminderDelivery,
      );
      _cacheSession(nextSession);

      await _loadMonth();
      if (!mounted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _showSnackBar(task == null ? 'Task added.' : 'Task updated.');
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _deleteTask(CalendarTask task) async {
    if (task.id.trim().isEmpty) {
      _showSnackBar('This item cannot be deleted yet.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(task.source.toLowerCase() == 'task' ? 'Delete task?' : 'Delete item?'),
        content: Text(
          'This will permanently delete "${task.title.trim().isEmpty ? 'this item' : task.title.trim()}" from your calendar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final nextSession = await _calendarService.deleteTask(
        session: _session,
        taskId: task.id,
      );
      _cacheSession(nextSession);
      await _loadMonth();
      if (!mounted) {
        return;
      }
      _showSnackBar(
        task.source.toLowerCase() == 'task' ? 'Task deleted.' : 'Item deleted.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _saveQuickAddFallback(String title) async {
    final nextSession = await _calendarService.saveTask(
      session: _session,
      title: title,
      startDate: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ),
      source: 'manual',
    );
    _cacheSession(nextSession);
    await _loadMonth();
  }

  Future<void> _submitQuickAdd(String rawValue) async {
    final value = rawValue.trim();
    if (value.isEmpty) {
      return;
    }

    _quickAddController.clear();

    final selectedDateIso = _formatDate(_selectedDate);
    try {
      final result = await _aiService.chat(
        session: _session,
        messages: [
          {
            'role': 'user',
            'content':
                'Create exactly one calendar task for $selectedDateIso from this quick-add text: "$value". '
                'Infer a local time only if the user implied one. '
                'If no time is implied, make it an untimed or all-day task on that date. '
                'Do not ask follow-up questions.',
          },
        ],
      );
      _cacheSession(result.session);

      if (result.calendarChanged) {
        await _loadMonth();
        if (!mounted) {
          return;
        }
        _showSnackBar('Added to your calendar.');
        return;
      }
    } catch (_) {
      // Fall through to the local quick-add fallback below.
    }

    try {
      await _saveQuickAddFallback(value);
      if (!mounted) {
        return;
      }
      _showSnackBar('Saved as an all-day task.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _toggleTask(CalendarTask task, bool value) async {
    try {
      final nextSession = await _calendarService.saveTask(
        session: _session,
        taskId: task.id,
        title: task.title,
        description: task.description,
        startDate: task.startDate,
        endDate: task.endDate,
        location: task.location,
        source: task.source,
        color: task.color,
        group: task.group,
        isCompleted: value,
        reminderEnabled: task.reminderEnabled,
        reminderMinutesBefore: task.reminderMinutesBefore,
        reminderDelivery: task.reminderDelivery,
      );
      _cacheSession(nextSession);
      await _loadMonth();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openImportDialog() async {
    final urlController = TextEditingController();
    final contentController = TextEditingController();

    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect calendar'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _pickAndImportCalendarFile();
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Choose .ics or .zip file'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'ICS URL (https://...)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'Or paste ICS content',
                ),
                minLines: 4,
                maxLines: 8,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              urlController.text.trim(),
              contentController.text.trim(),
            )),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    urlController.dispose();
    contentController.dispose();

    if (result == null) {
      return;
    }
    if (result.$1.isEmpty && result.$2.isEmpty) {
      _showSnackBar('Paste ICS content or enter an HTTPS ICS URL.');
      return;
    }

    try {
      final importResult = await _calendarService.importCalendar(
        session: _session,
        icsUrl: result.$1,
        icsContent: result.$2,
      );
      _cacheSession(importResult.$1);
      await _loadMonth();
      if (!mounted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _showSnackBar('Imported ${importResult.$2} calendar events.');
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _pickAndImportCalendarFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Calendar files', extensions: ['ics', 'zip']),
        ],
      );

      if (file == null) {
        return;
      }

      final name = file.name.toLowerCase();
      final bytes = await file.readAsBytes();

      if (name.endsWith('.ics')) {
        final content = String.fromCharCodes(bytes);
        await _importCalendarContents([content]);
        return;
      }

      if (name.endsWith('.zip')) {
        final archives = _extractIcsFilesFromZip(bytes);
        if (archives.isEmpty) {
          _showSnackBar('No .ics files were found in that zip archive.');
          return;
        }
        await _importCalendarContents(archives);
        return;
      }

      _showSnackBar('Only .ics and .zip files are supported.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  List<String> _extractIcsFilesFromZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final contents = <String>[];

    for (final entry in archive.files) {
      if (!entry.isFile || !entry.name.toLowerCase().endsWith('.ics')) {
        continue;
      }

      final data = entry.content;
      if (data is List<int>) {
        contents.add(String.fromCharCodes(data));
      }
    }

    return contents;
  }

  Future<void> _importCalendarContents(List<String> contents) async {
    var totalImported = 0;

    for (final content in contents) {
      final importResult = await _calendarService.importCalendar(
        session: _session,
        icsContent: content,
      );
      _cacheSession(importResult.$1);
      totalImported += importResult.$2;
    }

    await _loadMonth();
    if (!mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Imported $totalImported calendar events.');
    });
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initialSession: _session,
          onSessionUpdated: (session) {
            _cacheSession(session);
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _logout() async {
    _liveActivityTimer?.cancel();
    if (_liveActivityId != null) {
      await LiveActivityService.endActivity(_liveActivityId!);
    } else if (_liveActivitySupported) {
      await LiveActivityService.endAllActivities();
    }
    await WidgetSyncService.clear();
    await SessionStorage.clearLiveActivity();
    await PushNotificationService.removeDeviceToken();
    if (!mounted) {
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  DateTime _dateWithTime(DateTime base, String suggestedTime) {
    final parts = suggestedTime.split(':');
    if (parts.length != 2) {
      return DateTime(base.year, base.month, base.day, 12);
    }

    final hour = int.tryParse(parts[0]) ?? 12;
    final minute = int.tryParse(parts[1]) ?? 0;
    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  (DateTime, DateTime) _monthRange(DateTime date) {
    final start = DateTime(date.year, date.month, 1);
    final end = DateTime(date.year, date.month + 1, 0, 23, 59, 59, 999);
    return (start, end);
  }

  String _formatDate(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  DateTime? _dayComparisonEnd(CalendarTask task) {
    final start = task.startDate;
    final end = task.endDate;
    if (end == null) {
      return start;
    }
    if (start == null) {
      return end;
    }

    final endsAtMidnight =
        end.hour == 0 &&
        end.minute == 0 &&
        end.second == 0 &&
        end.millisecond == 0 &&
        end.microsecond == 0;
    if (endsAtMidnight && end.isAfter(start)) {
      return end.subtract(const Duration(milliseconds: 1));
    }
    return end;
  }

  bool _taskFallsOnDate(CalendarTask task, DateTime date) {
    final start = task.startDate ?? task.endDate;
    if (start == null) {
      return false;
    }

    final end = _dayComparisonEnd(task) ?? start;
    final target = DateUtils.dateOnly(date);
    final startDay = DateUtils.dateOnly(start);
    final endDay = DateUtils.dateOnly(end);
    return !target.isBefore(startDay) && !target.isAfter(endDay);
  }

  bool _isAllDayTask(CalendarTask task) {
    final start = task.startDate;
    if (start == null) {
      return true;
    }

    final end = _dayComparisonEnd(task);
    final startsAtMidnight = start.hour == 0 && start.minute == 0;
    if (!startsAtMidnight) {
      return false;
    }
    if (end == null) {
      return true;
    }

    return end.difference(start) >= const Duration(hours: 20);
  }

  int _compareDayTasks(CalendarTask a, CalendarTask b) {
    final aAllDay = _isAllDayTask(a);
    final bAllDay = _isAllDayTask(b);
    if (aAllDay != bAllDay) {
      return aAllDay ? -1 : 1;
    }

    final aStart = a.startDate;
    final bStart = b.startDate;
    if (aStart == null && bStart != null) {
      return -1;
    }
    if (aStart != null && bStart == null) {
      return 1;
    }
    if (aStart != null && bStart != null) {
      final byStart = aStart.compareTo(bStart);
      if (byStart != 0) {
        return byStart;
      }
    }

    final aEnd = _dayComparisonEnd(a);
    final bEnd = _dayComparisonEnd(b);
    if (aEnd == null && bEnd != null) {
      return -1;
    }
    if (aEnd != null && bEnd == null) {
      return 1;
    }
    if (aEnd != null && bEnd != null) {
      final byEnd = aEnd.compareTo(bEnd);
      if (byEnd != 0) {
        return byEnd;
      }
    }

    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  List<CalendarTask> get _tasksForSelectedDay {
    return _visibleTasks
        .where((task) => _taskFallsOnDate(task, _selectedDate))
        .toList()
      ..sort(_compareDayTasks);
  }

  List<CalendarTask> get _pendingSelectedTasks =>
      _tasksForSelectedDay.where((task) => !task.isCompleted).toList();

  List<CalendarTask> get _completedSelectedTasks =>
      _tasksForSelectedDay.where((task) => task.isCompleted).toList();

  List<CalendarTask> get _allDaySelectedTasks =>
      _pendingSelectedTasks.where(_isAllDayTask).toList()
        ..sort(_compareDayTasks);

  List<CalendarTask> get _timedSelectedTasks =>
      _pendingSelectedTasks
          .where((task) => !_isAllDayTask(task) && task.startDate != null)
          .toList()
        ..sort(_compareDayTasks);

  List<CalendarTask> get _todoTasksForSelectedDay => _pendingSelectedTasks;

  Color _taskBaseColor(CalendarTask task) {
    final parsed = _parseColor(task.color);
    if (parsed != null) {
      return parsed;
    }

    switch (task.source.toLowerCase()) {
      case 'ical':
        return const Color(0xFF94A3B8); // slate
      case 'task':
        return const Color(0xFF22C55E); // green
      case 'plan':
        return const Color(0xFFA855F7); // purple
      case 'event':
      default:
        return AppTheme.accent; // blue
    }
  }

  Color _taskDisplayColor(CalendarTask task, {Color? groupColor}) {
    final parsed = _parseColor(task.color);
    if (parsed != null) {
      return parsed;
    }

    return groupColor ?? _taskBaseColor(task);
  }

  Color? _parseColor(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    if (normalized.length != 6 && normalized.length != 8) {
      return null;
    }

    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) {
      return null;
    }

    return Color(normalized.length == 6 ? 0xFF000000 | parsed : parsed);
  }

  Map<String, dynamic>? get _selectedDayWeather {
    final daily = _weatherData?['daily'];
    if (daily is! Map<String, dynamic>) {
      return null;
    }

    final target = _formatDate(_selectedDate);
    final times =
        (daily['time'] as List?)?.map((item) => '$item').toList() ?? [];
    final index = times.indexOf(target);
    if (index < 0) return null;

    int? readInt(String key) =>
        ((daily[key] as List?)?.elementAt(index) as num?)?.toInt();
    num? readNum(String key) => (daily[key] as List?)?.elementAt(index) as num?;

    return {
      'code': readInt('weathercode'),
      'max': readNum('temperature_2m_max'),
      'min': readNum('temperature_2m_min'),
    };
  }

  List<Map<String, dynamic>> get _selectedDayForecast {
    final daily = _weatherData?['daily'];
    if (daily is! Map<String, dynamic>) {
      return const [];
    }

    final times =
        (daily['time'] as List?)?.map((item) => '$item').toList() ?? const [];
    if (times.isEmpty) {
      return const [];
    }

    final target = _formatDate(_selectedDate);
    final startIndex = times.indexOf(target);
    if (startIndex < 0) {
      return const [];
    }

    final endIndex = (startIndex + 5).clamp(0, times.length);
    return List.generate(endIndex - startIndex, (offset) {
      final index = startIndex + offset;
      num? readNum(String key) =>
          (daily[key] as List?)?.elementAt(index) as num?;
      int? readInt(String key) =>
          ((daily[key] as List?)?.elementAt(index) as num?)?.toInt();
      return {
        'date': times[index],
        'min': readNum('temperature_2m_min'),
        'max': readNum('temperature_2m_max'),
        'code': readInt('weathercode'),
      };
    });
  }

  List<Map<String, dynamic>> get _selectedDayHourlyForecast {
    final hourly = _weatherData?['hourly'];
    if (hourly is! Map<String, dynamic>) {
      return const [];
    }

    final times =
        (hourly['time'] as List?)?.map((item) => '$item').toList() ?? const [];
    if (times.isEmpty) {
      return const [];
    }

    final targetDate = _formatDate(_selectedDate);
    final now = DateTime.now();
    final allEntries = <Map<String, dynamic>>[];

    for (var index = 0; index < times.length; index++) {
      final parsedTime = DateTime.tryParse(times[index]);
      if (parsedTime == null || _formatDate(parsedTime) != targetDate) {
        continue;
      }

      final temperature =
          (hourly['temperature_2m'] as List?)?.elementAt(index) as num?;
      final weatherCode =
          ((hourly['weathercode'] as List?)?.elementAt(index) as num?)?.toInt();
      allEntries.add({
        'time': parsedTime,
        'temperature': temperature,
        'code': weatherCode,
      });
    }

    if (allEntries.isEmpty) {
      return const [];
    }

    final isToday = DateUtils.isSameDay(_selectedDate, now);
    if (isToday) {
      final upcoming = allEntries.where((entry) {
        final time = entry['time'] as DateTime?;
        return time != null &&
            !time.isBefore(DateTime(now.year, now.month, now.day, now.hour));
      }).toList();
      return (upcoming.isNotEmpty ? upcoming : allEntries).take(6).toList();
    }

    final preferredHours = {6, 9, 12, 15, 18, 21};
    final preferredEntries = allEntries.where((entry) {
      final time = entry['time'] as DateTime?;
      return time != null && preferredHours.contains(time.hour);
    }).toList();

    if (preferredEntries.length >= 4) {
      return preferredEntries.take(6).toList();
    }

    return allEntries
        .where((entry) {
          final time = entry['time'] as DateTime?;
          return time != null && time.hour % 3 == 0;
        })
        .take(6)
        .toList();
  }

  String get _weatherLocationLabel {
    final explicitName = _weatherLocationName?.trim() ?? '';
    if (explicitName.isNotEmpty) {
      return explicitName;
    }

    final timezone = _weatherData?['timezone']?.toString().trim() ?? '';
    if (timezone.isEmpty) {
      return 'Local forecast';
    }

    final upperTimezone = timezone.toUpperCase();
    if (upperTimezone == 'GMT' || upperTimezone == 'UTC') {
      return 'Local forecast';
    }

    final parts = timezone.split('/');
    return parts.last.replaceAll('_', ' ');
  }

  String _weatherConditionLabel(int? code) {
    if (code == null) return 'Weather unavailable';
    if (code == 0) return 'Clear sky';
    if (code == 1) return 'Mostly clear';
    if (code == 2) return 'Partly cloudy';
    if (code == 3) return 'Overcast';
    if (code == 45 || code == 48) return 'Foggy';
    if (code >= 51 && code <= 67) return 'Rain showers';
    if (code >= 71 && code <= 77) return 'Snow showers';
    if (code >= 80 && code <= 86) return 'Heavy rain';
    if (code == 95 || code == 96 || code == 99) return 'Thunderstorms';
    return 'Mixed conditions';
  }

  String _weatherWidgetMenuLabel(_WeatherWidgetMode mode) {
    return switch (mode) {
      _WeatherWidgetMode.future => 'Future forecast',
      _WeatherWidgetMode.futureAndHourly => 'Future + hourly',
      _WeatherWidgetMode.hourly => 'Hourly only',
    };
  }

  String _weatherGlyph(int? code) {
    if (code == null) return '•';
    if (code == 0 || code == 1) return '☀️';
    if (code == 2 || code == 3) return '⛅';
    if (code == 45 || code == 48) return '🌫️';
    if (code >= 51 && code <= 67) return '🌧️';
    if (code >= 71 && code <= 77) return '❄️';
    if (code >= 80 && code <= 86) return '🌦️';
    if (code == 95 || code == 96 || code == 99) return '⛈️';
    return '•';
  }

  Widget _buildTaskPreviewRow(CalendarTask task) {
    final accentColor = _taskDisplayColor(task);
    final timeText = _isAllDayTask(task)
        ? 'All day'
        : task.startDate == null
        ? 'Any time'
        : task.endDate != null
        ? '${_formatTime(task.startDate!)} - ${_formatTime(task.endDate!)}'
        : _formatTime(task.startDate!);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openTaskDialog(task: task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title.isEmpty ? '(Untitled)' : task.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: task.isCompleted
                          ? AppTheme.textMuted
                          : AppTheme.textPrimary,
                      decoration: task.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeText,
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  if (task.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (task.source.toLowerCase() == 'task')
              Checkbox(
                value: task.isCompleted,
                activeColor: accentColor,
                onChanged: (value) {
                  if (value != null) {
                    _toggleTask(task, value);
                  }
                },
              )
            else
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.55),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarTab() {
    return _buildCalendarTabRevamp();
  }

  Widget _buildDayTab() {
    return _buildDayTabPolished();
  }

  // ── CALENDAR TAB — compact month grid + agenda list ─────────────────────
  Widget _buildCalendarTabRevamp() {
    final today = DateUtils.dateOnly(DateTime.now());
    final selectedDayWeather = _selectedDayWeather;
    final dayTasks = _tasksForSelectedDay;

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () => _loadMonth(showLoader: false),
            child: CustomScrollView(
              slivers: [
                // ── Month header row ──────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_monthName(_displayMonth.month)} ${_displayMonth.year}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => unawaited(
                            _setDisplayedMonth(
                              DateTime(
                                _displayMonth.year,
                                _displayMonth.month - 1,
                              ),
                              animatePage: true,
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => unawaited(
                            _setDisplayedMonth(
                              DateTime(
                                _displayMonth.year,
                                _displayMonth.month + 1,
                              ),
                              animatePage: true,
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.today_outlined),
                          onPressed: () => unawaited(
                            _setDisplayedMonth(
                              DateTime(today.year, today.month),
                              animatePage: true,
                              selectedDateOverride: today,
                            ),
                          ),
                          tooltip: 'Today',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Weekday labels ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                          .map(
                            (d) => Expanded(
                              child: Center(
                                child: Text(
                                  d,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),

                // ── Swipeable month grid ──────────────────────────────────
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 336,
                    child: PageView.builder(
                      controller: _monthPageController,
                      onPageChanged: (page) {
                        final base = DateTime(today.year, today.month);
                        unawaited(
                          _setDisplayedMonth(
                            DateTime(base.year, base.month + (page - 1200)),
                          ),
                        );
                      },
                      itemBuilder: (context, page) {
                        final base = DateTime(today.year, today.month);
                        final pageMonth = DateTime(
                          base.year,
                          base.month + (page - 1200),
                        );
                        final firstDay =
                            DateTime(
                              pageMonth.year,
                              pageMonth.month,
                              1,
                            ).weekday %
                            7;
                        final daysInMonth = DateTime(
                          pageMonth.year,
                          pageMonth.month + 1,
                          0,
                        ).day;
                        final totalCells = firstDay + daysInMonth;
                        final rows = (totalCells / 7).ceil();

                        return GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                childAspectRatio: 0.9,
                                mainAxisSpacing: 2,
                                crossAxisSpacing: 2,
                              ),
                          itemCount: rows * 7,
                          itemBuilder: (context, index) {
                            final dayNum = index - firstDay + 1;
                            if (dayNum < 1 || dayNum > daysInMonth) {
                              return const SizedBox.shrink();
                            }
                            final date = DateTime(
                              pageMonth.year,
                              pageMonth.month,
                              dayNum,
                            );
                            return DayGrid(
                              day: dayNum,
                              isToday: DateUtils.isSameDay(date, today),
                              isSelected: DateUtils.isSameDay(
                                date,
                                _selectedDate,
                              ),
                              weatherData: _weatherData,
                              tasks: _visibleTasks
                                  .where(
                                    (t) =>
                                        DateUtils.isSameDay(t.startDate, date),
                                  )
                                  .toList(),
                              onDayTap: (selectedDay) {
                                setState(() {
                                  _selectedDate = DateTime(
                                    pageMonth.year,
                                    pageMonth.month,
                                    selectedDay,
                                  );
                                });
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),

                // ── Divider ───────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Divider(height: 1, color: AppTheme.border),
                ),

                // ── Selected-day header ───────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateUtils.isSameDay(_selectedDate, today)
                                    ? 'Today'
                                    : '${_weekdayName(_selectedDate.weekday)}, '
                                          '${_monthName(_selectedDate.month)} '
                                          '${_selectedDate.day}',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if (selectedDayWeather != null)
                                Text(
                                  '${(selectedDayWeather['max'] as num?)?.round() ?? 0}° / '
                                  '${(selectedDayWeather['min'] as num?)?.round() ?? 0}°  '
                                  '${_weatherGlyph(selectedDayWeather['code'] as int?)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _openTaskDialog(),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Quick-add bar ─────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _quickAddController,
                      decoration: InputDecoration(
                        hintText: 'Quick add…',
                        hintStyle: TextStyle(color: AppTheme.textMuted),
                        prefixIcon: const Icon(
                          Icons.add_circle_outline,
                          size: 18,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.border),
                        ),
                      ),
                      onSubmitted: (value) => unawaited(_submitQuickAdd(value)),
                    ),
                  ),
                ),

                // ── Agenda list ───────────────────────────────────────────
                if (dayTasks.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Nothing scheduled',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _buildTaskPreviewRow(dayTasks[i]),
                        ),
                        childCount: dayTasks.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
  }

  // ── TODAY TAB — timeline schedule view ───────────────────────────────────
  // ignore: unused_element
  Widget _buildDayTabRevamp() {
    final dayTasks = _tasksForSelectedDay;
    final todoTasks = _todoTasksForSelectedDay;
    final completedTasks = _completedSelectedTasks;
    final selectedDayWeather = _selectedDayWeather;
    final formattedDate =
        '${_monthName(_selectedDate.month)} ${_selectedDate.day}, ${_selectedDate.year}';
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return RefreshIndicator(
      onRefresh: () => _loadMonth(showLoader: false),
      child: CustomScrollView(
        slivers: [
          // ── Day summary strip ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: dayTasks.isEmpty
                              ? 0
                              : completedTasks.length / dayTasks.length,
                          strokeWidth: 3,
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          color: AppTheme.accentStrong,
                        ),
                        Text(
                          '${completedTasks.length}/${dayTasks.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isToday ? 'Today' : formattedDate,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (selectedDayWeather != null)
                          Text(
                            '${(selectedDayWeather['max'] as num?)?.round() ?? 0}° / '
                            '${(selectedDayWeather['min'] as num?)?.round() ?? 0}°  '
                            '${_weatherGlyph(selectedDayWeather['code'] as int?)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () =>
                        _openTaskDialog(initialDate: _selectedDate),
                    tooltip: 'Add item',
                  ),
                ],
              ),
            ),
          ),

          // ── Quick-add bar ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _quickAddController,
                decoration: InputDecoration(
                  hintText: 'Quick add…',
                  hintStyle: TextStyle(color: AppTheme.textMuted),
                  prefixIcon: const Icon(Icons.add_circle_outline, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.border),
                  ),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    _openTaskDialog(
                      initialTitle: value.trim(),
                      initialDate: _selectedDate,
                    );
                    _quickAddController.clear();
                  }
                },
              ),
            ),
          ),

          // ── Action chips ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  _DayActionChip(
                    label: 'Task',
                    icon: Icons.check_circle_outline,
                    onTap: () => _openTaskDialog(initialDate: _selectedDate),
                  ),
                  const SizedBox(width: 8),
                  _DayActionChip(
                    label: 'Event',
                    icon: Icons.event_outlined,
                    onTap: () => _openTaskDialog(initialDate: _selectedDate),
                  ),
                  const SizedBox(width: 8),
                  _DayActionChip(
                    label: 'AI',
                    icon: Icons.auto_awesome_outlined,
                    onTap: () => setState(() => _selectedIndex = 2),
                  ),
                  const SizedBox(width: 8),
                  _DayActionChip(
                    label: 'Import',
                    icon: Icons.upload_file_outlined,
                    onTap: _openImportDialog,
                  ),
                ],
              ),
            ),
          ),

          // ── All-day items ─────────────────────────────────────────────
          if (todoTasks.where((t) => t.startDate == null).isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'ALL DAY',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final task = todoTasks
                        .where((t) => t.startDate == null)
                        .toList()[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _buildTaskPreviewRow(task),
                    );
                  },
                  childCount: todoTasks
                      .where((t) => t.startDate == null)
                      .length,
                ),
              ),
            ),
          ],

          // ── Timeline ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _buildTimelineView(
              todoTasks.where((t) => t.startDate != null).toList(),
            ),
          ),

          // ── Completed ────────────────────────────────────────────────
          if (completedTasks.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'COMPLETED',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _buildTaskPreviewRow(completedTasks[i]),
                  ),
                  childCount: completedTasks.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _shiftSelectedDay(int delta) {
    final nextDate = DateUtils.dateOnly(
      _selectedDate.add(Duration(days: delta)),
    );
    final today = DateTime.now();
    final monthOffset =
        (nextDate.year - today.year) * 12 + (nextDate.month - today.month);

    setState(() {
      _selectedDate = nextDate;
      _displayMonth = DateTime(nextDate.year, nextDate.month);
      _expandedDayTaskIds.clear();
    });

    if (_monthPageController.hasClients) {
      _monthPageController.animateToPage(
        1200 + monthOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _toggleDayTaskExpanded(CalendarTask task) {
    final taskId = task.id.isEmpty
        ? '${task.title}-${task.startDate?.toIso8601String() ?? 'unscheduled'}'
        : task.id;
    setState(() {
      if (!_expandedDayTaskIds.add(taskId)) {
        _expandedDayTaskIds.remove(taskId);
      }
    });
  }

  Widget _buildDayTaskTile(CalendarTask task) {
    final accentColor = _taskDisplayColor(task);
    final taskKey = task.id.isEmpty
        ? '${task.title}-${task.startDate?.toIso8601String() ?? 'unscheduled'}'
        : task.id;
    final isExpanded = _expandedDayTaskIds.contains(taskKey);
    final hasDescription = task.description.trim().isNotEmpty;
    final timeText = _isAllDayTask(task)
        ? 'All day'
        : task.startDate == null
        ? 'Any time'
        : task.endDate != null
        ? '${_formatTime(task.startDate!)} - ${_formatTime(task.endDate!)}'
        : _formatTime(task.startDate!);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openTaskDialog(task: task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: task.isCompleted ? 0.07 : 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeText,
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    task.title.isEmpty ? '(Untitled)' : task.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: task.isCompleted
                          ? AppTheme.textMuted
                          : AppTheme.textPrimary,
                      decoration: task.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (hasDescription) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _toggleDayTaskExpanded(task),
                      child: Text(
                        task.description.trim(),
                        maxLines: isExpanded ? null : 2,
                        overflow: isExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.35,
                        ),
                      ),
                    ),
                    if (task.description.trim().length > 90)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          isExpanded ? 'Show less' : 'Show more',
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                  if (task.location.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      task.location.trim(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (task.source.toLowerCase() == 'task')
              Checkbox(
                value: task.isCompleted,
                activeColor: accentColor,
                onChanged: (value) {
                  if (value != null) {
                    _toggleTask(task, value);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  String _formatHourlyWeatherLabel(DateTime time) {
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return '$hour$suffix';
  }

  Widget _buildHourlyWeatherStrip(List<Map<String, dynamic>> hourlyForecast) {
    if (hourlyForecast.isEmpty) {
      return Text(
        'Hourly forecast unavailable',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: 13,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: hourlyForecast.map((entry) {
          final time = entry['time'] as DateTime?;
          final temperature = (entry['temperature'] as num?)?.round();
          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time == null ? '--' : _formatHourlyWeatherLabel(time),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.76),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _weatherGlyph(entry['code'] as int?),
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(height: 10),
                Text(
                  temperature != null ? '$temperature°' : '--',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFutureForecastList(
    List<Map<String, dynamic>> forecast,
    double? minForecastTemp,
    double? maxForecastTemp,
  ) {
    if (forecast.isEmpty) {
      return Text(
        'Forecast unavailable',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: 13,
        ),
      );
    }

    return Column(
      children: forecast.map((entry) {
        final date = DateTime.tryParse('${entry['date']}');
        final minTemp = (entry['min'] as num?)?.round();
        final maxTemp = (entry['max'] as num?)?.round();
        final minValue = (entry['min'] as num?)?.toDouble();
        final maxValue = (entry['max'] as num?)?.toDouble();
        final spread = ((maxForecastTemp ?? 0) - (minForecastTemp ?? 0)).abs();
        final normalizedSpread = spread < 1 ? 1.0 : spread;
        final startFraction = minForecastTemp == null || minValue == null
            ? 0.0
            : ((minValue - minForecastTemp) / normalizedSpread).clamp(0.0, 1.0);
        final widthFraction = minValue == null || maxValue == null
            ? 0.45
            : ((maxValue - minValue) / normalizedSpread).clamp(0.18, 1.0);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  date == null
                      ? '--'
                      : _weekdayName(date.weekday).substring(0, 3),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 24,
                child: Center(
                  child: Text(
                    _weatherGlyph(entry['code'] as int?),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              SizedBox(
                width: 30,
                child: Text(
                  minTemp != null ? '$minTemp°' : '--',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WeatherRangeBar(
                  startFraction: startFraction,
                  widthFraction: widthFraction,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 30,
                child: Text(
                  maxTemp != null ? '$maxTemp°' : '--',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWeatherWidgetModeButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: PopupMenuButton<_WeatherWidgetMode>(
        initialValue: _weatherWidgetMode,
        tooltip: 'Weather layout',
        onSelected: (mode) => unawaited(_setWeatherWidgetMode(mode)),
        padding: EdgeInsets.zero,
        splashRadius: 18,
        icon: Icon(
          Icons.widgets_outlined,
          color: Colors.white.withValues(alpha: 0.88),
          size: 18,
        ),
        itemBuilder: (context) => _WeatherWidgetMode.values
            .map(
              (mode) => PopupMenuItem<_WeatherWidgetMode>(
                value: mode,
                child: Text(_weatherWidgetMenuLabel(mode)),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildTodayHeroCard({
    required bool isToday,
    required String formattedDate,
    required int totalTasks,
    required int completedTasks,
    required Map<String, dynamic>? selectedDayWeather,
    required List<Map<String, dynamic>> forecast,
  }) {
    final high = (selectedDayWeather?['max'] as num?)?.round();
    final low = (selectedDayWeather?['min'] as num?)?.round();
    final conditionCode = selectedDayWeather?['code'] as int?;
    final forecastMins = forecast
        .map((day) => (day['min'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final forecastMaxes = forecast
        .map((day) => (day['max'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final minForecastTemp = forecastMins.isEmpty
        ? null
        : forecastMins.reduce((a, b) => a < b ? a : b);
    final maxForecastTemp = forecastMaxes.isEmpty
        ? null
        : forecastMaxes.reduce((a, b) => a > b ? a : b);
    final activeTasks = totalTasks - completedTasks;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3F475A), Color(0xFF2A82BF), Color(0xFF244D86)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF091325).withValues(alpha: 0.42),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => _shiftSelectedDay(-1),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left, color: Colors.white),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      isToday ? 'Today' : _weekdayName(_selectedDate.weekday),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.96),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formattedDate,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _shiftSelectedDay(1),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.near_me_rounded,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _weatherLocationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      high != null ? '$high°' : '--°',
                      style: const TextStyle(
                        fontSize: 58,
                        height: 0.92,
                        fontWeight: FontWeight.w300,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _weatherConditionLabel(conditionCode),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.96),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (low != null) 'Low of $low°',
                        '$activeTasks active',
                        '$completedTasks done',
                      ].join(' · '),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.74),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 6,
                child: forecast.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(
                          'Forecast unavailable',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 13,
                          ),
                        ),
                      )
                    : Column(
                        children: forecast.map((entry) {
                          final date = DateTime.tryParse('${entry['date']}');
                          final minTemp = (entry['min'] as num?)?.round();
                          final maxTemp = (entry['max'] as num?)?.round();
                          final minValue = (entry['min'] as num?)?.toDouble();
                          final maxValue = (entry['max'] as num?)?.toDouble();
                          final spread =
                              ((maxForecastTemp ?? 0) - (minForecastTemp ?? 0))
                                  .abs();
                          final normalizedSpread = spread < 1 ? 1.0 : spread;
                          final startFraction =
                              minForecastTemp == null || minValue == null
                              ? 0.0
                              : ((minValue - minForecastTemp) /
                                        normalizedSpread)
                                    .clamp(0.0, 1.0);
                          final widthFraction =
                              minValue == null || maxValue == null
                              ? 0.45
                              : ((maxValue - minValue) / normalizedSpread)
                                    .clamp(0.18, 1.0);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 36,
                                  child: Text(
                                    date == null
                                        ? '--'
                                        : _weekdayName(
                                            date.weekday,
                                          ).substring(0, 3),
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.92,
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 24,
                                  child: Center(
                                    child: Text(
                                      _weatherGlyph(entry['code'] as int?),
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 30,
                                  child: Text(
                                    minTemp != null ? '$minTemp°' : '--',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.68,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _WeatherRangeBar(
                                    startFraction: startFraction,
                                    widthFraction: widthFraction,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 30,
                                  child: Text(
                                    maxTemp != null ? '$maxTemp°' : '--',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodayHeroCardV2({
    required bool isToday,
    required String formattedDate,
    required int totalTasks,
    required int completedTasks,
    required Map<String, dynamic>? selectedDayWeather,
    required List<Map<String, dynamic>> forecast,
  }) {
    final high = (selectedDayWeather?['max'] as num?)?.round();
    final low = (selectedDayWeather?['min'] as num?)?.round();
    final conditionCode = selectedDayWeather?['code'] as int?;
    final forecastMins = forecast
        .map((day) => (day['min'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final forecastMaxes = forecast
        .map((day) => (day['max'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final minForecastTemp = forecastMins.isEmpty
        ? null
        : forecastMins.reduce((a, b) => a < b ? a : b);
    final maxForecastTemp = forecastMaxes.isEmpty
        ? null
        : forecastMaxes.reduce((a, b) => a > b ? a : b);
    final activeTasks = totalTasks - completedTasks;
    final hourlyForecast = _selectedDayHourlyForecast;

    Widget buildSummaryColumn() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.near_me_rounded,
                size: 14,
                color: Colors.white.withValues(alpha: 0.92),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _weatherLocationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            high != null ? '$high°' : '--°',
            style: const TextStyle(
              fontSize: 58,
              height: 0.92,
              fontWeight: FontWeight.w300,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _weatherConditionLabel(conditionCode),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.96),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (low != null) 'Low of $low°',
              '$activeTasks active',
              '$completedTasks done',
            ].join(' · '),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      );
    }

    Widget buildHourlySummary() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: buildSummaryColumn()),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _weatherConditionLabel(conditionCode),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.96),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (high != null) 'H:$high°',
                      if (low != null) 'L:$low°',
                    ].join(' '),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3F475A), Color(0xFF2A82BF), Color(0xFF244D86)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF091325).withValues(alpha: 0.42),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => _shiftSelectedDay(-1),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left, color: Colors.white),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      isToday ? 'Today' : _weekdayName(_selectedDate.weekday),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.96),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formattedDate,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _buildWeatherWidgetModeButton(),
              IconButton(
                onPressed: () => _shiftSelectedDay(1),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_weatherWidgetMode == _WeatherWidgetMode.future)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: buildSummaryColumn()),
                const SizedBox(width: 16),
                Expanded(
                  flex: 6,
                  child: _buildFutureForecastList(
                    forecast,
                    minForecastTemp,
                    maxForecastTemp,
                  ),
                ),
              ],
            )
          else ...[
            buildHourlySummary(),
            const SizedBox(height: 16),
            _buildHourlyWeatherStrip(hourlyForecast),
            if (_weatherWidgetMode == _WeatherWidgetMode.futureAndHourly) ...[
              const SizedBox(height: 16),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
              const SizedBox(height: 12),
              _buildFutureForecastList(
                forecast,
                minForecastTemp,
                maxForecastTemp,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDayTabPolished() {
    final dayTasks = _tasksForSelectedDay;
    final allDayTasks = _allDaySelectedTasks;
    final timedTasks = _timedSelectedTasks;
    final completedTasks = _completedSelectedTasks;
    final selectedDayWeather = _selectedDayWeather;
    final forecast = _selectedDayForecast;
    final formattedDate =
        '${_monthName(_selectedDate.month)} ${_selectedDate.day}, ${_selectedDate.year}';
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return SafeArea(
      top: true,
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _loadMonth(showLoader: false),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(
                  children: [
                    _DayActionChip(
                      label: 'Task',
                      icon: Icons.check_circle_outline,
                      onTap: () => _openTaskDialog(initialDate: _selectedDate),
                    ),
                    const SizedBox(width: 8),
                    _DayActionChip(
                      label: 'Event',
                      icon: Icons.event_outlined,
                      onTap: () => _openTaskDialog(initialDate: _selectedDate),
                    ),
                    const SizedBox(width: 8),
                    _DayActionChip(
                      label: 'Plan',
                      icon: Icons.auto_stories_outlined,
                      onTap: () => _openTaskDialog(
                        initialDate: _selectedDate,
                        newTaskSource: 'plan',
                      ),
                    ),
                    const SizedBox(width: 8),
                    _DayActionChip(
                      label: 'Suggest',
                      icon: Icons.auto_awesome_outlined,
                      onTap: () => setState(() => _selectedIndex = 2),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Stack(
                  children: [
                    if (_weatherWidgetMode == _WeatherWidgetMode.future)
                      _buildTodayHeroCard(
                        isToday: isToday,
                        formattedDate: formattedDate,
                        totalTasks: dayTasks.length,
                        completedTasks: completedTasks.length,
                        selectedDayWeather: selectedDayWeather,
                        forecast: forecast,
                      )
                    else
                      _buildTodayHeroCardV2(
                        isToday: isToday,
                        formattedDate: formattedDate,
                        totalTasks: dayTasks.length,
                        completedTasks: completedTasks.length,
                        selectedDayWeather: selectedDayWeather,
                        forecast: forecast,
                      ),
                    if (_weatherWidgetMode == _WeatherWidgetMode.future)
                      Positioned(
                        top: 14,
                        right: 52,
                        child: _buildWeatherWidgetModeButton(),
                      ),
                  ],
                ),
              ),
            ),
            if (allDayTasks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'ALL DAY',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildDayTaskTile(allDayTasks[index]),
                    childCount: allDayTasks.length,
                  ),
                ),
              ),
            ],
            if (timedTasks.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildDayTaskTile(timedTasks[index]),
                    childCount: timedTasks.length,
                  ),
                ),
              ),
            if (allDayTasks.isEmpty &&
                timedTasks.isEmpty &&
                completedTasks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Nothing scheduled yet for this day.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                ),
              ),
            if (completedTasks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'COMPLETED',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _buildDayTaskTile(completedTasks[index]),
                    childCount: completedTasks.length,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineView(List<CalendarTask> timedTasks) {
    if (timedTasks.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final isToday = DateUtils.isSameDay(_selectedDate, now);

    // Determine visible hour range
    int minHour = 8;
    int maxHour = 18;
    for (final task in timedTasks) {
      if (task.startDate != null) {
        minHour = task.startDate!.hour < minHour
            ? task.startDate!.hour
            : minHour;
        final endHour = task.endDate != null
            ? task.endDate!.hour + (task.endDate!.minute > 0 ? 1 : 0)
            : task.startDate!.hour + 1;
        maxHour = endHour > maxHour ? endHour : maxHour;
      }
    }
    if (isToday) {
      minHour = now.hour < minHour ? now.hour : minHour;
      maxHour = now.hour + 1 > maxHour ? now.hour + 1 : maxHour;
    }
    minHour = (minHour - 1).clamp(0, 23);
    maxHour = (maxHour + 1).clamp(1, 24);

    const hourHeight = 60.0;
    final totalHours = maxHour - minHour;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SizedBox(
        height: totalHours * hourHeight + 20,
        child: Stack(
          children: [
            // Hour gridlines + labels
            for (int h = minHour; h <= maxHour; h++) ...[
              Positioned(
                top: (h - minHour) * hourHeight,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        h == 0
                            ? '12a'
                            : h < 12
                            ? '${h}a'
                            : h == 12
                            ? '12p'
                            : '${h - 12}p',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(height: 1, color: AppTheme.border)),
                  ],
                ),
              ),
            ],

            // "Now" red line
            if (isToday)
              Positioned(
                top: ((now.hour + now.minute / 60.0) - minHour) * hourHeight,
                left: 40,
                right: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),

            // Task blocks
            for (final task in timedTasks)
              if (task.startDate != null)
                Positioned(
                  top:
                      ((task.startDate!.hour + task.startDate!.minute / 60.0) -
                          minHour) *
                      hourHeight,
                  left: 48,
                  right: 0,
                  height: (() {
                    if (task.endDate != null) {
                      final dur = task.endDate!.difference(task.startDate!);
                      return (dur.inMinutes / 60.0 * hourHeight).clamp(
                        20.0,
                        double.infinity,
                      );
                    }
                    return hourHeight * 0.75;
                  })(),
                  child: GestureDetector(
                    onTap: () => _openTaskDialog(task: task),
                    child: Container(
                      margin: const EdgeInsets.only(right: 4, bottom: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _taskDisplayColor(task).withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _taskDisplayColor(
                            task,
                          ).withValues(alpha: 0.50),
                        ),
                      ),
                      child: Text(
                        task.title.isEmpty ? '(Untitled)' : task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: task.isCompleted
                              ? AppTheme.textMuted
                              : AppTheme.textPrimary,
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  PreferredSizeWidget? _buildAppBar() {
    final selectedDateLabel =
        '${_monthName(_selectedDate.month)} ${_selectedDate.day}, ${_selectedDate.year}';

    if (_selectedIndex == 1) {
      return null;
    }

    return AppBar(
      title: Text(
        _selectedIndex == 0 ? 'Calendar++' : 'AI for $selectedDateLabel',
      ),
      actions: [
        if (_selectedIndex == 0) ...[
          IconButton(
            onPressed: _openImportDialog,
            icon: const Icon(Icons.link),
            tooltip: 'Connect calendar',
          ),
        ],
        IconButton(
          onPressed: _openSettings,
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
        ),
        IconButton(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          tooltip: 'Logout',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildCalendarTab(),
          _buildDayTab(),
          AIScreen(
            embedded: true,
            key: ValueKey(_selectedDate.toIso8601String()),
            initialSession: _session,
            selectedDate: _selectedDate,
            onSessionUpdated: (session) {
              setState(() {
                _cacheSession(session);
              });
            },
            onCalendarChanged: () => _loadMonth(),
            onCreateTaskFromSuggestion:
                (title, description, suggestedTime) async {
                  final startDate = _dateWithTime(_selectedDate, suggestedTime);
                  final nextSession = await _calendarService.saveTask(
                    session: _session,
                    title: title,
                    description: description,
                    startDate: startDate,
                    color: '',
                    group: '',
                    reminderEnabled: false,
                    reminderMinutesBefore: 30,
                    reminderDelivery: 'email',
                  );
                  _cacheSession(nextSession);
                  await _loadMonth();
                },
          ),
        ],
      ),
      floatingActionButton: (_selectedIndex == 0 || _selectedIndex == 1)
          ? FloatingActionButton.extended(
              onPressed: () => _openTaskDialog(),
              tooltip: 'Add Item',
              icon: const Icon(Icons.add),
              label: Text(_selectedIndex == 0 ? 'Add Item' : 'Add to Day'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI',
          ),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month - 1];
  }

  String _weekdayName(int weekday) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return weekdays[weekday - 1];
  }
}

class _DayActionChip extends StatelessWidget {
  const _DayActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withValues(alpha: 0.07),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherRangeBar extends StatelessWidget {
  const _WeatherRangeBar({
    required this.startFraction,
    required this.widthFraction,
  });

  final double startFraction;
  final double widthFraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final clampedWidth = widthFraction.clamp(0.12, 1.0) * trackWidth;
        final clampedLeft =
            startFraction.clamp(0.0, 1.0) * (trackWidth - clampedWidth);

        return SizedBox(
          height: 6,
          child: Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Positioned(
                left: clampedLeft,
                child: Container(
                  width: clampedWidth,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8EE1E9), Color(0xFFF7C949)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
