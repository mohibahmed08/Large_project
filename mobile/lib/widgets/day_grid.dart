import 'package:flutter/material.dart';
import '../screens/day_detail_screen.dart';

class DayGrid extends StatelessWidget {
  final int day;
  final bool isToday;
  final int month;
  final int year;
  final Map<String, dynamic>? weatherData;

  DayGrid({
    required this.day,
    required this.isToday,
    required this.month,
    required this.year,
    this.weatherData,
  });

  String getWeatherText() {
    if (weatherData == null) return "";

    try {
      List codes = weatherData!["hourly"]["weathercode"];

      int start = (day - 1) * 24;
      int end = start + 24;

      if (end > codes.length) return "";

      List dayCodes = codes.sublist(start, end);

      Map<int, int> count = {};

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
      case 2:
      case 3:
        return "Cloudy";
      case 61:
      case 63:
        return "Rain";
      default:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
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
          color: Color(0xFF12121f),
          border: Border.all(
            color: isToday ? Color(0xFF64b5f6) : Color(0xFF2c2c3e),
            width: isToday ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            // WEATHER
            Positioned(
              top: 8,
              left: 10,
              child: Text(
                getWeatherText(),
                style: TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ),

            // DAY NUMBER
            Positioned(
              top: 8,
              right: 10,
              child: Text(
                '$day',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}