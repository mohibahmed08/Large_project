import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/calendar_screen.dart'; 

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isLoggedIn = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  // Check if a JWT token is already saved on the device
  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');
    
    setState(() {
      _isLoggedIn = token != null && token.isNotEmpty;
      _isLoading = false; // Finished checking
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show a blank loading screen while checking the token
    if (_isLoading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF111827), // Matches your dark theme
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      title: 'Calendar++',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      // If logged in, go to Calendar. If not, go to Login.
      home: _isLoggedIn ? CalendarScreen() : LoginScreen(),
    );
  }
}