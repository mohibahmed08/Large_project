import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'calendar_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final String apiBase = 'http://localhost:5000'; 

  // UI State
  bool isLogin = true;
  bool showPassword = false;
  bool isLoading = false;
  String errorMsg = '';
  String successMsg = '';

  // Controllers
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  // Colors
  final Color bgGray900 = const Color(0xFF111827);
  final Color bgGray800 = const Color(0xFF1f2937);
  final Color borderGray700 = const Color(0xFF374151);
  final Color textGray400 = const Color(0xFF9ca3af);
  final Color blue500 = const Color(0xFF3b82f6);

  void switchTab(bool loginMode) {
    setState(() {
      isLogin = loginMode;
      errorMsg = '';
      successMsg = '';
    });
  }

  Future<void> handleSubmit() async {
    if (!isLogin && passwordController.text != confirmPasswordController.text) {
      setState(() => errorMsg = 'Passwords do not match');
      return;
    }

    setState(() {
      isLoading = true;
      errorMsg = '';
      successMsg = '';
    });

    try {
      if (isLogin) {
        // --- LOGIN API CALL ---
        final res = await http.post(
          Uri.parse('$apiBase/api/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'login': emailController.text,
            'password': passwordController.text,
          }),
        );

        final data = jsonDecode(res.body);

        if (res.statusCode != 200) {
          setState(() => errorMsg = data['error'] ?? 'Login failed.');
          return;
        }

        // Save data to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwtToken', data['jwtToken'] ?? '');
        await prefs.setString('userId', data['id'] ?? '');
        await prefs.setString('firstName', data['firstName'] ?? '');
        await prefs.setString('lastName', data['lastName'] ?? '');

        // Navigate to the Calendar Screen
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => CalendarScreen()),
          );
        }

      } else {
        // --- REGISTER API CALL ---
        final res = await http.post(
          Uri.parse('$apiBase/api/signup'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'firstName': firstNameController.text,
            'lastName': lastNameController.text,
            'email': emailController.text,
            'password': passwordController.text,
          }),
        );

        final data = jsonDecode(res.body);

        if (res.statusCode != 200) {
          setState(() => errorMsg = data['error'] ?? 'Registration failed.');
          return;
        }

        setState(() {
          successMsg = 'Account created! Please verify your email.';
          isLogin = true; 
        });
      }
    } catch (e) {
      setState(() => errorMsg = 'Could not reach the server. Check connection.');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  // UI Builder for Inputs
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool isPassword = false,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: textGray400, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: isPassword && !showPassword,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: bgGray900,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderGray700),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: blue500),
            ),
            suffixIcon: isPassword
                ? TextButton(
                    onPressed: () => setState(() => showPassword = !showPassword),
                    child: Text(
                      showPassword ? 'HIDE' : 'SHOW',
                      style: TextStyle(color: textGray400, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray900, 
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 448), 
            margin: const EdgeInsets.all(16), 
            padding: const EdgeInsets.all(32), 
            decoration: BoxDecoration(
              color: bgGray800,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderGray700),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tabs
                Container(
                  margin: const EdgeInsets.only(bottom: 32),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderGray700))),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => switchTab(true),
                          child: Container(
                            padding: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: isLogin ? blue500 : Colors.transparent, width: 2)),
                            ),
                            child: Text('LOGIN', textAlign: TextAlign.center, style: TextStyle(color: isLogin ? blue500 : textGray400, fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => switchTab(false),
                          child: Container(
                            padding: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: !isLogin ? blue500 : Colors.transparent, width: 2)),
                            ),
                            child: Text('REGISTER', textAlign: TextAlign.center, style: TextStyle(color: !isLogin ? blue500 : textGray400, fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Text(isLogin ? 'Welcome Back' : 'Create Account', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),

                if (errorMsg.isNotEmpty)
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), border: Border.all(color: Colors.red.shade700), borderRadius: BorderRadius.circular(8)),
                    child: Text(errorMsg, style: TextStyle(color: Colors.red.shade300, fontSize: 14)),
                  ),
                if (successMsg.isNotEmpty)
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), border: Border.all(color: Colors.green.shade700), borderRadius: BorderRadius.circular(8)),
                    child: Text(successMsg, style: TextStyle(color: Colors.green.shade300, fontSize: 14)),
                  ),

                if (!isLogin) ...[
                  Row(
                    children: [
                      Expanded(child: _buildTextField(label: 'FIRST NAME', controller: firstNameController, hintText: 'Jane')),
                      const SizedBox(width: 12),
                      Expanded(child: _buildTextField(label: 'LAST NAME', controller: lastNameController, hintText: 'Doe')),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                _buildTextField(label: 'EMAIL ADDRESS', controller: emailController, hintText: 'johndoe@example.com'),
                const SizedBox(height: 20),
                
                _buildTextField(label: 'PASSWORD', controller: passwordController, isPassword: true, hintText: '••••••••'),
                const SizedBox(height: 20),

                if (!isLogin) ...[
                  _buildTextField(label: 'CONFIRM PASSWORD', controller: confirmPasswordController, isPassword: true, hintText: '••••••••'),
                  const SizedBox(height: 20),
                ],

                SizedBox(
                  width: double.infinity, height: 48,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600, disabledBackgroundColor: borderGray700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(isLogin ? 'Sign In' : 'Get Started', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(isLogin ? "Don't have an account? " : "Already have an account? ", style: const TextStyle(color: Colors.grey, fontSize: 14)),
                    GestureDetector(
                      onTap: () => switchTab(!isLogin),
                      child: Text(isLogin ? 'Register now' : 'Log in here', style: TextStyle(color: blue500, fontSize: 14, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}