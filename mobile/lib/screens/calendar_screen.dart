import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

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
  final TextEditingController _quickAddController = TextEditingController();
  final PageController _monthPageController = PageController(initialPage: 1200);

  late UserSession _session;
  Timer? _liveActivityTimer;
  StreamSubscription<Map<String, dynamic>>? _notificationOpenSubscription;
  String? _liveActivityId;
  String? _liveActivityTaskId;
  bool _liveActivitySupported = false;
  bool _liveActivityReady = false;
  DateTime _currentDate = DateTime.now();
  DateTime _displayMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  Map<String, dynamic>? _weatherData;
  List<CalendarTask> _tasks = [];
  List<CalendarTask> _visibleTasks = [];
  bool _isLoading = true;
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
    _quickAddController.dispose();
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

  Future<void> _openTaskDialog({
    CalendarTask? task,
    String? newTaskSource,
    String? initialGroup,
    String? initialTitle,
    DateTime? initialDate,
  }) async {
    final baseDate = task?.startDate ?? initialDate ?? _selectedDate;
    final initialEndDate = task?.endDate ??
        (task?.startDate ?? initialDate ?? _selectedDate).add(const Duration(hours: 1));

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


  int get _selectedDayCompletedCount => _completedSelectedTasks.length;


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
  }

  Widget _buildDayTab() {
    return _buildDayTabRevamp();
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
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => setState(() {
                            _displayMonth = DateTime(
                              _displayMonth.year,
                              _displayMonth.month - 1,
                            );
                          }),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => setState(() {
                            _displayMonth = DateTime(
                              _displayMonth.year,
                              _displayMonth.month + 1,
                            );
                          }),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.today_outlined),
                          onPressed: () => setState(() {
                            _displayMonth = DateTime(today.year, today.month);
                            _selectedDate = today;
                          }),
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
                    height: 280,
                    child: PageView.builder(
                      controller: PageController(initialPage: 1200),
                      onPageChanged: (page) {
                        final base = DateTime(today.year, today.month);
                        setState(() {
                          _displayMonth = DateTime(
                            base.year,
                            base.month + (page - 1200),
                          );
                        });
                      },
                      itemBuilder: (context, page) {
                        final base = DateTime(today.year, today.month);
                        final pageMonth = DateTime(
                          base.year,
                          base.month + (page - 1200),
                        );
                        final firstDay = DateTime(pageMonth.year, pageMonth.month, 1).weekday % 7;
                        final daysInMonth =
                            DateTime(pageMonth.year, pageMonth.month + 1, 0).day;
                        final totalCells = firstDay + daysInMonth;
                        final rows = (totalCells / 7).ceil();

                        return GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            childAspectRatio: 0.72,
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
                              isSelected: DateUtils.isSameDay(date, _selectedDate),
                              weatherData: _weatherData,
                              tasks: _visibleTasks
                                  .where((t) => DateUtils.isSameDay(t.startDate, date))
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
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
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
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.12),
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
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
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
                    onPressed: () => _openTaskDialog(initialDate: _selectedDate),
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
                  childCount:
                      todoTasks.where((t) => t.startDate == null).length,
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

  Widget _buildTimelineView(List<CalendarTask> timedTasks) {
    if (timedTasks.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final isToday = DateUtils.isSameDay(_selectedDate, now);

    // Determine visible hour range
    int minHour = 8;
    int maxHour = 18;
    for (final task in timedTasks) {
      if (task.startDate != null) {
        minHour = task.startDate!.hour < minHour ? task.startDate!.hour : minHour;
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
                    Expanded(
                      child: Divider(
                        height: 1,
                        color: AppTheme.border,
                      ),
                    ),
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
                  top: ((task.startDate!.hour + task.startDate!.minute / 60.0) -
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
                        color: _taskDisplayColor(task)
                            .withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _taskDisplayColor(task)
                              .withValues(alpha: 0.50),
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
