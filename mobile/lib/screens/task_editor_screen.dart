import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum TaskEditorAction { save, delete }

class TaskEditorResult {
  const TaskEditorResult({
    required this.action,
    required this.title,
    required this.description,
    required this.location,
    required this.color,
    required this.group,
    required this.startDate,
    required this.endDate,
    required this.reminderEnabled,
    required this.reminderMinutesBefore,
    required this.reminderDelivery,
  });

  final TaskEditorAction action;
  final String title;
  final String description;
  final String location;
  final String color;
  final String group;
  final DateTime startDate;
  final DateTime endDate;
  final bool reminderEnabled;
  final int reminderMinutesBefore;
  final String reminderDelivery;
}

class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({
    super.key,
    required this.initialTitle,
    required this.initialDescription,
    required this.initialLocation,
    required this.initialColor,
    required this.initialGroup,
    required this.existingGroups,
    required this.initialStartDate,
    required this.initialEndDate,
    required this.initialReminderEnabled,
    required this.initialReminderMinutesBefore,
    required this.initialReminderDelivery,
    required this.isEditing,
  });

  final String initialTitle;
  final String initialDescription;
  final String initialLocation;
  final String initialColor;
  final String initialGroup;
  final List<String> existingGroups;
  final DateTime initialStartDate;
  final DateTime initialEndDate;
  final bool initialReminderEnabled;
  final int initialReminderMinutesBefore;
  final String initialReminderDelivery;
  final bool isEditing;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _locationController;
  late final TextEditingController _groupController;
  late final TextEditingController _customColorController;
  late DateTime _startDate;
  late DateTime _endDate;
  late bool _reminderEnabled;
  late int _reminderMinutesBefore;
  late String _reminderDelivery;
  static const List<int> _reminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440];
  static const List<String> _reminderDeliveryOptions = [
    'email',
    'push',
    'both',
  ];
  static const List<String> _colorOptions = [
    '',
    '#60A5FA',
    '#F97316',
    '#22C55E',
    '#EAB308',
    '#A855F7',
    '#EF4444',
    '#14B8A6',
    '#0EA5E9',
    '#F43F5E',
    '#84CC16',
    '#FACC15',
    '#2DD4BF',
    '#818CF8',
  ];
  late String _selectedColor;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _locationController = TextEditingController(text: widget.initialLocation);
    _groupController = TextEditingController(text: widget.initialGroup);
    _startDate = widget.initialStartDate;
    _endDate = widget.initialEndDate.isBefore(widget.initialStartDate)
        ? widget.initialStartDate
        : widget.initialEndDate;
    _reminderEnabled = widget.initialReminderEnabled;
    _reminderMinutesBefore = widget.initialReminderMinutesBefore;
    _reminderDelivery =
        _reminderDeliveryOptions.contains(widget.initialReminderDelivery)
        ? widget.initialReminderDelivery
        : 'email';
    _selectedColor = _colorOptions.contains(widget.initialColor.toUpperCase())
        ? widget.initialColor.toUpperCase()
        : '';
    _customColorController = TextEditingController(text: _selectedColor);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _groupController.dispose();
    _customColorController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startDate : _endDate;
    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (sheetContext) {
        var draft = current;
        return _GlassDatePickerSheet(
          initialValue: current,
          minimumDate: DateTime(2020),
          maximumDate: DateTime(2100),
          onChanged: (value) {
            draft = DateTime(
              value.year,
              value.month,
              value.day,
              current.hour,
              current.minute,
            );
          },
          onCancel: () => Navigator.pop(sheetContext),
          onConfirm: () => Navigator.pop(sheetContext, draft),
        );
      },
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = picked.isBefore(_startDate) ? _startDate : picked;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _startDate : _endDate;
    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (sheetContext) {
        var draft = current;
        return _GlassTimePickerSheet(
          initialValue: current,
          onChanged: (value) {
            draft = DateTime(
              current.year,
              current.month,
              current.day,
              value.hour,
              value.minute,
            );
          },
          onCancel: () => Navigator.pop(sheetContext),
          onConfirm: () => Navigator.pop(sheetContext, draft),
        );
      },
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = picked.isBefore(_startDate) ? _startDate : picked;
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

    final normalizedColor = _normalizeColor(_customColorController.text);

    Navigator.pop(
      context,
      TaskEditorResult(
        action: TaskEditorAction.save,
        title: title,
        description: _descriptionController.text.trim(),
        location: _locationController.text.trim(),
        color: normalizedColor,
        group: _groupController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        reminderEnabled: _reminderEnabled,
        reminderMinutesBefore: _reminderMinutesBefore,
        reminderDelivery: _reminderDelivery,
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete item?'),
        content: const Text(
          'This will permanently remove this item from your calendar.',
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

    Navigator.pop(
      context,
      TaskEditorResult(
        action: TaskEditorAction.delete,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        location: _locationController.text.trim(),
        color: _normalizeColor(_customColorController.text),
        group: _groupController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        reminderEnabled: _reminderEnabled,
        reminderMinutesBefore: _reminderMinutesBefore,
        reminderDelivery: _reminderDelivery,
      ),
    );
  }

  String _reminderDeliveryLabel(String value) {
    switch (value) {
      case 'push':
        return 'Push notification';
      case 'both':
        return 'Email and push';
      case 'email':
      default:
        return 'Email only';
    }
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

  String _normalizeColor(String value) {
    final normalized = value.trim().toUpperCase();
    if (RegExp(r'^#[0-9A-F]{6}([0-9A-F]{2})?$').hasMatch(normalized)) {
      return normalized;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isEditing ? 'Edit Task' : 'Add Task')),
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
            if (widget.existingGroups.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue:
                    widget.existingGroups.contains(_groupController.text)
                    ? _groupController.text
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Use an existing group',
                ),
                borderRadius: BorderRadius.circular(20),
                dropdownColor: const Color(0xFF182235),
                icon: const Icon(CupertinoIcons.chevron_down, size: 18),
                menuMaxHeight: 280,
                style: _dropdownTextStyle(context),
                items: widget.existingGroups
                    .map(
                      (group) => DropdownMenuItem<String>(
                        value: group,
                        child: Text(group),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _groupController.text = value;
                  });
                },
              ),
            ],
            const SizedBox(height: 24),
            Text('Task color', style: Theme.of(context).textTheme.titleMedium),
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
                      _customColorController.text = option;
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
                        ? const Icon(
                            Icons.block,
                            color: Colors.white70,
                            size: 18,
                          )
                        : isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text('Start', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isStart: true),
                    style: _dateTimeButtonStyle(context),
                    child: Text(_formatDate(_startDate)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(isStart: true),
                    style: _dateTimeButtonStyle(context),
                    child: Text(_formatTime(_startDate)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('End', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isStart: false),
                    style: _dateTimeButtonStyle(context),
                    child: Text(_formatDate(_endDate)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(isStart: false),
                    style: _dateTimeButtonStyle(context),
                    child: Text(_formatTime(_endDate)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Reminder',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Send a reminder before this task starts.',
                          style: TextStyle(color: Colors.white70, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Transform.scale(
                    scale: 0.94,
                    child: CupertinoSwitch(
                      value: _reminderEnabled,
                      activeTrackColor: AppTheme.accent,
                      onChanged: (value) {
                        setState(() {
                          _reminderEnabled = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_reminderEnabled) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _reminderOptions.contains(_reminderMinutesBefore)
                    ? _reminderMinutesBefore
                    : 30,
                decoration: const InputDecoration(labelText: 'Reminder timing'),
                borderRadius: BorderRadius.circular(20),
                dropdownColor: const Color(0xFF182235),
                icon: const Icon(CupertinoIcons.chevron_down, size: 18),
                menuMaxHeight: 280,
                style: _dropdownTextStyle(context),
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
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _reminderDelivery,
                decoration: const InputDecoration(
                  labelText: 'Reminder delivery',
                ),
                borderRadius: BorderRadius.circular(20),
                dropdownColor: const Color(0xFF182235),
                icon: const Icon(CupertinoIcons.chevron_down, size: 18),
                menuMaxHeight: 280,
                style: _dropdownTextStyle(context),
                items: _reminderDeliveryOptions
                    .map(
                      (value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(_reminderDeliveryLabel(value)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _reminderDelivery = value;
                  });
                },
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _customColorController,
              decoration: const InputDecoration(
                labelText: 'Custom hex color',
                hintText: '#60A5FA',
              ),
              onChanged: (value) {
                setState(() {
                  _selectedColor = value.trim().toUpperCase();
                });
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: Text(widget.isEditing ? 'Save Changes' : 'Create Task'),
            ),
            if (widget.isEditing) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  ButtonStyle _dateTimeButtonStyle(BuildContext context) {
    return OutlinedButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    );
  }

  TextStyle _dropdownTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodyLarge!.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );
  }
}

class _GlassTimePickerSheet extends StatelessWidget {
  const _GlassTimePickerSheet({
    required this.initialValue,
    required this.onChanged,
    required this.onCancel,
    required this.onConfirm,
  });

  final DateTime initialValue;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 320,
            decoration: BoxDecoration(
              color: const Color(0xFF101828).withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 2),
                    child: Container(
                      width: 38,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                    child: Row(
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          onPressed: onCancel,
                          child: const Text(
                            'Cancel',
                            style: TextStyle(decoration: TextDecoration.none),
                          ),
                        ),
                        const Spacer(),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          onPressed: onConfirm,
                          child: const Text(
                            'Done',
                            style: TextStyle(decoration: TextDecoration.none),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: CupertinoTheme(
                      data: CupertinoThemeData(
                        brightness: Brightness.dark,
                        primaryColor: AppTheme.accent,
                        textTheme: CupertinoTextThemeData(
                          dateTimePickerTextStyle: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                          ),
                        ),
                      ),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.time,
                        initialDateTime: initialValue,
                        use24hFormat: false,
                        onDateTimeChanged: onChanged,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassDatePickerSheet extends StatelessWidget {
  const _GlassDatePickerSheet({
    required this.initialValue,
    required this.minimumDate,
    required this.maximumDate,
    required this.onChanged,
    required this.onCancel,
    required this.onConfirm,
  });

  final DateTime initialValue;
  final DateTime minimumDate;
  final DateTime maximumDate;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 320,
            decoration: BoxDecoration(
              color: const Color(0xFF101828).withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 2),
                    child: Container(
                      width: 38,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                    child: Row(
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          onPressed: onCancel,
                          child: const Text(
                            'Cancel',
                            style: TextStyle(decoration: TextDecoration.none),
                          ),
                        ),
                        const Spacer(),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          onPressed: onConfirm,
                          child: const Text(
                            'Done',
                            style: TextStyle(decoration: TextDecoration.none),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: CupertinoTheme(
                      data: CupertinoThemeData(
                        brightness: Brightness.dark,
                        primaryColor: AppTheme.accent,
                        textTheme: CupertinoTextThemeData(
                          dateTimePickerTextStyle: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                          ),
                        ),
                      ),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.date,
                        initialDateTime: initialValue,
                        minimumDate: minimumDate,
                        maximumDate: maximumDate,
                        onDateTimeChanged: onChanged,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
