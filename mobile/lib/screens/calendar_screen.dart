import 'package:flutter/material.dart';
import '../widgets/day_grid.dart';
import 'ai_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CalendarScreen extends StatefulWidget {
  @override
  _CalendarScreenState createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime currentDate = DateTime.now();
  Map<String, dynamic>? weatherData;
  bool isLoading = true;

  int? selectedDay;
  int selectedIndex = 0;

  // 🔥 EVENTS STORAGE
  Map<int, List<String>> events = {
    3: ["Gym at 6pm", "Meeting at 8pm"],
    5: ["Study session"],
  };

  @override
  void initState() {
    super.initState();
    fetchWeather();
  }

  // ================= WEATHER =================
  Future<void> fetchWeather() async {
    final today = DateTime.now();

    final start =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final endDate = today.add(Duration(days: 10));

    final end =
        "${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}";

    final url = Uri.parse(
        "https://api.open-meteo.com/v1/forecast?latitude=28.5383&longitude=-81.3792&start_date=$start&end_date=$end&hourly=weathercode");

    final response = await http.get(url);

    if (response.statusCode == 200) {
      setState(() {
        weatherData = jsonDecode(response.body);
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  // ================= MONTH NAV =================
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

  // ================= DAY CLICK =================
  void onDaySelected(int day) {
    setState(() {
      selectedDay = day;
    });
  }

  // ================= ADD TASK =================
  void openAddTaskDialog() {
    if (selectedDay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Select a day first")),
      );
      return;
    }

    TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Color(0xFF1e1e2f),
          title: Text("Add Task", style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Enter task...",
              hintStyle: TextStyle(color: Colors.white54),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  addTask(controller.text);
                }
                Navigator.pop(context);
              },
              child: Text("Add"),
            ),
          ],
        );
      },
    );
  }

  void addTask(String task) {
    setState(() {
      if (events[selectedDay] == null) {
        events[selectedDay!] = [];
      }
      events[selectedDay!]!.add(task);
    });
  }

  // ================= NAVIGATION =================
  void onNavTap(int index) {
    setState(() {
      selectedIndex = index;
    });

    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AIScreen()),
      );
    }
  }

  // ================= UI =================
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
        title: Text("Calendar"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),

      // ================= MAIN BODY =================
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ===== MONTH HEADER =====
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: goToPreviousMonth,
                        child: Icon(Icons.arrow_back_ios,
                            color: Colors.white),
                      ),
                      SizedBox(width: 12),
                      Text(
                        "${_getMonthName(currentDate.month)} ${currentDate.year}",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      GestureDetector(
                        onTap: goToNextMonth,
                        child: Icon(Icons.arrow_forward_ios,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),

                // ===== WEEKDAYS =====
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                        .map((day) => Expanded(
                              child: Center(
                                child: Text(
                                  day,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),

                SizedBox(height: 6),

                // ===== CALENDAR GRID =====
                Expanded(
                  child: GridView.builder(
                    padding: EdgeInsets.all(6),
                    itemCount: daysInMonth + firstDayOfMonth,
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemBuilder: (context, index) {
                      if (index < firstDayOfMonth) return SizedBox();

                      int day = index - firstDayOfMonth + 1;

                      return DayGrid(
                        day: day,
                        month: currentDate.month,
                        year: currentDate.year,
                        isToday: day == today.day &&
                            currentDate.month == today.month &&
                            currentDate.year == today.year,
                        weatherData: weatherData,
                        onDayTap: onDaySelected,
                      );
                    },
                  ),
                ),

                // ===== EVENTS PANEL =====
                Container(
                  padding: EdgeInsets.all(16),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Color(0xFF12121f),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedDay != null
                            ? "Events for ${_getMonthName(currentDate.month)} $selectedDay"
                            : "Select a day",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),

                      if (selectedDay != null &&
                          events[selectedDay] != null)
                        ...events[selectedDay]!.map(
                          (e) => Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              e,
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        )
                      else if (selectedDay != null)
                        Text(
                          "No events planned",
                          style: TextStyle(color: Colors.white54),
                        ),
                    ],
                  ),
                ),
              ],
            ),

      // ================= ADD TASK BUTTON =================
      floatingActionButton: FloatingActionButton(
        backgroundColor: Color(0xFF64b5f6),
        onPressed: openAddTaskDialog,
        child: Icon(Icons.add),
      ),

      // ================= BOTTOM NAV =================
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: onNavTap,
        backgroundColor: Color(0xFF12121f),
        selectedItemColor: Color(0xFF64b5f6),
        unselectedItemColor: Colors.white54,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: "Calendar",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.smart_toy),
            label: "AI",
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