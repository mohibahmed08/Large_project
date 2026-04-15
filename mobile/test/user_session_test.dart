import 'dart:convert';

import 'package:calendar/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

String createJwt(Map<String, Object?> payload) {
  String encodePart(Object value) {
    return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  return '${encodePart({'alg': 'none', 'typ': 'JWT'})}.${encodePart(payload)}.signature';
}

void main() {
  test('UserSession.fromAccessToken decodes the user payload', () {
    final token = createJwt({
      'userId': 'user-7',
      'firstName': 'Jordan',
      'lastName': 'Lee',
    });

    final session = UserSession.fromAccessToken(token);

    expect(session.userId, 'user-7');
    expect(session.firstName, 'Jordan');
    expect(session.lastName, 'Lee');
    expect(session.accessToken, token);
  });

  test('UserSession.fromLoginResponse reads the access token field', () {
    final token = createJwt({
      'userId': 'user-8',
      'firstName': 'Sam',
      'lastName': 'Patel',
    });

    final session = UserSession.fromLoginResponse({'accessToken': token});

    expect(session.userId, 'user-8');
    expect(session.firstName, 'Sam');
    expect(session.lastName, 'Patel');
  });

  test('UserSession.fromAccessToken rejects invalid JWT formats', () {
    expect(
      () => UserSession.fromAccessToken('not-a-token'),
      throwsException,
    );
  });

  test('copyWith preserves existing values unless overridden', () {
    final original = UserSession(
      userId: 'user-9',
      firstName: 'Taylor',
      lastName: 'Kim',
      accessToken: 'token-a',
    );

    final updated = original.copyWith(lastName: 'Tran', accessToken: 'token-b');

    expect(updated.userId, 'user-9');
    expect(updated.firstName, 'Taylor');
    expect(updated.lastName, 'Tran');
    expect(updated.accessToken, 'token-b');
  });
}
