import 'dart:convert';

class UserSession {
  UserSession({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.accessToken,
  });

  final String userId;
  final String firstName;
  final String lastName;
  final String accessToken;

  factory UserSession.fromLoginResponse(Map<String, dynamic> json) {
    final token = json['accessToken']?.toString() ?? '';
    if (token.isEmpty) {
      throw Exception('The server did not return an access token.');
    }

    final payload = _decodeJwtPayload(token);
    final userId = payload['userId']?.toString() ?? '';
    if (userId.isEmpty) {
      throw Exception('The login token did not include a user id.');
    }

    return UserSession(
      userId: userId,
      firstName: payload['firstName']?.toString() ?? '',
      lastName: payload['lastName']?.toString() ?? '',
      accessToken: token,
    );
  }

  UserSession copyWith({
    String? userId,
    String? firstName,
    String? lastName,
    String? accessToken,
  }) {
    return UserSession(
      userId: userId ?? this.userId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      accessToken: accessToken ?? this.accessToken,
    );
  }

  static Map<String, dynamic> _decodeJwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw Exception('Invalid JWT format.');
    }

    final normalized = base64Url.normalize(parts[1]);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return jsonDecode(decoded) as Map<String, dynamic>;
  }
}
