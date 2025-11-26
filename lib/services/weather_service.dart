import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/environment_config.dart';

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
  Future<WeatherCondition> getCurrentWeather(double lat, double lng) async {
    try {
      // Cloudflare Worker 프록시를 통해 날씨 정보 조회
      final backendUrl = EnvironmentConfig.apiBaseUrl;
      final url = Uri.parse('$backendUrl/weather?lat=$lat&lon=$lng');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final weatherList = data['weather'] as List;
        if (weatherList.isNotEmpty) {
          final main = weatherList[0]['main'].toString().toLowerCase();
          return _mapWeatherCondition(main);
        }
      } else {
        debugPrint(
          'Weather API Error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Weather Service Error: $e');
    }
    return WeatherCondition.unknown;
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
