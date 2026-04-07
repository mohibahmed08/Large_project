import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/task_model.dart';
import '../models/user_model.dart';
import 'api_config.dart';

class CalendarResult {
  CalendarResult({
    required this.tasks,
    required this.session,
  });

  final List<CalendarTask> tasks;
  final UserSession session;
}

class CalendarService {
  CalendarService({String? baseUrl}) : baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final String baseUrl;

  Future<CalendarResult> loadCalendar({
    required UserSession session,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final json = await _post(
      'loadcalendar',
      session,
      {
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      },
    );

    final tasks = ((json['tasks'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CalendarTask.fromJson)
        .toList();

    return CalendarResult(
      tasks: tasks,
      session: _updatedSession(session, json),
    );
  }

  Future<CalendarResult> searchCalendar({
    required UserSession session,
    required String search,
  }) async {
    final json = await _post(
      'searchcalendar',
      session,
      {'search': search},
    );

    final tasks = ((json['results'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CalendarTask.fromJson)
        .toList();

    return CalendarResult(
      tasks: tasks,
      session: _updatedSession(session, json),
    );
  }

  Future<UserSession> saveTask({
    required UserSession session,
    String? taskId,
    required String title,
    String description = '',
    DateTime? startDate,
    DateTime? endDate,
    String location = '',
    String source = 'manual',
    bool isCompleted = false,
  }) async {
    final json = await _post(
      'savecalendar',
      session,
      {
        if (taskId != null && taskId.isNotEmpty) 'taskId': taskId,
        'title': title,
        'description': description,
        if (startDate != null) 'dueDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
        'location': location,
        'source': source,
        'isCompleted': isCompleted,
      },
    );

    return _updatedSession(session, json);
  }

  Future<(UserSession, int)> importCalendar({
    required UserSession session,
    String? icsUrl,
    String? icsContent,
  }) async {
    final json = await _post(
      'readcalendar',
      session,
      {
        if (icsUrl != null && icsUrl.trim().isNotEmpty) 'icsUrl': icsUrl.trim(),
        if (icsContent != null && icsContent.trim().isNotEmpty)
          'icsContent': icsContent.trim(),
      },
    );

    return (
      _updatedSession(session, json),
      (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    UserSession session,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': session.userId,
        'jwtToken': session.accessToken,
        ...body,
      }),
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

  UserSession _updatedSession(UserSession session, Map<String, dynamic> json) {
    final refreshed = json['jwtToken']?.toString() ?? '';
    if (refreshed.isEmpty) {
      return session;
    }
    return session.copyWith(accessToken: refreshed);
  }
}
