import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_ai/config/api_config.dart';

/// 최고 수준 보안을 위한 동적 토큰 인증 서비스
class AuthService {
  static const String _tokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _tokenExpiryKey = 'token_expiry';
  static const String _deviceIdKey = 'device_id';

  static String? _cachedAccessToken;
  static String? _cachedRefreshToken;
  static DateTime? _tokenExpiry;
  static String? _deviceId;

  /// 유효한 액세스 토큰을 반환 (자동 갱신 포함)
  static Future<String> getValidAccessToken() async {
    try {
      // 캐시된 토큰이 있고 유효하면 반환
      if (_cachedAccessToken != null &&
          _tokenExpiry != null &&
          DateTime.now().isBefore(_tokenExpiry!)) {
        debugPrint('Using cached access token');
        return _cachedAccessToken!;
      }

      // 리프레시 토큰으로 새 액세스 토큰 발급 시도
      if (_cachedRefreshToken != null) {
        try {
          final newToken = await _refreshAccessToken(_cachedRefreshToken!);
          if (newToken != null) {
            debugPrint('Access token refreshed successfully');
            return newToken;
          }
        } catch (e) {
          debugPrint('Token refresh failed: $e');
          // 리프레시 실패시 새로 발급
        }
      }

      // 새 토큰 발급
      debugPrint('Requesting new access token');
      return await _requestNewToken();
    } catch (e) {
      debugPrint('AuthService error: $e');
      throw AuthException('인증 토큰을 가져올 수 없습니다: ${e.toString()}');
    }
  }

  /// 새 액세스 토큰 요청
  static Future<String> _requestNewToken() async {
    try {
      final deviceId = await _getOrCreateDeviceId();
      final appVersion = await _getAppVersion();
      final deviceInfo = await _getDeviceInfo();

      final requestUrl = '${ApiConfig.proxyUrl}/api/auth/token';
      debugPrint('Requesting token from: $requestUrl');
      debugPrint('DeviceId: $deviceId, AppVersion: $appVersion');

      final response = await http
          .post(
            Uri.parse(requestUrl),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'ReviewAI-Flutter/$appVersion',
            },
            body: jsonEncode({
              'deviceId': deviceId,
              'appVersion': appVersion,
              'deviceInfo': deviceInfo,
            }),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('Token response status: ${response.statusCode}');
      // 🔒 보안: 토큰 내용은 로그에 출력하지 않음 (프로덕션)
      if (kDebugMode) {
        debugPrint('Token response received (length: ${response.body.length})');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // 🔒 null 체크: 필수 필드 검증
        if (data['accessToken'] == null || data['refreshToken'] == null || data['expiresIn'] == null) {
          throw AuthException('토큰 응답에 필수 필드가 누락되었습니다.');
        }
        final accessToken = data['accessToken'] as String;
        final refreshToken = data['refreshToken'] as String;
        final expiresIn = data['expiresIn'] as int;

        // 토큰 캐싱
        await _cacheTokens(accessToken, refreshToken, expiresIn);

        return accessToken;
      } else {
        try {
          final errorData = jsonDecode(response.body);
          throw AuthException(
            '토큰 발급 실패: ${errorData['message'] ?? 'Unknown error'} (Status: ${response.statusCode})',
          );
        } catch (e) {
          // JSON 파싱 실패 시 (HTML 응답 등)
          throw AuthException(
            '토큰 발급 실패: 서버 응답 오류 (Status: ${response.statusCode}). Response: ${response.body.substring(0, 100)}',
          );
        }
      }
    } catch (e) {
      debugPrint('AuthService _requestNewToken error: $e');
      rethrow;
    }
  }

  /// 리프레시 토큰으로 액세스 토큰 갱신
  static Future<String?> _refreshAccessToken(String refreshToken) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.proxyUrl}/api/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // 🔒 null 체크: 필수 필드 검증
      if (data['accessToken'] == null || data['expiresIn'] == null) {
        throw AuthException('토큰 갱신 응답에 필수 필드가 누락되었습니다.');
      }
      final accessToken = data['accessToken'] as String;
      final expiresIn = data['expiresIn'] as int;

      // 새 액세스 토큰만 캐싱 (리프레시 토큰은 그대로 유지)
      await _cacheAccessToken(accessToken, expiresIn);

      return accessToken;
    } else {
      // 리프레시 실패시 캐시 클리어
      await _clearTokens();
      return null;
    }
  }

  /// 토큰 캐싱
  static Future<void> _cacheTokens(
    String accessToken,
    String refreshToken,
    int expiresIn,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = DateTime.now().add(Duration(seconds: expiresIn));

    await prefs.setString(_tokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    await prefs.setString(_tokenExpiryKey, expiry.toIso8601String());

    _cachedAccessToken = accessToken;
    _cachedRefreshToken = refreshToken;
    _tokenExpiry = expiry;
  }

  /// 액세스 토큰만 캐싱
  static Future<void> _cacheAccessToken(
    String accessToken,
    int expiresIn,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = DateTime.now().add(Duration(seconds: expiresIn));

    await prefs.setString(_tokenKey, accessToken);
    await prefs.setString(_tokenExpiryKey, expiry.toIso8601String());

    _cachedAccessToken = accessToken;
    _tokenExpiry = expiry;
  }

  /// 토큰 캐시 클리어
  static Future<void> _clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_tokenExpiryKey);

    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _tokenExpiry = null;
  }

  /// 디바이스 ID 가져오기 또는 생성
  static Future<String> _getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_deviceIdKey);

    if (_deviceId == null) {
      _deviceId = _generateDeviceId();
      await prefs.setString(_deviceIdKey, _deviceId!);
    }

    return _deviceId!;
  }

  /// 디바이스 ID 생성
  static String _generateDeviceId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp * 1000 + (timestamp % 1000)).toString();
    return 'device_${random}_${DateTime.now().microsecondsSinceEpoch}';
  }

  /// 앱 버전 가져오기
  static Future<String> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      debugPrint('Failed to get app version: $e');
      return '1.0.0';
    }
  }

  /// 디바이스 정보 가져오기
  static Future<String> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return 'Android-${androidInfo.version.release}-${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return 'iOS-${iosInfo.systemVersion}-${iosInfo.model}';
      }

      return 'Unknown-Platform';
    } catch (e) {
      debugPrint('Failed to get device info: $e');
      return 'Unknown-Device';
    }
  }

  /// 앱 시작시 캐시된 토큰 로드
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _cachedAccessToken = prefs.getString(_tokenKey);
      _cachedRefreshToken = prefs.getString(_refreshTokenKey);

      final expiryString = prefs.getString(_tokenExpiryKey);
      if (expiryString != null) {
        _tokenExpiry = DateTime.parse(expiryString);
      }

      _deviceId = prefs.getString(_deviceIdKey);

      debugPrint('AuthService initialized');
    } catch (e) {
      debugPrint('AuthService initialization failed: $e');
    }
  }

  /// 로그아웃 (토큰 삭제)
  static Future<void> logout() async {
    await _clearTokens();
    debugPrint('User logged out');
  }
}

/// 인증 관련 예외 클래스
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}
