import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:review_ai/config/api_config.dart';
import 'package:review_ai/services/auth_service.dart';
import 'package:review_ai/core/utils/logger_service.dart';

/// 서버 시간 서비스 (시스템 시간 조작 방지)
class ServerTimeService {
  static DateTime? _cachedServerTime;
  static Stopwatch? _cacheAge;
  static Stopwatch? _failureBackoff;
  static Future<DateTime>? _inFlightRequest;
  static int? _timeOffset; // 서버 시간 - 로컬 시간 (밀리초)

  static http.Client? _customClient;
  static DateTime Function()? _mockNow;

  static DateTime _now() => _mockNow?.call() ?? DateTime.now();

  @visibleForTesting
  static void setClientForTesting(http.Client? client) {
    _customClient = client;
  }

  @visibleForTesting
  static void setClockForTesting(DateTime Function()? clock) {
    _mockNow = clock;
  }

  @visibleForTesting
  static Duration cacheExpiry = const Duration(minutes: 5);

  @visibleForTesting
  static Duration failureCacheExpiry = const Duration(seconds: 30);

  /// 서버 시간을 가져옵니다 (성공 응답은 5분, 실패 응답은 30초간 캐싱).
  static Future<DateTime> getServerTime() async {
    try {
      // 캐시 확인
      if (_cachedServerTime != null && _cacheAge != null) {
        final cacheAge = _cacheAge!.elapsed;
        if (cacheAge < cacheExpiry) {
          // 캐시된 시간 + 경과 시간
          final serverTime = _cachedServerTime!.add(cacheAge);
          LoggerService.d('Using cached server time: $serverTime');
          return serverTime;
        }
      }

      final failureBackoff = _failureBackoff;
      if (failureBackoff != null &&
          failureBackoff.elapsed < failureCacheExpiry) {
        return _now();
      }
      _failureBackoff = null;

      final inFlightRequest = _inFlightRequest;
      if (inFlightRequest != null) {
        return inFlightRequest;
      }

      final request = _fetchServerTime();
      _inFlightRequest = request;
      try {
        return await request;
      } finally {
        if (identical(_inFlightRequest, request)) {
          _inFlightRequest = null;
        }
      }
    } catch (e) {
      _failureBackoff = Stopwatch()..start();
      LoggerService.e('ServerTimeService error: $e');

      // 에러 발생 시 로컬 시간 사용 (폴백)
      LoggerService.d('Falling back to local time');
      return _now();
    }
  }

  static Future<DateTime> _fetchServerTime() async {
    try {
      // 서버에서 시간 가져오기
      LoggerService.d('Fetching server time from API');
      final token = await AuthService.getValidAccessToken();

      final client = _customClient ?? http.Client();
      final http.Response response;
      try {
        response = await client
            .get(
              Uri.parse('${ApiConfig.proxyUrl}/api/server-time'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 10));
      } finally {
        if (_customClient == null) {
          client.close();
        }
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final serverTimeStr = data['serverTime'] as String;
        final serverTimestamp = data['timestamp'] as int;

        final serverTime = DateTime.parse(serverTimeStr);
        final localTime = _now();

        // 시간 오프셋 계산 (서버 - 로컬)
        _timeOffset = serverTimestamp - localTime.millisecondsSinceEpoch;

        // 캐시 저장
        _cachedServerTime = serverTime;
        _cacheAge = Stopwatch()..start();
        _failureBackoff = null;

        LoggerService.d('Server time fetched: $serverTime');
        LoggerService.d('Time offset: ${_timeOffset}ms');

        return serverTime;
      } else {
        throw Exception('Failed to fetch server time: ${response.statusCode}');
      }
    } catch (e) {
      _failureBackoff = Stopwatch()..start();
      LoggerService.e('ServerTimeService error: $e');
      LoggerService.d('Falling back to local time');
      return _now();
    }
  }

  /// 현재 날짜 가져오기 (서버 시간 기준)
  static Future<DateTime> getCurrentDate() async {
    final serverTime = await getServerTime();
    return DateTime(serverTime.year, serverTime.month, serverTime.day);
  }

  /// 시스템 시간 조작 감지
  static Future<bool> detectTimeManipulation() async {
    try {
      if (_timeOffset == null) {
        // 첫 호출이면 조작 없음
        await getServerTime();
        return false;
      }

      final previousOffset = _timeOffset;
      final serverTime = await getServerTime();
      final localTime = _now();
      final currentOffset =
          serverTime.millisecondsSinceEpoch - localTime.millisecondsSinceEpoch;

      // 오프셋 변화가 5분 이상이면 시간 조작 의심
      final offsetDiff = (currentOffset - previousOffset!).abs();
      if (offsetDiff > const Duration(minutes: 5).inMilliseconds) {
        LoggerService.d(
          'Time manipulation detected! Offset changed by ${offsetDiff}ms',
        );
        return true;
      }

      return false;
    } catch (e) {
      LoggerService.e('Error detecting time manipulation: $e');
      return false;
    }
  }

  /// 캐시 초기화
  static void clearCache() {
    _cachedServerTime = null;
    _cacheAge = null;
    _failureBackoff = null;
    _timeOffset = null;
    LoggerService.d('ServerTimeService cache cleared');
  }

  /// 초기화 (앱 시작 시 호출)
  static Future<void> initialize() async {
    try {
      LoggerService.d('ServerTimeService initializing...');
      await getServerTime();
      LoggerService.i('ServerTimeService initialized');
    } catch (e) {
      LoggerService.e('ServerTimeService initialization failed: $e');
    }
  }
}
