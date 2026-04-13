import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/user_model.dart';
import 'api_config.dart';

class AuthService {
  AuthService({String? baseUrl}) : baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final String baseUrl;

  Future<UserSession> login(String email, String password) async {
    final response = await _post(
      Uri.parse('$baseUrl/login'),
      {'login': email, 'password': password},
    );

    return UserSession.fromLoginResponse(response);
  }

  Future<void> signup({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    await _post(
      Uri.parse('$baseUrl/signup'),
      {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'password': password,
      },
    );
  }

  Future<void> requestPasswordReset(String email) async {
    await _post(
      Uri.parse('$baseUrl/forgotpassword'),
      {'email': email},
    );
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _post(
      Uri.parse('$baseUrl/resetpassword'),
      {'token': token, 'newPassword': newPassword},
    );
  }

  Future<Map<String, dynamic>> _post(Uri uri, Map<String, dynamic> body) async {
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    final json = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json;
    }

    throw Exception(json['error']?.toString() ?? 'Request failed.');
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.isEmpty) {
      return {};
    }

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return {};
  }
}
