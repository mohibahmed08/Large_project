import 'package:flutter/material.dart';

class DayGrid extends StatelessWidget {
  const DayGrid({
    super.key,
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.month,
    required this.year,
    required this.taskCount,
    required this.onDayTap,
    this.weatherData,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final int month;
  final int year;
  final int taskCount;
  final Map<String, dynamic>? weatherData;
  final ValueChanged<int> onDayTap;

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
    switch (code) {
      case 0:
        return 'Sunny';
      case 1:
        return 'Mostly';
      case 2:
        return 'Partly';
      case 3:
        return 'Cloudy';
      case 61:
        return 'Rain';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final weatherText = getWeatherText();

    return GestureDetector(
      onTap: () => onDayTap(day),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF12121F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF9C27B0)
                : isToday
                    ? const Color(0xFF64B5F6)
                    : const Color(0xFF2C2C3E),
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
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF64B5F6),
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
              ),
          ],
        ),
      ),
    );
  }
}
