import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_models.dart';
import '../models/user_model.dart';
import 'api_config.dart';

class AiChatResult {
  AiChatResult({
    required this.reply,
    required this.session,
  });

  final String reply;
  final UserSession session;
}

class AiSuggestionResult {
  AiSuggestionResult({
    required this.suggestions,
    required this.session,
  });

  final List<SuggestionItem> suggestions;
  final UserSession session;
}

class AiService {
  AiService({String? baseUrl}) : baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final String baseUrl;

  Future<AiChatResult> chat({
    required UserSession session,
    required List<Map<String, String>> messages,
    double? latitude,
    double? longitude,
  }) async {
    final localNow = DateTime.now();
    final json = await _post(
      'chat',
      session,
      {
        'messages': messages,
        'localNow': localNow.toIso8601String(),
        'timeZone': localNow.timeZoneName,
        'utcOffsetMinutes': localNow.timeZoneOffset.inMinutes,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
    );

    return AiChatResult(
      reply: json['reply']?.toString() ?? '',
      session: _updatedSession(session, json),
    );
  }

  Future<AiSuggestionResult> suggestEvents({
    required UserSession session,
    required DateTime date,
    String? preferences,
    double? latitude,
    double? longitude,
  }) async {
    final localNow = DateTime.now();
    final json = await _post(
      'suggestevents',
      session,
      {
        'date': date.toIso8601String(),
        'localNow': localNow.toIso8601String(),
        'timeZone': localNow.timeZoneName,
        'utcOffsetMinutes': localNow.timeZoneOffset.inMinutes,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (preferences != null && preferences.trim().isNotEmpty)
          'preferences': preferences.trim(),
      },
    );

    final suggestions = _parseSuggestions(json['suggestions']);

    return AiSuggestionResult(
      suggestions: suggestions,
      session: _updatedSession(session, json),
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

  List<SuggestionItem> _parseSuggestions(dynamic rawSuggestions) {
    final items = (rawSuggestions as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SuggestionItem.fromJson)
        .toList();

    if (items.length == 1 && items.first.title == 'Parse error') {
      final recovered = _recoverSuggestionsFromText(items.first.description);
      if (recovered.isNotEmpty) {
        return recovered;
      }
    }

    return items;
  }

  List<SuggestionItem> _recoverSuggestionsFromText(String text) {
    final cleaned = _extractJsonArray(text);
    if (cleaned.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! List) {
        return const [];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) => SuggestionItem.fromJson(
              item.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String _extractJsonArray(String text) {
    final fenceMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```', multiLine: true)
        .firstMatch(text);
    final fenced = fenceMatch?.group(1)?.trim();
    if (fenced != null && fenced.startsWith('[') && fenced.endsWith(']')) {
      return fenced;
    }

    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start >= 0 && end > start) {
      return text.substring(start, end + 1).trim();
    }

    return '';
  }

  UserSession _updatedSession(UserSession session, Map<String, dynamic> json) {
    final refreshed = json['jwtToken']?.toString() ?? '';
    if (refreshed.isEmpty) {
      return session;
    }
    return session.copyWith(accessToken: refreshed);
  }
}
