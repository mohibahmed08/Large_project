import 'package:flutter/material.dart';

class TaskEditorResult {
  const TaskEditorResult({
    required this.title,
    required this.description,
    required this.location,
    required this.color,
    required this.group,
    required this.startDate,
    required this.endDate,
    required this.reminderEnabled,
    required this.reminderMinutesBefore,
  });

  final String title;
  final String description;
  final String location;
  final String color;
  final String group;
  final DateTime startDate;
  final DateTime endDate;
  final bool reminderEnabled;
  final int reminderMinutesBefore;
}

class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({
    super.key,
    required this.initialTitle,
    required this.initialDescription,
    required this.initialLocation,
    required this.initialColor,
    required this.initialGroup,
    required this.initialStartDate,
    required this.initialEndDate,
    required this.initialReminderEnabled,
    required this.initialReminderMinutesBefore,
    required this.isEditing,
  });

  final String initialTitle;
  final String initialDescription;
  final String initialLocation;
  final String initialColor;
  final String initialGroup;
  final DateTime initialStartDate;
  final DateTime initialEndDate;
  final bool initialReminderEnabled;
  final int initialReminderMinutesBefore;
  final bool isEditing;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _locationController;
  late final TextEditingController _groupController;
  late DateTime _startDate;
  late DateTime _endDate;
  late bool _reminderEnabled;
  late int _reminderMinutesBefore;
  static const List<int> _reminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440];
  static const List<String> _colorOptions = [
    '',
    '#60A5FA',
    '#F97316',
    '#22C55E',
    '#EAB308',
    '#A855F7',
    '#EF4444',
    '#14B8A6',
  ];
  late String _selectedColor;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController =
        TextEditingController(text: widget.initialDescription);
    _locationController = TextEditingController(text: widget.initialLocation);
    _groupController = TextEditingController(text: widget.initialGroup);
    _startDate = widget.initialStartDate;
    _endDate = widget.initialEndDate.isBefore(widget.initialStartDate)
        ? widget.initialStartDate
        : widget.initialEndDate;
    _reminderEnabled = widget.initialReminderEnabled;
    _reminderMinutesBefore = widget.initialReminderMinutesBefore;
    _selectedColor = _colorOptions.contains(widget.initialColor.toUpperCase())
        ? widget.initialColor.toUpperCase()
        : '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      final updated = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );

      if (isStart) {
        _startDate = updated;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = updated.isBefore(_startDate) ? _startDate : updated;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _startDate : _endDate;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      final updated = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );

      if (isStart) {
        _startDate = updated;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = updated.isBefore(_startDate) ? _startDate : updated;
      }
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a title for the task.')),
      );
      return;
    }

    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time cannot be before start time.')),
      );
      return;
    }

    Navigator.pop(
      context,
      TaskEditorResult(
        title: title,
        description: _descriptionController.text.trim(),
        location: _locationController.text.trim(),
        color: _selectedColor,
        group: _groupController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        reminderEnabled: _reminderEnabled,
        reminderMinutesBefore: _reminderMinutesBefore,
      ),
    );
  }

  String _reminderLabel(int minutes) {
    if (minutes == 0) {
      return 'At time of event';
    }
    if (minutes == 60) {
      return '1 hour before';
    }
    if (minutes == 1440) {
      return '1 day before';
    }
    if (minutes > 60 && minutes % 60 == 0) {
      return '${minutes ~/ 60} hours before';
    }
    return '$minutes minutes before';
  }

  String _formatDate(DateTime value) {
    return '${value.month}/${value.day}/${value.year}';
  }

  String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Color _chipColor(String hex) {
    if (hex.isEmpty) {
      return const Color(0xFF334155);
    }

    final normalized = hex.replaceFirst('#', '');
    final value = int.tryParse(normalized, radix: 16);
    if (value == null) {
      return const Color(0xFF334155);
    }

    return Color(normalized.length == 6 ? 0xFF000000 | value : value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Task' : 'Add Task'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              minLines: 3,
              maxLines: 5,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Location'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _groupController,
              decoration: const InputDecoration(
                labelText: 'Group',
                hintText: 'School, Work, Personal...',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 20),
            Text(
              'Task color',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _colorOptions.map((option) {
                final isSelected = _selectedColor == option;
                final fill = _chipColor(option);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = option;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.18),
                        width: isSelected ? 2.4 : 1.2,
                      ),
                    ),
                    child: option.isEmpty
                        ? const Icon(Icons.block, color: Colors.white70, size: 18)
                        : isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text(
              'Start',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isStart: true),
                    child: Text(_formatDate(_startDate)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(isStart: true),
                    child: Text(_formatTime(_startDate)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'End',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isStart: false),
                    child: Text(_formatDate(_endDate)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(isStart: false),
                    child: Text(_formatTime(_endDate)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Email reminder'),
              subtitle: const Text('Send a reminder email before this task.'),
              value: _reminderEnabled,
              onChanged: (value) {
                setState(() {
                  _reminderEnabled = value;
                });
              },
            ),
            if (_reminderEnabled) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _reminderOptions.contains(_reminderMinutesBefore)
                    ? _reminderMinutesBefore
                    : 30,
                decoration: const InputDecoration(
                  labelText: 'Reminder timing',
                ),
                items: _reminderOptions
                    .map(
                      (minutes) => DropdownMenuItem<int>(
                        value: minutes,
                        child: Text(_reminderLabel(minutes)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _reminderMinutesBefore = value;
                  });
                },
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: Text(widget.isEditing ? 'Save Changes' : 'Create Task'),
            ),
          ],
        ),
      ),
    );
  }
}
