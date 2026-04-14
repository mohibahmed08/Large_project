import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/account_settings.dart';
import '../models/user_model.dart';
import 'api_config.dart';

class AccountSettingsResult {
  AccountSettingsResult({
    required this.settings,
    required this.session,
  });

  final AccountSettings settings;
  final UserSession session;
}

class AccountService {
  AccountService({String? baseUrl}) : baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final String baseUrl;

  Future<AccountSettingsResult> getSettings({
    required UserSession session,
  }) async {
    final json = await _post(
      'getaccountsettings',
      session,
      {},
    );
    return AccountSettingsResult(
      settings: AccountSettings.fromJson(
        (json['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      session: _updatedSession(session, json),
    );
  }

  Future<AccountSettingsResult> saveSettings({
    required UserSession session,
    required String firstName,
    required String lastName,
    required bool reminderEnabled,
    required int reminderMinutesBefore,
    required String reminderDelivery,
    String? avatarDataUrl,
  }) async {
    final json = await _post(
      'saveaccountsettings',
      session,
      {
        'firstName': firstName,
        'lastName': lastName,
        'reminderEnabled': reminderEnabled,
        'reminderMinutesBefore': reminderMinutesBefore,
        'reminderDelivery': reminderDelivery,
        ...?avatarDataUrl == null ? null : {'avatarDataUrl': avatarDataUrl},
      },
    );
    final nextSession = _updatedSession(session, json).copyWith(
      firstName: firstName,
      lastName: lastName,
    );
    return AccountSettingsResult(
      settings: AccountSettings.fromJson(
        (json['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      session: nextSession,
    );
  }

  Future<AccountSettingsResult> regenerateFeed({
    required UserSession session,
  }) async {
    final json = await _post('regeneratecalendarfeed', session, {});
    return AccountSettingsResult(
      settings: AccountSettings.fromJson(
        (json['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
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

  UserSession _updatedSession(UserSession session, Map<String, dynamic> json) {
    final refreshed = json['jwtToken']?.toString() ?? '';
    if (refreshed.isEmpty) {
      return session;
    }
    return session.copyWith(accessToken: refreshed);
  }
}
