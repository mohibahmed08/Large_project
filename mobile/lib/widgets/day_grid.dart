import 'package:flutter/material.dart';

class DayGrid extends StatelessWidget {
  final int day;
  final bool isToday;
  final int month;
  final int year;
  final Map<String, dynamic>? weatherData;
  final Function(int) onDayTap;

  const DayGrid({
    super.key,
    required this.day,
    required this.isToday,
    required this.month,
    required this.year,
    required this.onDayTap,
    this.weatherData,
  });

  String getWeatherText() {
    if (weatherData == null) return "";

    try {
      final List codes = weatherData!["hourly"]["weathercode"];

      final DateTime today = DateTime.now();
      final DateTime cellDate = DateTime(year, month, day);

      final int diffDays = cellDate.difference(today).inDays;

      if (diffDays < 0) return "";
      if ((diffDays * 24 + 24) > codes.length) return "";

      final int start = diffDays * 24;
      final int end = start + 24;

      final List dayCodes = codes.sublist(start, end);

      final Map<int, int> count = {};

      for (var c in dayCodes) {
        count[c] = (count[c] ?? 0) + 1;
      }

      int mostCommon = dayCodes[0];
      int maxCount = 0;

      count.forEach((key, value) {
        if (value > maxCount) {
          maxCount = value;
          mostCommon = key;
        }
      });

      return weatherCodeToText(mostCommon);
    } catch (e) {
      return "";
    }
  }

  String weatherCodeToText(int code) {
    switch (code) {
      case 0:
        return "Sunny";
      case 1:
        return "Mostly";
      case 2:
        return "Partly";
      case 3:
        return "Cloudy";
      case 61:
        return "Rain";
      default:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    final weatherText = getWeatherText();

    return GestureDetector(
      onTap: () => onDayTap(day),

      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF12121f),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isToday ? const Color(0xFF64b5f6) : const Color(0xFF2c2c3e),
            width: isToday ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),

        child: Stack(
          children: [
            if (weatherText.isNotEmpty)
              Positioned(
                top: 6,
                left: 8,
                child: Text(
                  weatherText,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white70,
                  ),
                ),
              ),

            Positioned(
              top: 6,
              right: 8,
              child: Text(
                "$day",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}