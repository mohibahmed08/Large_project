import 'package:flutter/material.dart';

class DayDetailScreen extends StatelessWidget {
  final int day;
  final int month;
  final int year;

  DayDetailScreen({
    required this.day,
    required this.month,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Day Details"),
      ),
      body: Center(
        child: Text(
          "$day / $month / $year",
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}