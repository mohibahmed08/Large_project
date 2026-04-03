import 'package:flutter/material.dart';
// Import the file you just created. Ensure the path matches your folder structure!
import 'screens/login_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calendar++',
      // This hides the little "DEBUG" banner in the top right corner
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      // This is the most important line: it tells Flutter what screen to show first
      home: LoginScreen(),
    );
  }
}