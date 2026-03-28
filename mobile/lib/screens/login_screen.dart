import 'package:flutter/material.dart';
// Note: You will eventually import your auth_service.dart here
// import '../services/auth_service.dart';

// 1. We use a StatefulWidget because the screen needs to update
// (e.g., showing a loading spinner when the button is clicked)
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 2. Controllers are how we "grab" the text the user types into the fields
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // A simple boolean to track if we are currently waiting for the server
  bool _isLoading = false;

  // 3. The async function triggered when the user taps "Login"
  void _handleLogin() async {
    // setState tells Flutter: "Hey, data changed, redraw the screen!"
    setState(() {
      _isLoading = true;
    });

    try {
      // This is where you will eventually call your backend:
      // final result = await AuthService().login(_emailController.text, _passwordController.text);

      // For now, we simulate a 2-second network delay
      await Future.delayed(Duration(seconds: 2));

      print("Sending to backend -> Email: ${_emailController.text}");

      // If login works, push the user to the Calendar Screen
      // Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CalendarScreen()));

    } catch (e) {
      // If login fails (e.g., wrong password), show a little pop-up banner at the bottom
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login failed: $e")),
      );
    } finally {
      // Turn the loading spinner off whether it succeeded or failed
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 4. The build method is where we draw the UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Calendar++ Login'),
      ),
      // Padding gives our content some breathing room from the screen edges
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        // Column stacks our widgets vertically
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Centers everything in the middle of the screen
          children: [

            // --- EMAIL FIELD ---
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),

            SizedBox(height: 16), // SizedBox is just an invisible spacer

            // --- PASSWORD FIELD ---
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true, // This turns the text into bullet points for security
            ),

            SizedBox(height: 24),

            // --- LOGIN BUTTON ---
            // If _isLoading is true, show a spinner. Otherwise, show the button.
            _isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
              onPressed: _handleLogin,
              child: Text('Login'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50), // Makes the button stretch across the screen
              ),
            ),
          ],
        ),
      ),
    );
  }
}