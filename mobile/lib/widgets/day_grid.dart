import 'package:flutter/material.dart';

import '../models/task_model.dart';
import '../theme/app_theme.dart';

class DayGrid extends StatelessWidget {
  const DayGrid({
    super.key,
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.month,
    required this.year,
    required this.tasks,
    required this.onDayTap,
    this.weatherData,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final int month;
  final int year;
  final List<CalendarTask> tasks;
  final Map<String, dynamic>? weatherData;
  final ValueChanged<int> onDayTap;

  int get taskCount => tasks.length;

  String getWeatherText() {
    if (weatherData == null) {
      return '';
    }

    try {
      final List codes = weatherData!['hourly']['weathercode'];
      final today = DateUtils.dateOnly(DateTime.now());
      final cellDate = DateTime(year, month, day);
      final diffDays = cellDate.difference(today).inDays;

      if (diffDays < 0) {
        return '';
      }
      if ((diffDays * 24 + 24) > codes.length) {
        return '';
      }

      final start = diffDays * 24;
      final dayCodes = codes.sublist(start, start + 24);
      final count = <int, int>{};

      for (final code in dayCodes) {
        count[code as int] = (count[code] ?? 0) + 1;
      }

      var mostCommon = dayCodes.first as int;
      var maxCount = 0;
      count.forEach((key, value) {
        if (value > maxCount) {
          maxCount = value;
          mostCommon = key;
        }
      });

      return weatherCodeToText(mostCommon);
    } catch (_) {
      return '';
    }
  }

  String weatherCodeToText(int code) {
    if (code == 0) return 'Sunny';
    if (code == 1) return 'Mostly';
    if (code == 2) return 'Partly';
    if (code == 3) return 'Cloudy';
    if (code == 45 || code == 48) return 'Foggy';
    if (code == 51 || code == 53 || code == 55) return 'Drizzle';
    if (code == 56 || code == 57) return 'Ice';
    if (code == 61 || code == 63 || code == 65) return 'Rain';
    if (code == 66 || code == 67) return 'Sleet';
    if (code == 71 || code == 73 || code == 75) return 'Snow';
    if (code == 77) return 'Flurries';
    if (code == 80 || code == 81 || code == 82) return 'Showers';
    if (code == 85 || code == 86) return 'Snow';
    if (code == 95) return 'Storm';
    if (code == 96 || code == 99) return 'Hail';
    return '';
  }

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
        return const Color(0xFF60A5FA); // blue – matches web accent
    }
  }

  Color _groupMajorityColor(List<CalendarTask> tasks) {
    final counts = <int, int>{};
    for (final task in tasks) {
      final normalized = task.color.trim().replaceFirst('#', '');
      final parsed = int.tryParse(normalized, radix: 16);
      if (parsed == null || (normalized.length != 6 && normalized.length != 8)) {
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
    final weatherText = getWeatherText();
    final groupColor = taskCount > 0 ? _groupMajorityColor(tasks) : const Color(0xFF64B5F6);
    final previewColors = <Color>[];
    for (final task in tasks) {
      final color = _taskDisplayColor(task, groupColor);
      if (previewColors.any((existing) => existing.value == color.value)) {
        continue;
      }
      previewColors.add(color);
      if (previewColors.length == 3) {
        break;
      }
    }

    return GestureDetector(
      onTap: () => onDayTap(day),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF12121F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppTheme.accent           // blue – consistent with theme
                : isToday
                    ? AppTheme.accentStrong // stronger blue for today
                    : AppTheme.border,
            width: isSelected || isToday ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            if (weatherText.isNotEmpty)
              Positioned(
                top: 6,
                left: 8,
                child: Text(
                  weatherText,
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ),
            Positioned(
              top: 6,
              right: 8,
              child: Text(
                '$day',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (taskCount > 0)
              Positioned(
                bottom: 6,
                left: 8,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: groupColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$taskCount',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ...previewColors.take(3).map(
                      (color) => Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (taskCount > 0)
              Positioned(
                bottom: 6,
                right: 8,
                child: Text(
                  tasks.first.group.isNotEmpty
                      ? tasks.first.group
                      : tasks.first.source.toUpperCase(),
                  style: const TextStyle(fontSize: 8, color: Colors.white54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
