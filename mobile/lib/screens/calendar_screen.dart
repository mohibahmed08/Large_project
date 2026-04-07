import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/task_model.dart';
import '../models/user_model.dart';
import '../services/calendar_service.dart';
import '../theme/app_theme.dart';
import '../widgets/day_grid.dart';
import 'ai_screen.dart';
import 'login_screen.dart';
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
  final CalendarService _calendarService = CalendarService();
  final TextEditingController _searchController = TextEditingController();

  late UserSession _session;
  DateTime _currentDate = DateTime.now();
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  Map<String, dynamic>? _weatherData;
  List<CalendarTask> _tasks = [];
  List<CalendarTask> _visibleTasks = [];
  bool _isLoading = true;
  bool _isSearching = false;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _loadMonth(showLoader: true);
    _fetchWeather();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        _session = result.session;
        _tasks = result.tasks;
        _visibleTasks = result.tasks;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (!mounted) {
        return;
      }
      if (showLoader) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchWeather() async {
    try {
      final today = DateTime.now();
      final start = _formatDate(today);
      final end = _formatDate(today.add(const Duration(days: 10)));
      final response = await http.get(
        Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=28.5383&longitude=-81.3792&start_date=$start&end_date=$end&hourly=weathercode',
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
        _session = result.session;
        _visibleTasks = result.tasks;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _openTaskDialog({CalendarTask? task}) async {
    final baseDate = task?.startDate ?? _selectedDate;

    final result = await Navigator.push<TaskEditorResult>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskEditorScreen(
          initialTitle: task?.title ?? '',
          initialDescription: task?.description ?? '',
          baseDate: baseDate,
          isEditing: task != null,
        ),
      ),
    );

    if (result == null || result.title.isEmpty) {
      return;
    }

    final startDate = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      task?.startDate?.hour ?? 12,
      task?.startDate?.minute ?? 0,
    );

    try {
      _session = await _calendarService.saveTask(
        session: _session,
        taskId: task?.id,
        title: result.title,
        description: result.description,
        startDate: startDate,
        isCompleted: task?.isCompleted ?? false,
      );

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
      _session = await _calendarService.saveTask(
        session: _session,
        taskId: task.id,
        title: task.title,
        description: task.description,
        startDate: task.startDate,
        isCompleted: value,
      );
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
      _session = importResult.$1;
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

  void _openAiScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIScreen(
          initialSession: _session,
          selectedDate: _selectedDate,
          onSessionUpdated: (session) {
            _session = session;
          },
          onCreateTaskFromSuggestion: (title, description, suggestedTime) async {
            final startDate = _dateWithTime(_selectedDate, suggestedTime);
            _session = await _calendarService.saveTask(
              session: _session,
              title: title,
              description: description,
              startDate: startDate,
            );
            await _loadMonth();
          },
        ),
      ),
    );
  }

  void _logout() {
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

  int _taskCountForDay(int day) {
    final date = DateTime(_currentDate.year, _currentDate.month, day);
    return _tasks.where((task) => DateUtils.isSameDay(task.startDate, date)).length;
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateTime(_currentDate.year, _currentDate.month + 1, 0).day;
    final firstDayOfMonth =
        DateTime(_currentDate.year, _currentDate.month, 1).weekday % 7;
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Calendar - ${_session.firstName.isEmpty ? _session.userId : _session.firstName}',
        ),
        actions: [
          IconButton(
            onPressed: _openImportDialog,
            icon: const Icon(Icons.link),
            tooltip: 'Connect calendar',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadMonth(showLoader: false),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _currentDate = DateTime(
                                      _currentDate.year,
                                      _currentDate.month - 1,
                                    );
                                  });
                                  _loadMonth(showLoader: true);
                                },
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Text(
                                '${_monthName(_currentDate.month)} ${_currentDate.year}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _currentDate = DateTime(
                                      _currentDate.year,
                                      _currentDate.month + 1,
                                    );
                                  });
                                  _loadMonth(showLoader: true);
                                },
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
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
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: daysInMonth + firstDayOfMonth,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              crossAxisSpacing: 4,
                              mainAxisSpacing: 4,
                            ),
                            itemBuilder: (context, index) {
                              if (index < firstDayOfMonth) {
                                return const SizedBox.shrink();
                              }

                              final day = index - firstDayOfMonth + 1;
                              final date = DateTime(
                                _currentDate.year,
                                _currentDate.month,
                                day,
                              );

                              return DayGrid(
                                day: day,
                                month: _currentDate.month,
                                year: _currentDate.year,
                                isToday: DateUtils.isSameDay(date, today),
                                isSelected: DateUtils.isSameDay(
                                  date,
                                  _selectedDate,
                                ),
                                weatherData: _weatherData,
                                taskCount: _taskCountForDay(day),
                                onDayTap: (selectedDay) {
                                  setState(() {
                                    _selectedDate = DateTime(
                                      _currentDate.year,
                                      _currentDate.month,
                                      selectedDay,
                                    );
                                  });
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
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
                                  'Tasks for ${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                onPressed: () => _openTaskDialog(),
                                icon: const Icon(Icons.add_circle_outline),
                                tooltip: 'Add task',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_tasksForSelectedDay.isEmpty)
                            const Text(
                              'No tasks scheduled for this day.',
                              style: TextStyle(color: AppTheme.textMuted),
                            )
                          else
                            ..._tasksForSelectedDay.map(
                              (task) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: AppTheme.surfaceAlt.withValues(alpha: 0.6),
                                child: ListTile(
                                  onTap: () => _openTaskDialog(task: task),
                                  leading: Checkbox(
                                    value: task.isCompleted,
                                    onChanged: (value) {
                                      if (value != null) {
                                        _toggleTask(task, value);
                                      }
                                    },
                                  ),
                                  title: Text(
                                    task.title.isEmpty ? '(Untitled)' : task.title,
                                  ),
                                  subtitle: Text(
                                    [
                                      if (task.description.isNotEmpty)
                                        task.description,
                                      if (task.startDate != null)
                                        'Starts ${task.startDate!.hour.toString().padLeft(2, '0')}:${task.startDate!.minute.toString().padLeft(2, '0')}',
                                      if (task.location.isNotEmpty) task.location,
                                      if (task.source.isNotEmpty)
                                        'Source: ${task.source}',
                                    ].join('\n'),
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                      height: 1.35,
                                    ),
                                  ),
                                  isThreeLine: true,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _selectedIndex == 0 ? () => _openTaskDialog() : _openAiScreen,
        label: Text(_selectedIndex == 0 ? 'Add Task' : 'Open AI'),
        icon: Icon(_selectedIndex == 0 ? Icons.add : Icons.smart_toy),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
          if (index == 1) {
            _openAiScreen();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy),
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
}
