import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:review_ai/config/api_config.dart';
import 'package:review_ai/services/auth_service.dart';

/// 서버 시간 서비스 (시스템 시간 조작 방지)
class ServerTimeService {
  static DateTime? _cachedServerTime;
  static DateTime? _cacheTimestamp;
  static int? _timeOffset; // 서버 시간 - 로컬 시간 (밀리초)

  static const Duration _cacheExpiry = Duration(minutes: 5);

  /// 서버 시간 가져오기 (5분 캐싱)
  static Future<DateTime> getServerTime() async {
    try {
      // 캐시 확인
      if (_cachedServerTime != null && _cacheTimestamp != null) {
        final cacheAge = DateTime.now().difference(_cacheTimestamp!);
        if (cacheAge < _cacheExpiry) {
          // 캐시된 시간 + 경과 시간
          final serverTime = _cachedServerTime!.add(cacheAge);
          debugPrint('Using cached server time: $serverTime');
          return serverTime;
        }
      }

      // 서버에서 시간 가져오기
      debugPrint('Fetching server time from API');
      final token = await AuthService.getValidAccessToken();

      final response = await http
          .get(
            Uri.parse('${ApiConfig.proxyUrl}/api/server-time'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final serverTimeStr = data['serverTime'] as String;
        final serverTimestamp = data['timestamp'] as int;

        final serverTime = DateTime.parse(serverTimeStr);
        final localTime = DateTime.now();

        // 시간 오프셋 계산 (서버 - 로컬)
        _timeOffset = serverTimestamp - localTime.millisecondsSinceEpoch;

        // 캐시 저장
        _cachedServerTime = serverTime;
        _cacheTimestamp = localTime;

        debugPrint('Server time fetched: $serverTime');
        debugPrint('Time offset: ${_timeOffset}ms');

        return serverTime;
      } else {
        throw Exception('Failed to fetch server time: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('ServerTimeService error: $e');

      // 에러 발생 시 로컬 시간 사용 (폴백)
      debugPrint('Falling back to local time');
      return DateTime.now();
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

      final serverTime = await getServerTime();
      final localTime = DateTime.now();
      final currentOffset =
          serverTime.millisecondsSinceEpoch - localTime.millisecondsSinceEpoch;

      // 오프셋 변화가 5분 이상이면 시간 조작 의심
      final offsetDiff = (currentOffset - _timeOffset!).abs();
      if (offsetDiff > Duration(minutes: 5).inMilliseconds) {
        debugPrint(
          'Time manipulation detected! Offset changed by ${offsetDiff}ms',
        );
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error detecting time manipulation: $e');
      return false;
    }
  }

  /// 캐시 초기화
  static void clearCache() {
    _cachedServerTime = null;
    _cacheTimestamp = null;
    _timeOffset = null;
    debugPrint('ServerTimeService cache cleared');
  }

  /// 초기화 (앱 시작 시 호출)
  static Future<void> initialize() async {
    try {
      debugPrint('ServerTimeService initializing...');
      await getServerTime();
      debugPrint('ServerTimeService initialized');
    } catch (e) {
      debugPrint('ServerTimeService initialization failed: $e');
    }
  }
}
