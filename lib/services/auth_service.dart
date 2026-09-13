import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:review_ai/core/utils/logger_service.dart';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'package:review_ai/config/api_config.dart';
import 'package:review_ai/services/app_attestation_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

void _debugLog(String message) {
  if (kDebugMode) {
    LoggerService.d(message);
  }
}

/// JWT 기반 동적 토큰 인증 서비스
class AuthService {
  @visibleForTesting
  static http.Client? mockClient;

  @visibleForTesting
  static FlutterSecureStorage? mockStorage;

  @visibleForTesting
  static String? mockAppVersion;

  @visibleForTesting
  static String? mockDeviceInfo;

  @visibleForTesting
  static Future<String?> Function()? mockAppCheckTokenProvider;

  static final http.Client _defaultClient = http.Client();

  static http.Client get _client => mockClient ?? _defaultClient;
  static FlutterSecureStorage get _secureStorage => mockStorage ?? _storage;

  static const String _tokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _tokenExpiryKey = 'token_expiry';
  static const String _deviceIdKey = 'device_id';

  static const _storage = FlutterSecureStorage();
  static String? _cachedAccessToken;
  static String? _cachedRefreshToken;
  static DateTime? _tokenExpiry;
  static String? _deviceId;
  static String? _cachedAppVersion;
  static String? _cachedDeviceInfo;

  /// 유효한 액세스 토큰을 반환 (자동 갱신 포함)
  static Future<String> getValidAccessToken() async {
    try {
      if (_cachedAccessToken != null &&
          _tokenExpiry != null &&
          DateTime.now().isBefore(
            _tokenExpiry!.subtract(const Duration(minutes: 1)),
          )) {
        _debugLog('Using cached access token');
        return _cachedAccessToken!;
      }

      // 리프레시 토큰으로 새 액세스 토큰 발급 시도
      if (_cachedRefreshToken != null) {
        try {
          final newToken = await _refreshAccessToken(_cachedRefreshToken!);
          if (newToken != null) {
            _debugLog('Access token refreshed successfully');
            return newToken;
          }
        } on AuthException catch (e) {
          _debugLog('Token refresh auth error: ${e.message}');
        } on TimeoutException {
          _debugLog('Token refresh timeout');
        } on SocketException {
          _debugLog('Token refresh network error');
        } catch (e, stack) {
          LoggerService.e('Token refresh unexpected error', e, stack);
        }
      }

      // 새 토큰 발급
      _debugLog('Requesting new access token');
      return await _requestNewToken();
    } on AuthException {
      rethrow;
    } catch (e, stack) {
      LoggerService.e('AuthService getValidAccessToken error', e, stack);
      throw AuthException('인증 토큰을 가져올 수 없습니다.');
    }
  }

  /// 새 액세스 토큰 요청
  static Future<String> _requestNewToken() async {
    try {
      final deviceId = await _getOrCreateDeviceId();
      final appVersion = await _getAppVersion();
      final deviceInfo = await _getDeviceInfo();

      const requestUrl = '${ApiConfig.proxyUrl}/api/auth/token';
      _debugLog('Requesting token from: $requestUrl');
      final appCheckHeaders = await _getAppCheckHeaders();

      final response = await _client
          .post(
            Uri.parse(requestUrl),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'ReviewAI-Flutter/$appVersion',
              ...appCheckHeaders,
            },
            body: jsonEncode({
              'deviceId': deviceId,
              'appVersion': appVersion,
              'deviceInfo': deviceInfo,
            }),
          )
          .timeout(const Duration(seconds: 10));

      _debugLog('Token response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['accessToken'] == null ||
            data['refreshToken'] == null ||
            data['expiresIn'] == null) {
          throw AuthException('토큰 응답에 필수 필드가 누락되었습니다.');
        }
        final accessToken = data['accessToken'] as String;
        final refreshToken = data['refreshToken'] as String;
        final expiresIn = data['expiresIn'] as int;

        await _cacheTokens(accessToken, refreshToken, expiresIn);

        return accessToken;
      } else {
        try {
          final errorData = jsonDecode(response.body);
          _debugLog(
            'Token request failed: ${errorData['message']} (Status: ${response.statusCode})',
          );
          throw AuthException('인증 서버에 연결할 수 없습니다. 잠시 후 다시 시도해주세요.');
        } on FormatException {
          _debugLog(
            'Token request failed with status ${response.statusCode} (Invalid JSON)',
          );
          throw AuthException('인증 서버에 연결할 수 없습니다. 잠시 후 다시 시도해주세요.');
        } catch (e, stack) {
          LoggerService.e('Error decoding token error response', e, stack);
          throw AuthException('인증 서버에 연결할 수 없습니다. 잠시 후 다시 시도해주세요.');
        }
      }
    } on TimeoutException {
      throw AuthException('서버 응답이 지연되고 있습니다.');
    } on SocketException {
      throw AuthException('네트워크 연결을 확인해주세요.');
    } on AuthException {
      rethrow;
    } catch (e, stack) {
      LoggerService.e(
        'AuthService _requestNewToken unexpected error',
        e,
        stack,
      );
      throw AuthException('알 수 없는 인증 오류가 발생했습니다.');
    }
  }

  /// 리프레시 토큰으로 액세스 토큰 갱신
  static Future<String?> _refreshAccessToken(String refreshToken) async {
    final appCheckHeaders = await _getAppCheckHeaders();
    final response = await _client
        .post(
          Uri.parse('${ApiConfig.proxyUrl}/api/auth/refresh'),
          headers: {'Content-Type': 'application/json', ...appCheckHeaders},
          body: jsonEncode({'refreshToken': refreshToken}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['accessToken'] == null || data['expiresIn'] == null) {
        throw AuthException('토큰 갱신 응답에 필수 필드가 누락되었습니다.');
      }
      final accessToken = data['accessToken'] as String;
      final expiresIn = data['expiresIn'] as int;

      // 새 액세스 토큰만 캐싱 (리프레시 토큰은 그대로 유지)
      await _cacheAccessToken(accessToken, expiresIn);

      return accessToken;
    } else {
      // 리프레시 실패시 토큰만 클리어 (deviceId 보존)
      await _clearTokens();
      return null;
    }
  }

  static Future<Map<String, String>> _getAppCheckHeaders() async {
    final provider =
        mockAppCheckTokenProvider ?? AppAttestationService.getToken;
    final token = await provider();
    if (token == null || token.isEmpty) return const {};
    return {'X-Firebase-AppCheck': token};
  }

  /// 토큰 캐싱 (Secure Storage 사용)
  static Future<void> _cacheTokens(
    String accessToken,
    String refreshToken,
    int expiresIn,
  ) async {
    final expiry = DateTime.now().add(Duration(seconds: expiresIn));

    await Future.wait([
      _secureStorage.write(key: _tokenKey, value: accessToken),
      _secureStorage.write(key: _refreshTokenKey, value: refreshToken),
      _secureStorage.write(
        key: _tokenExpiryKey,
        value: expiry.toIso8601String(),
      ),
    ]);

    _cachedAccessToken = accessToken;
    _cachedRefreshToken = refreshToken;
    _tokenExpiry = expiry;
  }

  /// 액세스 토큰만 캐싱
  static Future<void> _cacheAccessToken(
    String accessToken,
    int expiresIn,
  ) async {
    final expiry = DateTime.now().add(Duration(seconds: expiresIn));

    await Future.wait([
      _secureStorage.write(key: _tokenKey, value: accessToken),
      _secureStorage.write(
        key: _tokenExpiryKey,
        value: expiry.toIso8601String(),
      ),
    ]);

    _cachedAccessToken = accessToken;
    _tokenExpiry = expiry;
  }

  /// 토큰 캐시 클리어 (deviceId는 보존)
  static Future<void> _clearTokens() async {
    await Future.wait([
      _secureStorage.delete(key: _tokenKey),
      _secureStorage.delete(key: _refreshTokenKey),
      _secureStorage.delete(key: _tokenExpiryKey),
    ]);

    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _tokenExpiry = null;
  }

  /// 디바이스 ID 가져오기 또는 생성
  static Future<String> _getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    _deviceId = await _secureStorage.read(key: _deviceIdKey);

    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await _secureStorage.write(key: _deviceIdKey, value: _deviceId!);
      _debugLog('New device ID generated and stored securely');
    }

    return _deviceId!;
  }

  /// 앱 버전 가져오기 (캐싱 적용)
  static Future<String> _getAppVersion() async {
    if (mockAppVersion != null) return mockAppVersion!;
    if (_cachedAppVersion != null) return _cachedAppVersion!;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _cachedAppVersion = packageInfo.version;
      return _cachedAppVersion!;
    } catch (e, stack) {
      LoggerService.e('Failed to get app version', e, stack);
      return '1.0.0';
    }
  }

  /// 디바이스 정보 가져오기 (캐싱 적용)
  static Future<String> _getDeviceInfo() async {
    if (mockDeviceInfo != null) return mockDeviceInfo!;
    if (_cachedDeviceInfo != null) return _cachedDeviceInfo!;
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _cachedDeviceInfo =
            'Android-${androidInfo.version.release}-${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _cachedDeviceInfo = 'iOS-${iosInfo.systemVersion}-${iosInfo.model}';
      } else {
        _cachedDeviceInfo = 'Unknown-Platform';
      }

      return _cachedDeviceInfo!;
    } catch (e, stack) {
      LoggerService.e('Failed to get device info', e, stack);
      return 'Unknown-Device';
    }
  }

  /// 앱 시작시 캐시된 토큰 로드
  static Future<void> initialize() async {
    try {
      _cachedAccessToken = await _secureStorage.read(key: _tokenKey);
      _cachedRefreshToken = await _secureStorage.read(key: _refreshTokenKey);

      final expiryString = await _secureStorage.read(key: _tokenExpiryKey);
      if (expiryString != null) {
        _tokenExpiry = DateTime.parse(expiryString);
      }

      _deviceId = await _secureStorage.read(key: _deviceIdKey);

      _debugLog('AuthService initialized (Secure Storage)');
    } catch (e, stack) {
      LoggerService.e('AuthService initialization failed', e, stack);
    }
  }

  /// 로그아웃 (토큰 삭제)
  static Future<void> logout() async {
    await _clearTokens();
    _debugLog('User logged out');
  }

  /// 테스트 환경에서 가짜 토큰을 설정하기 위한 헬퍼 메서드
  @visibleForTesting
  static void setMockToken({
    String? accessToken,
    String? refreshToken,
    DateTime? expiry,
  }) {
    _cachedAccessToken = accessToken;
    _cachedRefreshToken = refreshToken;
    _tokenExpiry = expiry;
  }
}

/// 인증 관련 예외 클래스
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}
