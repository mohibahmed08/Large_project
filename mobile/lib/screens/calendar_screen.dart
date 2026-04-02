import 'package:flutter/material.dart';
import '../widgets/day_grid.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CalendarScreen extends StatefulWidget {
  @override
  _CalendarScreenState createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime currentDate = DateTime.now();
  Map<String, dynamic>? weatherData;

  @override
  void initState() {
    super.initState();
    fetchWeather();
  }

  Future<void> fetchWeather() async {
    final url = Uri.parse(
        "https://api.open-meteo.com/v1/forecast?latitude=28.5383&longitude=-81.3792&hourly=weathercode");

    final response = await http.get(url);

    if (response.statusCode == 200) {
      setState(() {
        weatherData = jsonDecode(response.body);
      });
    } else {
      print("Failed to load weather");
    }
  }

  void goToNextMonth() {
    setState(() {
      currentDate = DateTime(currentDate.year, currentDate.month + 1);
    });
  }

  void goToPreviousMonth() {
    setState(() {
      currentDate = DateTime(currentDate.year, currentDate.month - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateTime(currentDate.year, currentDate.month + 1, 0).day;

    final firstDayOfMonth =
        DateTime(currentDate.year, currentDate.month, 1).weekday % 7;

    final today = DateTime.now();

    return Scaffold(
      backgroundColor: Color(0xFF1e1e2f),
      appBar: AppBar(
        title: Text('Calendar'),
        backgroundColor: Colors.grey[200],
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // HEADER
          Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: goToPreviousMonth,
                  child: Text(
                    "←",
                    style: TextStyle(fontSize: 22, color: Colors.white),
                  ),
                ),
                SizedBox(width: 20),
                Text(
                  "${_getMonthName(currentDate.month)} ${currentDate.year}",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                SizedBox(width: 20),
                GestureDetector(
                  onTap: goToNextMonth,
                  child: Text(
                    "→",
                    style: TextStyle(fontSize: 22, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),

          // WEEKDAYS
          Row(
            children: ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
                .map((day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ))
                .toList(),
          ),

          SizedBox(height: 8),

          // GRID
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: GridView.builder(
                itemCount: daysInMonth + firstDayOfMonth,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  if (index < firstDayOfMonth) return SizedBox();

                  int day = index - firstDayOfMonth + 1;

                  return DayGrid(
                    day: day,
                    isToday: day == today.day &&
                        currentDate.month == today.month &&
                        currentDate.year == today.year,
                    month: currentDate.month,
                    year: currentDate.year,
                    weatherData: weatherData,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      "January","February","March","April","May","June",
      "July","August","September","October","November","December"
    ];
    return months[month - 1];
  }
}