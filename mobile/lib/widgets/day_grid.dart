import 'package:flutter/material.dart';

import '../models/task_model.dart';
import '../theme/app_theme.dart';

class DayGrid extends StatelessWidget {
  const DayGrid({
    super.key,
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.tasks,
    required this.onDayTap,
    this.weatherData,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final List<CalendarTask> tasks;
  final Map<String, dynamic>? weatherData;
  final ValueChanged<int> onDayTap;

  int get taskCount => tasks.length;

  Color _taskBaseColor(CalendarTask task) {
    final normalized = task.color.trim().replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed != null && (normalized.length == 6 || normalized.length == 8)) {
      return Color(normalized.length == 6 ? 0xFF000000 | parsed : parsed);
    }

    switch (task.source.toLowerCase()) {
      case 'ical':
        return const Color(0xFF94A3B8); // slate – matches web
      case 'task':
        return const Color(0xFF22C55E); // green – matches web
      case 'plan':
        return const Color(0xFFA855F7); // purple – matches web
      case 'event':
      default:
        return AppTheme.accent;
    }
  }

  Color _groupMajorityColor(List<CalendarTask> tasks) {
    final counts = <int, int>{};
    for (final task in tasks) {
      final normalized = task.color.trim().replaceFirst('#', '');
      final parsed = int.tryParse(normalized, radix: 16);
      if (parsed == null ||
          (normalized.length != 6 && normalized.length != 8)) {
        continue;
      }
      final colorValue = normalized.length == 6 ? 0xFF000000 | parsed : parsed;
      counts.update(colorValue, (value) => value + 1, ifAbsent: () => 1);
    }

    if (counts.isNotEmpty) {
      final winner = counts.entries.reduce(
        (best, next) => next.value > best.value ? next : best,
      );
      return Color(winner.key);
    }

    return _taskBaseColor(tasks.first);
  }

  Color _taskDisplayColor(CalendarTask task, Color groupColor) {
    final normalized = task.color.trim().replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed != null && (normalized.length == 6 || normalized.length == 8)) {
      return Color(normalized.length == 6 ? 0xFF000000 | parsed : parsed);
    }

    return groupColor;
  }

  @override
  Widget build(BuildContext context) {
    final groupColor = taskCount > 0
        ? _groupMajorityColor(tasks)
        : AppTheme.accent;
    final previewColors = <Color>[];
    for (final task in tasks) {
      final color = _taskDisplayColor(task, groupColor);
      if (previewColors.any(
        (existing) => existing.toARGB32() == color.toARGB32(),
      )) {
        continue;
      }
      previewColors.add(color);
      if (previewColors.length == 3) {
        break;
      }
    }

    // Keep the month grid light so the themed background stays visible.
    return GestureDetector(
      onTap: () => onDayTap(day),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isSelected
              ? Border.all(color: AppTheme.accent, width: 1.8)
              : isToday
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1.2,
                )
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected || isToday
                      ? FontWeight.w800
                      : FontWeight.w600,
                  color: isSelected
                      ? const Color(0xFF8BD9FF)
                      : Colors.white.withValues(alpha: isToday ? 0.96 : 0.9),
                ),
              ),
            ),
            const SizedBox(height: 5),
            if (previewColors.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: previewColors
                    .take(3)
                    .map(
                      (c) => Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                    .toList(),
              )
            else
              const SizedBox(height: 9),
          ],
        ),
      ),
    );
  }
}
