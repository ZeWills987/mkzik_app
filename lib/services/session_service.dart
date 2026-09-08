import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class AppSession {
  final int id;
  final String ipAddress;
  final String userAgent;
  final DateTime loginDate;
  final bool isCurrent;

  const AppSession({
    required this.id,
    required this.ipAddress,
    required this.userAgent,
    required this.loginDate,
    required this.isCurrent,
  });

  /// Libellé lisible du user-agent (ex: "Dart/3.12" → "Application Mkzik").
  String get deviceLabel {
    final ua = userAgent.toLowerCase();
    if (ua.contains('dart')) return 'Application Mkzik';
    if (ua.contains('android')) return 'Android';
    if (ua.contains('iphone') || ua.contains('ios')) return 'iPhone';
    if (ua.contains('windows')) return 'Windows';
    if (ua.contains('mac')) return 'macOS';
    if (ua.contains('linux')) return 'Linux';
    return 'Appareil inconnu';
  }

  factory AppSession.fromJson(Map<String, dynamic> j) => AppSession(
        id: (j['id'] as num).toInt(),
        ipAddress: (j['ip_address'] ?? '').toString(),
        userAgent: (j['user_agent'] ?? '').toString(),
        loginDate: DateTime.tryParse(j['login_date']?.toString() ?? '') ?? DateTime.now(),
        isCurrent: j['is_current'] == true,
      );
}

class SessionService {
  static Map<String, String> get _headers {
    final token = ApiConfig.token;
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// `GET api/sessions` → sessions actives.
  static Future<List<AppSession>> getSessions() async {
    final res = await http
        .get(Uri.parse('${ApiConfig.baseUrl}api/sessions'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body);
    if (body is! List) return [];
    return body.whereType<Map<String, dynamic>>().map(AppSession.fromJson).toList();
  }

  /// `DELETE api/sessions/{id}` → révoque une session.
  static Future<bool> revokeSession(int id) async {
    final res = await http
        .delete(Uri.parse('${ApiConfig.baseUrl}api/sessions/$id'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    return res.statusCode == 200;
  }

  /// `POST api/sessions/revoke-others` → révoque toutes les autres sessions.
  /// Retourne le nombre de sessions révoquées.
  static Future<int> revokeOthers() async {
    final res = await http
        .post(Uri.parse('${ApiConfig.baseUrl}api/sessions/revoke-others'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return 0;
    final body = jsonDecode(res.body);
    return body is Map ? (body['revoked'] as num?)?.toInt() ?? 0 : 0;
  }
}
