import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/task_model.dart';
import '../models/user_model.dart';
import '../services/calendar_service.dart';
import '../services/live_activity_service.dart';
import '../services/push_notification_service.dart';
import '../services/session_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/day_grid.dart';
import 'ai_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'task_editor_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.initialSession,
  });

  final UserSession initialSession;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const Duration _liveActivityUpcomingWindow = Duration(hours: 12);

  final CalendarService _calendarService = CalendarService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _quickTaskController = TextEditingController();
  final PageController _monthPageController = PageController(initialPage: 1200);

  late UserSession _session;
  Timer? _liveActivityTimer;
  StreamSubscription<Map<String, dynamic>>? _notificationOpenSubscription;
  String? _liveActivityId;
  String? _liveActivityTaskId;
  bool _liveActivitySupported = false;
  bool _liveActivityReady = false;
  DateTime _currentDate = DateTime.now();
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  Map<String, dynamic>? _weatherData;
  List<CalendarTask> _tasks = [];
  List<CalendarTask> _visibleTasks = [];
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isQuickAdding = false;
  int _selectedIndex = 0; // 0=Calendar, 1=Day, 2=AI

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
    unawaited(SessionStorage.saveSession(_session));
    unawaited(_restoreLiveActivityState());
    _liveActivityTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_syncLiveActivity()),
    );
    _notificationOpenSubscription =
        PushNotificationService.notificationOpens.listen((data) {
      unawaited(_handleNotificationOpen(data));
    });
    _loadMonth(showLoader: true);
    _fetchWeather();
  }

  @override
  void dispose() {
    _liveActivityTimer?.cancel();
    _notificationOpenSubscription?.cancel();
    _searchController.dispose();
    _quickTaskController.dispose();
    _monthPageController.dispose();
    super.dispose();
  }

  Future<void> _handleNotificationOpen(Map<String, dynamic> data) async {
    final taskId = data['taskId']?.toString() ?? '';
    if (taskId.isEmpty) {
      return;
    }

    CalendarTask? task = _taskById(taskId);
    if (task == null) {
      await _loadMonth(showLoader: false);
      task = _taskById(taskId);
    }

    if (!mounted || task?.startDate == null) {
      return;
    }

    final selectedDay = DateUtils.dateOnly(task!.startDate!);
    setState(() {
      _selectedDate = selectedDay;
      _currentDate = DateTime(selectedDay.year, selectedDay.month, 1);
      _selectedIndex = 1;
    });

    final now = DateTime.now();
    final monthOffset =
        (selectedDay.year - now.year) * 12 + (selectedDay.month - now.month);
    _monthPageController.jumpToPage(1200 + monthOffset);
  }

  Future<void> _restoreLiveActivityState() async {
    _liveActivitySupported = await LiveActivityService.isSupported();
    final saved = await SessionStorage.readLiveActivity();
    _liveActivityId = saved.activityId;
    _liveActivityTaskId = saved.taskId;
    _liveActivityReady = true;
    await _syncLiveActivity();
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

  CalendarTask? _liveActivityCandidate() {
    final now = DateTime.now();
    final candidates = _tasks.where((task) {
      if (task.isCompleted || task.startDate == null) {
        return false;
      }

      final start = task.startDate!;
      final end = _effectiveEndDate(task);
      final isOngoing = !now.isBefore(start) && !now.isAfter(end);
      final isUpcoming = start.isAfter(now) &&
          start.difference(now) <= _liveActivityUpcomingWindow;

      return isOngoing || isUpcoming;
    }).toList()
      ..sort((a, b) {
        final aStart = a.startDate!;
        final bStart = b.startDate!;
        final aOngoing = !now.isBefore(aStart) && !now.isAfter(_effectiveEndDate(a));
        final bOngoing = !now.isBefore(bStart) && !now.isAfter(_effectiveEndDate(b));

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
    final candidateLocation =
        candidate.location.trim().isEmpty ? null : candidate.location.trim();
    final candidateTitle =
        candidate.title.trim().isEmpty ? 'Untitled item' : candidate.title.trim();

    if (_liveActivityId != null && _liveActivityTaskId == candidate.id) {
      await LiveActivityService.updateActivity(
        activityId: _liveActivityId!,
        title: candidateTitle,
        startTime: candidateStart,
        endTime: candidateEnd,
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

  void _goToToday() {
    final now = DateUtils.dateOnly(DateTime.now());
    setState(() {
      _selectedDate = now;
      _currentDate = now;
    });
    // Jump the page controller back to the base page (offset 1200 represents today)
    _monthPageController.jumpToPage(1200);
    _loadMonth(showLoader: false);
  }

  void _cacheSession(UserSession session) {
    _session = session;
    unawaited(SessionStorage.saveSession(session));
  }

  Future<void> _loadMonth({bool showLoader = false}) async {
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
      unawaited(_syncLiveActivity());
    } catch (error) {
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

  Future<void> _fetchWeather() async {
    try {
      // Resolve device location, falling back to a default if permission denied.
      double latitude = 28.5383;
      double longitude = -81.3792;

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 10),
            ),
          );
          latitude = position.latitude;
          longitude = position.longitude;
        }
      }

      final today = DateTime.now();
      final start = _formatDate(today);
      final end = _formatDate(today.add(const Duration(days: 10)));
      final response = await http.get(
        Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude&start_date=$start&end_date=$end&hourly=weathercode&daily=weathercode,temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit',
        ),
      );

      if (!mounted || response.statusCode != 200) {
        return;
      }

      setState(() {
        _weatherData = jsonDecode(response.body) as Map<String, dynamic>;
      });
    } catch (_) {
      // Ignore optional weather failures.
    }
  }

  Future<void> _searchTasks(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _visibleTasks = _tasks;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final result = await _calendarService.searchCalendar(
        session: _session,
        search: trimmed,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _cacheSession(result.session);
        _visibleTasks = result.tasks;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _openTaskDialog({
    CalendarTask? task,
    String? newTaskSource,
    String? initialGroup,
  }) async {
    final baseDate = task?.startDate ?? _selectedDate;
    final initialEndDate = task?.endDate ??
        (task?.startDate ?? _selectedDate).add(const Duration(hours: 1));

    final result = await Navigator.push<TaskEditorResult>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskEditorScreen(
          initialTitle: task?.title ?? '',
          initialDescription: task?.description ?? '',
          initialLocation: task?.location ?? '',
          initialColor: task?.color ?? '',
          initialGroup: task?.group ?? initialGroup ?? _defaultGroupForNewTask,
          existingGroups: _existingGroups,
          initialStartDate: baseDate,
          initialEndDate: initialEndDate,
          initialReminderEnabled: task?.reminderEnabled ?? false,
          initialReminderMinutesBefore: task?.reminderMinutesBefore ?? 30,
          isEditing: task != null,
        ),
      ),
    );

    if (result == null || result.title.isEmpty) {
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
            onPressed: () => Navigator.pop(
              context,
              (urlController.text.trim(), contentController.text.trim()),
            ),
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
          const XTypeGroup(
            label: 'Calendar files',
            extensions: ['ics', 'zip'],
          ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _deleteTask(CalendarTask task) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete task'),
            content: Text(
              'Delete "${task.title.isEmpty ? '(Untitled)' : task.title}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
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
      _showSnackBar('Task deleted.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
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

  List<CalendarTask> get _tasksForSelectedDay {
    return _visibleTasks.where((task) {
      final startDate = task.startDate;
      return startDate != null && DateUtils.isSameDay(startDate, _selectedDate);
    }).toList()
      ..sort((a, b) => (a.startDate ?? _selectedDate).compareTo(b.startDate ?? _selectedDate));
  }

  List<CalendarTask> get _pendingSelectedTasks =>
      _tasksForSelectedDay.where((task) => !task.isCompleted).toList();

  List<CalendarTask> get _completedSelectedTasks =>
      _tasksForSelectedDay.where((task) => task.isCompleted).toList();

  List<CalendarTask> get _todoTasksForSelectedDay =>
      _pendingSelectedTasks
          .where((task) => task.source.toLowerCase() == 'task')
          .toList();

  List<CalendarTask> get _agendaTasksForSelectedDay =>
      _pendingSelectedTasks
          .where((task) => task.source.toLowerCase() != 'task')
          .toList();

  int get _selectedDayCompletedCount => _completedSelectedTasks.length;

  int get _selectedDayPendingCount => _pendingSelectedTasks.length;

  double get _selectedDayCompletionRatio {
    final dayTasks = _tasksForSelectedDay;
    if (dayTasks.isEmpty) {
      return 0;
    }
    return _selectedDayCompletedCount / dayTasks.length;
  }

  String get _selectedDayHeroTitle {
    return DateUtils.isSameDay(_selectedDate, DateTime.now()) ? 'Today' : 'Plan';
  }

  CalendarTask? get _nextSelectedTask {
    final upcoming = _pendingSelectedTasks.toList()
      ..sort(
        (a, b) => (a.startDate ?? _selectedDate).compareTo(
          b.startDate ?? _selectedDate,
        ),
      );
    return upcoming.isEmpty ? null : upcoming.first;
  }

  String get _selectedDateLongLabel {
    return '${_weekdayName(_selectedDate.weekday)}, ${_monthName(_selectedDate.month)} ${_selectedDate.day}, ${_selectedDate.year}';
  }

  DateTime _defaultQuickTaskStart() {
    final now = DateTime.now();
    if (DateUtils.isSameDay(now, _selectedDate)) {
      final roundedMinute = now.minute <= 30 ? 30 : 0;
      final roundedHour = now.minute <= 30 ? now.hour : now.hour + 1;
      return DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        roundedHour,
        roundedMinute,
      );
    }

    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      9,
    );
  }

  Future<void> _addQuickTaskForSelectedDay() async {
    final title = _quickTaskController.text.trim();
    if (title.isEmpty) {
      return;
    }

    setState(() {
      _isQuickAdding = true;
    });

    try {
      final nextSession = await _calendarService.saveTask(
        session: _session,
        title: title,
        startDate: _defaultQuickTaskStart(),
        source: 'task',
        group: '',
        reminderEnabled: false,
        reminderMinutesBefore: 30,
      );
      _cacheSession(nextSession);
      _quickTaskController.clear();
      await _loadMonth(showLoader: false);
      if (!mounted) {
        return;
      }
      _showSnackBar('Added "$title" to $_selectedDateLongLabel.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isQuickAdding = false;
        });
      }
    }
  }

  String _taskGroupLabel(CalendarTask task) {
    final explicitGroup = task.group.trim();
    if (explicitGroup.isNotEmpty) {
      return explicitGroup;
    }

    switch (task.source.toLowerCase()) {
      case 'ical':
        return 'Imported';
      case 'task':
        return 'Task';
      case 'plan':
        return 'Plan';
      case 'event':
        return 'Event';
      case 'manual':
        return 'Manual';
      default:
        return task.source.isEmpty ? 'Other' : task.source;
    }
  }

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

  Color _groupMajorityColor(List<CalendarTask> tasks) {
    final counts = <int, int>{};
    for (final task in tasks) {
      final parsed = _parseColor(task.color);
      if (parsed == null) {
        continue;
      }
      counts.update(parsed.toARGB32(), (value) => value + 1, ifAbsent: () => 1);
    }

    if (counts.isNotEmpty) {
      final winningValue = counts.entries.reduce(
        (best, next) => next.value > best.value ? next : best,
      );
      return Color(winningValue.key);
    }

    return _taskBaseColor(tasks.first);
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

    return Color(
      normalized.length == 6 ? 0xFF000000 | parsed : parsed,
    );
  }

  Map<String, dynamic>? get _selectedDayWeather {
    final daily = _weatherData?['daily'];
    if (daily is! Map<String, dynamic>) {
      return null;
    }

    final target = _formatDate(_selectedDate);
    final times = (daily['time'] as List?)?.map((item) => '$item').toList() ?? [];
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

  String _weatherLabel(int? code) {
    if (code == null) return 'Weather';
    if (code == 0) return 'Clear';
    if (code == 1) return 'Mostly clear';
    if (code == 2) return 'Partly cloudy';
    if (code == 3) return 'Overcast';
    if (code == 45 || code == 48) return 'Fog';
    if (code == 51 || code == 53 || code == 55) return 'Drizzle';
    if (code == 56 || code == 57) return 'Freezing drizzle';
    if (code == 61 || code == 63 || code == 65) return 'Rain';
    if (code == 66 || code == 67) return 'Freezing rain';
    if (code == 71 || code == 73 || code == 75) return 'Snow';
    if (code == 77) return 'Snow grains';
    if (code == 80 || code == 81 || code == 82) return 'Showers';
    if (code == 85 || code == 86) return 'Snow showers';
    if (code == 95) return 'Thunderstorm';
    if (code == 96 || code == 99) return 'Thunderstorm w/ hail';
    return 'Weather';
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

  Widget _buildGlassPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.12),
                AppTheme.surfaceAlt.withValues(alpha: 0.88),
                AppTheme.surface.withValues(alpha: 0.94),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 22,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildTaskPreviewRow(CalendarTask task) {
    final accentColor = _taskDisplayColor(task);
    final timeText = task.startDate == null
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
          border: Border.all(
            color: accentColor.withValues(alpha: 0.25),
          ),
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
    final today = DateTime.now();

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () => _loadMonth(showLoader: false),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // Search card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.surfaceAlt.withValues(alpha: 0.95),
                        AppTheme.surface.withValues(alpha: 0.98),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(
                          'Plan in one place',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Search tasks, add events, import an ICS calendar, and jump into AI suggestions without leaving the same workspace.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppTheme.textMuted, height: 1.4),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _searchController,
                          onSubmitted: _searchTasks,
                          decoration: InputDecoration(
                            labelText: 'Search tasks',
                            hintText: 'Title, description, or location',
                            suffixIcon: _isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    onPressed: () => _searchTasks(
                                      _searchController.text,
                                    ),
                                    icon: const Icon(Icons.search),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // Month header with Today button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          _monthPageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        icon: const Icon(Icons.chevron_left),
                        tooltip: 'Previous month',
                      ),
                      Expanded(
                        child: Text(
                          '${_monthName(_currentDate.month)} ${_currentDate.year}',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          _monthPageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'Next month',
                      ),
                      TextButton(
                        onPressed: _goToToday,
                        child: const Text('Today'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Column(
                      children: [
                          // Weekday header
                          Row(
                            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                                .map(
                                  (day) => Expanded(
                                    child: Center(
                                      child: Text(
                                        day,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: AppTheme.textMuted,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 8),
                          // Swipeable month grid
                          SizedBox(
                            height: 340,
                            child: PageView.builder(
                              controller: _monthPageController,
                              onPageChanged: (page) {
                                final now = DateTime.now();
                                final monthOffset = page - 1200;
                                final newDate = DateTime(now.year, now.month + monthOffset, 1);
                                setState(() {
                                  _currentDate = newDate;
                                });
                                _loadMonth(showLoader: false);
                              },
                              itemBuilder: (context, page) {
                                final now = DateTime.now();
                                final monthOffset = page - 1200;
                                final pageMonth = DateTime(now.year, now.month + monthOffset, 1);
                                final daysInPageMonth = DateTime(pageMonth.year, pageMonth.month + 1, 0).day;
                                final firstDay = DateTime(pageMonth.year, pageMonth.month, 1).weekday % 7;
                                return GridView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: daysInPageMonth + firstDay,
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 7,
                                    crossAxisSpacing: 4,
                                    mainAxisSpacing: 4,
                                  ),
                                  itemBuilder: (context, index) {
                                    if (index < firstDay) return const SizedBox.shrink();
                                    final day = index - firstDay + 1;
                                    final date = DateTime(pageMonth.year, pageMonth.month, day);
                                    return DayGrid(
                                      day: day,
                                      month: pageMonth.month,
                                      year: pageMonth.year,
                                      isToday: DateUtils.isSameDay(date, today),
                                      isSelected: DateUtils.isSameDay(date, _selectedDate),
                                      weatherData: _weatherData,
                                      tasks: _visibleTasks
                                          .where((t) => DateUtils.isSameDay(t.startDate, date))
                                          .toList(),
                                      onDayTap: (selectedDay) {
                                        setState(() {
                                          _selectedDate = DateTime(pageMonth.year, pageMonth.month, selectedDay);
                                          _selectedIndex = 1; // Switch to Day tab
                                        });
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ],
              ),
            );
  }

  Widget _buildDayTab() {
    return _buildDayTabRevamp();
    final dayTasks = _tasksForSelectedDay;
    final selectedDayWeather = _selectedDayWeather;
    final formattedDate = '${_monthName(_selectedDate.month)} ${_selectedDate.day}, ${_selectedDate.year}';

    return Scaffold(
      appBar: AppBar(
        title: Text(formattedDate),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTaskDialog(),
        label: const Text('Add Item'),
        icon: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadMonth(showLoader: false),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // Weather card for selected day
            if (selectedDayWeather != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        _weatherGlyph(selectedDayWeather['code'] as int?),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _weatherLabel(selectedDayWeather['code'] as int?),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'High ${((selectedDayWeather['max'] as num?)?.round() ?? 0)}°  •  Low ${((selectedDayWeather['min'] as num?)?.round() ?? 0)}°',
                              style: const TextStyle(color: AppTheme.textMuted, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Tasks / items for selected day
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dayTasks.isEmpty ? 'Nothing scheduled' : '${dayTasks.length} item${dayTasks.length == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (dayTasks.isEmpty)
                      const Text(
                        'No items scheduled for this day. Tap + to add one.',
                        style: TextStyle(color: AppTheme.textMuted),
                      )
                    else
                      ...(() {
                        final groupedTasks = <String, List<CalendarTask>>{};
                        for (final task in dayTasks) {
                          final key = _taskGroupLabel(task);
                          groupedTasks.putIfAbsent(key, () => []).add(task);
                        }

                        return groupedTasks.entries.expand((entry) sync* {
                          final groupColor = _groupMajorityColor(entry.value);
                          yield Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: groupColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  entry.key.toUpperCase(),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: groupColor,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.08,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${entry.value.length}',
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          );

                          for (final task in entry.value) {
                            final taskColor = _taskDisplayColor(task, groupColor: groupColor);
                            yield Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: taskColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border(
                                  left: BorderSide(color: taskColor, width: 3),
                                  top: BorderSide(color: taskColor.withValues(alpha: 0.2)),
                                  right: BorderSide(color: taskColor.withValues(alpha: 0.2)),
                                  bottom: BorderSide(color: taskColor.withValues(alpha: 0.2)),
                                ),
                              ),
                              child: ListTile(
                                onTap: () => _openTaskDialog(task: task),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: task.source == 'task'
                                    ? Checkbox(
                                        value: task.isCompleted,
                                        activeColor: taskColor,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                        onChanged: (value) {
                                          if (value != null) _toggleTask(task, value);
                                        },
                                      )
                                    : null,
                                title: Text(
                                  task.title.isEmpty ? '(Untitled)' : task.title,
                                  style: TextStyle(
                                    decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                                    color: task.isCompleted ? AppTheme.textMuted : AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (task.startDate != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        task.endDate != null
                                            ? '${_formatTime(task.startDate!)} – ${_formatTime(task.endDate!)}'
                                            : _formatTime(task.startDate!),
                                        style: TextStyle(
                                          color: taskColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                    if (task.description.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        task.description,
                                        style: const TextStyle(color: AppTheme.textMuted, height: 1.35),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    if (task.location.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '📍 ${task.location}',
                                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _openTaskDialog(task: task);
                                    } else if (value == 'delete') {
                                      _deleteTask(task);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
                                    PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
                                  ],
                                ),
                              ),
                            );
                          }
                        }).toList();
                      })(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarTabRevamp() {
    final today = DateTime.now();
    final selectedDayWeather = _selectedDayWeather;
    final previewTasks = _tasksForSelectedDay.take(3).toList();

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () => _loadMonth(showLoader: false),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _buildGlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedDayHeroTitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _selectedDateLongLabel,
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppTheme.accent.withValues(alpha: 0.28),
                              ),
                            ),
                            child: const Text(
                              'Liquid Glass',
                              style: TextStyle(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _searchController,
                        onSubmitted: _searchTasks,
                        decoration: InputDecoration(
                          labelText: 'Search tasks',
                          hintText: 'Title, description, or location',
                          suffixIcon: _isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  onPressed: () => _searchTasks(
                                    _searchController.text,
                                  ),
                                  icon: const Icon(Icons.search),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _InsightPill(
                            label: 'Pending',
                            value: '$_selectedDayPendingCount',
                          ),
                          _InsightPill(
                            label: 'Completed',
                            value: '$_selectedDayCompletedCount',
                          ),
                          if (selectedDayWeather != null)
                            _InsightPill(
                              label: _weatherLabel(
                                selectedDayWeather['code'] as int?,
                              ),
                              value:
                                  'H ${((selectedDayWeather['max'] as num?)?.round() ?? 0)}°',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildGlassPanel(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: () {
                              _monthPageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                            icon: const Icon(Icons.chevron_left),
                            tooltip: 'Previous month',
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '${_monthName(_currentDate.month)} ${_currentDate.year}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Swipe the grid or tap the arrows',
                                  style: TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            onPressed: () {
                              _monthPageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                            icon: const Icon(Icons.chevron_right),
                            tooltip: 'Next month',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _CalendarActionButton(
                              icon: Icons.my_location_outlined,
                              label: 'Today',
                              onPressed: _goToToday,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CalendarActionButton(
                              icon: Icons.add_task,
                              label: 'Task',
                              onPressed: () => _openTaskDialog(
                                newTaskSource: 'task',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CalendarActionButton(
                              icon: Icons.download_for_offline_outlined,
                              label: 'Import',
                              onPressed: _openImportDialog,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                            .map(
                              (day) => Expanded(
                                child: Center(
                                  child: Text(
                                    day,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: AppTheme.textMuted,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 332,
                        child: PageView.builder(
                          controller: _monthPageController,
                          onPageChanged: (page) {
                            final now = DateTime.now();
                            final monthOffset = page - 1200;
                            final newDate = DateTime(
                              now.year,
                              now.month + monthOffset,
                              1,
                            );
                            setState(() {
                              _currentDate = newDate;
                            });
                            _loadMonth(showLoader: false);
                          },
                          itemBuilder: (context, page) {
                            final now = DateTime.now();
                            final monthOffset = page - 1200;
                            final pageMonth = DateTime(
                              now.year,
                              now.month + monthOffset,
                              1,
                            );
                            final daysInPageMonth = DateTime(
                              pageMonth.year,
                              pageMonth.month + 1,
                              0,
                            ).day;
                            final firstDay = DateTime(
                                  pageMonth.year,
                                  pageMonth.month,
                                  1,
                                ).weekday %
                                7;

                            return GridView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: daysInPageMonth + firstDay,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                crossAxisSpacing: 4,
                                mainAxisSpacing: 4,
                              ),
                              itemBuilder: (context, index) {
                                if (index < firstDay) {
                                  return const SizedBox.shrink();
                                }
                                final day = index - firstDay + 1;
                                final date = DateTime(
                                  pageMonth.year,
                                  pageMonth.month,
                                  day,
                                );
                                return DayGrid(
                                  day: day,
                                  month: pageMonth.month,
                                  year: pageMonth.year,
                                  isToday: DateUtils.isSameDay(date, today),
                                  isSelected:
                                      DateUtils.isSameDay(date, _selectedDate),
                                  weatherData: _weatherData,
                                  tasks: _visibleTasks
                                      .where(
                                        (task) =>
                                            DateUtils.isSameDay(
                                              task.startDate,
                                              date,
                                            ),
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
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildGlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selected day',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _selectedDateLongLabel,
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedIndex = 1;
                              });
                            },
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Open Today'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _quickTaskController,
                              onSubmitted: (_) => _addQuickTaskForSelectedDay(),
                              decoration: const InputDecoration(
                                labelText: 'Quick to-do',
                                hintText: 'Add something for this day',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed:
                                _isQuickAdding ? null : _addQuickTaskForSelectedDay,
                            child: _isQuickAdding
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (previewTasks.isEmpty)
                        const Text(
                          'Nothing is scheduled for this day yet. Add a task above or tap any date to start planning.',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            height: 1.45,
                          ),
                        )
                      else ...[
                        Text(
                          '${_tasksForSelectedDay.length} item${_tasksForSelectedDay.length == 1 ? '' : 's'} lined up',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        ...previewTasks.map(_buildTaskPreviewRow),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
  }

  Widget _buildDayTabRevamp() {
    final dayTasks = _tasksForSelectedDay;
    final todoTasks = _todoTasksForSelectedDay;
    final agendaTasks = _agendaTasksForSelectedDay;
    final completedTasks = _completedSelectedTasks;
    final nextTask = _nextSelectedTask;
    final selectedDayWeather = _selectedDayWeather;
    final formattedDate =
        '${_monthName(_selectedDate.month)} ${_selectedDate.day}, ${_selectedDate.year}';

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedDayHeroTitle),
        actions: [
          if (!DateUtils.isSameDay(_selectedDate, DateTime.now()))
            IconButton(
              onPressed: _goToToday,
              icon: const Icon(Icons.my_location_outlined),
              tooltip: 'Jump to today',
            ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTaskDialog(),
        label: const Text('Add Item'),
        icon: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadMonth(showLoader: false),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 108),
          children: [
            _buildGlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formattedDate,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dayTasks.isEmpty
                        ? 'A fresh page for the day.'
                        : '${
                            dayTasks.length
                          } items planned with ${(_selectedDayCompletionRatio * 100).round()}% already done.',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _selectedDayCompletionRatio,
                      minHeight: 10,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _InsightPill(label: 'To-do', value: '${todoTasks.length}'),
                      _InsightPill(
                        label: 'Agenda',
                        value: '${agendaTasks.length}',
                      ),
                      _InsightPill(
                        label: 'Done',
                        value: '${completedTasks.length}',
                      ),
                      if (selectedDayWeather != null)
                        _InsightPill(
                          label: _weatherLabel(
                            selectedDayWeather['code'] as int?,
                          ),
                          value:
                              '${((selectedDayWeather['max'] as num?)?.round() ?? 0)}° / ${((selectedDayWeather['min'] as num?)?.round() ?? 0)}°',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildGlassPanel(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 156,
                    child: _CalendarActionButton(
                      icon: Icons.check_circle_outline,
                      label: 'New Task',
                      onPressed: () => _openTaskDialog(newTaskSource: 'task'),
                    ),
                  ),
                  SizedBox(
                    width: 156,
                    child: _CalendarActionButton(
                      icon: Icons.event_outlined,
                      label: 'New Event',
                      onPressed: () => _openTaskDialog(newTaskSource: 'event'),
                    ),
                  ),
                  SizedBox(
                    width: 156,
                    child: _CalendarActionButton(
                      icon: Icons.auto_awesome_outlined,
                      label: 'Ask AI',
                      onPressed: () {
                        setState(() {
                          _selectedIndex = 2;
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 156,
                    child: _CalendarActionButton(
                      icon: Icons.link_outlined,
                      label: 'Import',
                      onPressed: _openImportDialog,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildGlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick to-do',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Capture a task without opening the full editor. It lands on the selected day automatically.',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _quickTaskController,
                          onSubmitted: (_) => _addQuickTaskForSelectedDay(),
                          decoration: const InputDecoration(
                            labelText: 'Task title',
                            hintText: 'Pay rent, call mom, send recap...',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed:
                            _isQuickAdding ? null : _addQuickTaskForSelectedDay,
                        child: _isQuickAdding
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (nextTask != null) ...[
              const SizedBox(height: 14),
              _buildGlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next up',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    _buildTaskPreviewRow(nextTask),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (dayTasks.isEmpty)
              _buildGlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nothing scheduled yet',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use the quick task field above or the add button to start shaping the day.',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              if (todoTasks.isNotEmpty) ...[
                _buildGlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'To-do list',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      ...todoTasks.map(_buildTaskPreviewRow),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (agendaTasks.isNotEmpty) ...[
                _buildGlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agenda',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      ...agendaTasks.map(_buildTaskPreviewRow),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (completedTasks.isNotEmpty)
                _buildGlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Completed',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      ...completedTasks.map(_buildTaskPreviewRow),
                    ],
                  ),
                ),
            ],
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
            onCreateTaskFromSuggestion: (title, description, suggestedTime) async {
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

class _InsightPill extends StatelessWidget {
  const _InsightPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarActionButton extends StatelessWidget {
  const _CalendarActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        foregroundColor: AppTheme.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}
