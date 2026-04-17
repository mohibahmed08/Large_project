import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/account_settings.dart';
import '../models/user_model.dart';
import 'api_config.dart';

class AccountSettingsResult {
  AccountSettingsResult({required this.settings, required this.session});

  final AccountSettings settings;
  final UserSession session;
}

class AccountService {
  AccountService({String? baseUrl}) : baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final String baseUrl;

  Future<AccountSettingsResult> getSettings({
    required UserSession session,
  }) async {
    final json = await _post('getaccountsettings', session, {});
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
    String? avatarUrl,
  }) async {
    final json = await _post('saveaccountsettings', session, {
      'firstName': firstName,
      'lastName': lastName,
      'reminderEnabled': reminderEnabled,
      'reminderMinutesBefore': reminderMinutesBefore,
      'reminderDelivery': reminderDelivery,
      ...?avatarUrl == null ? null : {'avatarUrl': avatarUrl},
    });
    final nextSession = _updatedSession(
      session,
      json,
    ).copyWith(firstName: firstName, lastName: lastName);
    return AccountSettingsResult(
      settings: AccountSettings.fromJson(
        (json['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      session: nextSession,
    );
  }

  Future<
    ({
      UserSession session,
      String imageUrl,
      String storagePath,
      String bucket,
      String mimeType,
    })
  >
  uploadImage({
    required UserSession session,
    required String imageDataUrl,
    required String purpose,
    required String fileName,
  }) async {
    final json = await _post('uploadimage', session, {
      'imageDataUrl': imageDataUrl,
      'purpose': purpose,
      'fileName': fileName,
    });
    return (
      session: _updatedSession(session, json),
      imageUrl: (json['imageUrl'] ?? '').toString(),
      storagePath: (json['storagePath'] ?? '').toString(),
      bucket: (json['bucket'] ?? '').toString(),
      mimeType: (json['mimeType'] ?? '').toString(),
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

  Future<({UserSession session, String message})> requestEmailChange({
    required UserSession session,
    required String nextEmail,
  }) async {
    final json = await _post('requestemailchange', session, {
      'nextEmail': nextEmail.trim(),
    });
    return (
      session: _updatedSession(session, json),
      message:
          (json['message'] ?? 'Verification sent to the new email address.')
              .toString(),
    );
  }

  Future<({UserSession session, String icsContent, String filename})>
  exportCalendar({required UserSession session}) async {
    final json = await _post('exportcalendar', session, {});
    return (
      session: _updatedSession(session, json),
      icsContent: (json['ics'] ?? '').toString(),
      filename: (json['filename'] ?? 'calendar-plus-plus.ics').toString(),
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

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = _decodeBody(response.body);
      return json;
    }

    final json = _decodeBody(response.body);
    throw Exception(json['error']?.toString() ?? 'Request failed.');
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.isEmpty) {
      return {};
    }

    final trimmed = body.trimLeft();
    if (trimmed.startsWith('<!DOCTYPE html') || trimmed.startsWith('<html')) {
      return const {
        'error':
            'Upload failed. The server returned HTML instead of JSON, which usually means the upload was too large or the request hit the wrong endpoint.',
      };
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
