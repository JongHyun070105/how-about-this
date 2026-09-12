import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:review_ai/config/api_config.dart';
import 'package:review_ai/core/utils/logger_service.dart';
import 'package:review_ai/services/auth_service.dart';

enum WeatherCondition {
  clear,
  clouds,
  rain,
  snow,
  thunderstorm,
  drizzle,
  atmosphere, // Mist, Smoke, Haze, etc.
  unknown,
}

class WeatherService {
  final http.Client _client;

  @visibleForTesting
  double Function(double, double, double, double)? mockDistanceBetween;

  @visibleForTesting
  DateTime? mockCurrentTime;

  DateTime get _now => mockCurrentTime ?? DateTime.now();

  // 캐시 필드
  WeatherCondition? _cachedCondition;
  DateTime? _cachedAt;
  double? _cachedLat;
  double? _cachedLng;

  // 캐시 정책 상수
  static const Duration _cacheDuration = Duration(minutes: 15);
  static const double _distanceThresholdMeters = 500.0;

  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  /// 현재 날씨를 가져옵니다 (로컬 캐싱 적용).
  Future<WeatherCondition> getCurrentWeather(double lat, double lng) async {
    // 1. 캐시가 존재하고 유효한지 확인 (15분 이내 & 500m 이내 동일 위치)
    if (_isCacheValid(lat, lng)) {
      LoggerService.d(
        'WeatherService: Using cached weather condition: $_cachedCondition',
      );
      return _cachedCondition!;
    }

    try {
      // Cloudflare Worker 프록시를 통해 날씨 정보 조회 (ApiConfig.proxyUrl 활용)
      final url = Uri.parse('${ApiConfig.proxyUrl}/weather?lat=$lat&lon=$lng');

      String? token;
      try {
        token = await AuthService.getValidAccessToken();
      } catch (e) {
        LoggerService.w('WeatherService: 토큰 획득 실패: $e');
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await _client
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>?;
        if (data != null && data['weather'] is List) {
          final weatherList = data['weather'] as List;
          if (weatherList.isNotEmpty && weatherList[0] is Map) {
            final mainVal = weatherList[0]['main'];
            if (mainVal != null) {
              final main = mainVal.toString().toLowerCase();
              final condition = _mapWeatherCondition(main);

              // 날씨 캐시 업데이트
              _cachedCondition = condition;
              _cachedAt = _now;
              _cachedLat = lat;
              _cachedLng = lng;

              return condition;
            }
          }
        }
        LoggerService.w('WeatherService: Unexpected weather response format');
      } else {
        LoggerService.e(
          'Weather API Error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e, stack) {
      LoggerService.e('Weather Service Error: $e', e, stack);
    }
    return WeatherCondition.unknown;
  }

  /// 캐시 유효성 판단
  bool _isCacheValid(double lat, double lng) {
    if (_cachedCondition == null ||
        _cachedAt == null ||
        _cachedLat == null ||
        _cachedLng == null) {
      return false;
    }

    // 시간 만료 검증
    final timeDiff = _now.difference(_cachedAt!);
    if (timeDiff >= _cacheDuration) {
      return false;
    }

    // 위치 오차 검증 (500m 이내)
    try {
      final distance = mockDistanceBetween != null
          ? mockDistanceBetween!(_cachedLat!, _cachedLng!, lat, lng)
          : Geolocator.distanceBetween(_cachedLat!, _cachedLng!, lat, lng);
      return distance <= _distanceThresholdMeters;
    } catch (e) {
      // Geolocator 계산 실패 시 안전하게 캐시 무효화
      return false;
    }
  }

  /// 날씨 캐시 초기화
  void clearCache() {
    _cachedCondition = null;
    _cachedAt = null;
    _cachedLat = null;
    _cachedLng = null;
  }

  /// 클라이언트 자원 해제
  void dispose() {
    _client.close();
  }

  WeatherCondition _mapWeatherCondition(String main) {
    switch (main) {
      case 'clear':
        return WeatherCondition.clear;
      case 'clouds':
        return WeatherCondition.clouds;
      case 'rain':
        return WeatherCondition.rain;
      case 'snow':
        return WeatherCondition.snow;
      case 'thunderstorm':
        return WeatherCondition.thunderstorm;
      case 'drizzle':
        return WeatherCondition.drizzle;
      case 'mist':
      case 'smoke':
      case 'haze':
      case 'dust':
      case 'fog':
      case 'sand':
      case 'ash':
      case 'squall':
      case 'tornado':
        return WeatherCondition.atmosphere;
      default:
        return WeatherCondition.unknown;
    }
  }
}
