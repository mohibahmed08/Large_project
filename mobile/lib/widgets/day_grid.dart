import 'package:flutter/material.dart';
import '../screens/day_detail_screen.dart';

class DayGrid extends StatelessWidget {
  final int day;
  final bool isToday;
  final int month;
  final int year;
  final Map<String, dynamic>? weatherData;

  const DayGrid({
    super.key,
    required this.day,
    required this.isToday,
    required this.month,
    required this.year,
    this.weatherData,
  });

  // ================= WEATHER =================
  String getWeatherText() {
    if (weatherData == null) return "";

    try {
      final List codes = weatherData!["hourly"]["weathercode"];

      // 🔥 API starts from TODAY
      final DateTime today = DateTime.now();

      // 🔥 Current cell date
      final DateTime cellDate = DateTime(year, month, day);

      // 🔥 Difference in days from API start
      final int diffDays = cellDate.difference(today).inDays;

      // ❌ Outside available range
      if (diffDays < 0) return "";
      if ((diffDays * 24 + 24) > codes.length) return "";

      final int start = diffDays * 24;
      final int end = start + 24;

      final List dayCodes = codes.sublist(start, end);

      // 🔥 Find most common weather
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

  // ================= WEATHER TEXT =================
  String weatherCodeToText(int code) {
    switch (code) {
      case 0:
        return "Sunny";
      case 1:
        return "Mostly Clear";
      case 2:
        return "Partly Cloudy";
      case 3:
        return "Cloudy";
      case 61:
      case 63:
      case 65:
        return "Rain";
      case 71:
      case 73:
      case 75:
        return "Snow";
      default:
        return "";
    }
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    final weatherText = getWeatherText();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DayDetailScreen(
              day: day,
              month: month,
              year: year,
            ),
          ),
        );
      },

      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF12121f),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isToday ? const Color(0xFF64b5f6) : const Color(0xFF2c2c3e),
            width: isToday ? 2 : 1,
          ),

          // 🔥 subtle glow like your web app
          boxShadow: isToday
              ? [
                  BoxShadow(
                    color: const Color(0xFF64b5f6).withOpacity(0.2),
                    blurRadius: 6,
                  )
                ]
              : [],
        ),

        child: Stack(
          children: [
            // WEATHER TEXT (TOP LEFT)
            if (weatherText.isNotEmpty)
              Positioned(
                top: 6,
                left: 8,
                child: Text(
                  weatherText,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            // DAY NUMBER (TOP RIGHT)
            Positioned(
              top: 6,
              right: 8,
              child: Text(
                "$day",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}