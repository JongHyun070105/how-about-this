import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:review_ai/models/food_recommendation.dart';
import 'package:review_ai/models/exceptions.dart';
import 'package:review_ai/services/api_proxy_service.dart';
import 'package:review_ai/config/api_config.dart';
import 'user_preference_service.dart';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:review_ai/services/weather_service.dart';

class RecommendationService {
  static const String _cacheKeyPrefix = 'recommendation_cache_';
  static const Duration _cacheExpiration = Duration(hours: 1);

  // HTTP Client 싱글톤 (재사용)
  static final http.Client _httpClient = http.Client();

  static Future<List<FoodRecommendation>> getFoodRecommendations({
    required String category,
  }) async {
    final cacheKey = '$_cacheKeyPrefix$category';

    final cachedData = await _getFromCache(cacheKey);
    if (cachedData != null) {
      debugPrint('Serving recommendation from cache for category: $category');
      return cachedData;
    }

    debugPrint('Cache miss for category: $category. Fetching from API.');

    final apiProxyService = ApiProxyService(_httpClient, ApiConfig.proxyUrl);

    // 최근 7일간 먹은 음식 가져오기
    final history = await UserPreferenceService.getFoodSelectionHistory();
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final recentFoods = history
        .where((s) => s.selectedAt.isAfter(sevenDaysAgo))
        .map((s) => s.foodName)
        .toSet() // 중복 제거
        .toList();

    debugPrint('Recent foods (last 7 days): ${recentFoods.length} items');

    // 개인화 추천 사용 (타 카테고리 혼동 방지)
    final prompt = await apiProxyService.buildPersonalizedRecommendationPrompt(
      category: category,
      recentFoods: recentFoods,
    );

    try {
      final response = await apiProxyService.generateContent(prompt);
      final jsonString =
          response['candidates'][0]['content']['parts'][0]['text'];

      if (jsonString == null) {
        debugPrint('ERROR: No text in Gemini response');
        throw Exception('Gemini API로부터 응답을 받지 못했습니다.');
      }

      debugPrint(
        'Raw Gemini response (first 200 chars): ${jsonString.substring(0, jsonString.length > 200 ? 200 : jsonString.length)}',
      );

      var cleanedJson = jsonString.trim();

      // Remove markdown code blocks if present
      if (cleanedJson.startsWith('```json')) {
        cleanedJson = cleanedJson
            .replaceAll('```json', '')
            .replaceAll('```', '');
      } else if (cleanedJson.startsWith('```')) {
        cleanedJson = cleanedJson.replaceAll('```', '');
      }

      cleanedJson = cleanedJson.trim();

      debugPrint(
        'Cleaned JSON for parsing (first 200 chars): ${cleanedJson.substring(0, cleanedJson.length > 200 ? 200 : cleanedJson.length)}',
      );

      final List<dynamic> decodedList = jsonDecode(cleanedJson);

      debugPrint('AI가 생성한 음식 개수: ${decodedList.length}개');

      final recommendations = decodedList.map((item) {
        if (item is Map<String, dynamic> && item['name'] != null) {
          final cleanedName = (item['name'] as String).replaceFirst(
            RegExp(r'^\d+\.\s*'),
            '',
          );
          item['name'] = cleanedName;
        }
        return FoodRecommendation.fromJson(item);
      }).toList();

      debugPrint('파싱 완료: ${recommendations.length}개 음식 추천');

      await _saveToCache(cacheKey, recommendations);

      return recommendations;
    } catch (e, stackTrace) {
      debugPrint('Gemini API 호출 또는 파싱 오류: $e');
      debugPrint('Stack trace: $stackTrace');

      if (e is NetworkException) {
        throw NetworkException('네트워크 연결을 확인해주세요.');
      } else if (e is ParsingException) {
        throw ParsingException('응답 처리 중 오류가 발생했습니다.');
      } else if (e is GeminiApiException) {
        rethrow; // 이미 적절한 메시지가 있으므로 그대로 전달
      }
      throw ApiException('음식 추천을 받아오는 데 실패했습니다.');
    }
  }

  static Future<void> _saveToCache(
    String key,
    List<FoodRecommendation> data,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    // 카테고리 정보를 포함한 캐시 데이터 구조
    final cacheData = {
      'category': key.replaceFirst(_cacheKeyPrefix, ''),
      'data': data.map((e) => e.toJson()).toList(),
      'cachedAt': DateTime.now().toIso8601String(),
    };

    final encodedData = jsonEncode(cacheData);
    final expirationTime = DateTime.now()
        .add(_cacheExpiration)
        .toIso8601String();

    await prefs.setString(key, encodedData);
    await prefs.setString('${key}_expiry', expirationTime);

    debugPrint('Cache saved for category: ${cacheData['category']}');
  }

  static Future<List<FoodRecommendation>?> _getFromCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final encodedData = prefs.getString(key);
    final expiryTimeStr = prefs.getString('${key}_expiry');

    if (encodedData == null || expiryTimeStr == null) {
      return null;
    }

    final expiryTime = DateTime.parse(expiryTimeStr);
    if (DateTime.now().isAfter(expiryTime)) {
      await prefs.remove(key);
      await prefs.remove('${key}_expiry');
      return null;
    }

    try {
      final decoded = jsonDecode(encodedData);

      // 새로운 캐시 구조 (카테고리 정보 포함)
      if (decoded is Map<String, dynamic> && decoded.containsKey('category')) {
        final cachedCategory = decoded['category'] as String;
        final requestedCategory = key.replaceFirst(_cacheKeyPrefix, '');

        // 카테고리 불일치 검증
        if (cachedCategory != requestedCategory) {
          debugPrint(
            'Cache category mismatch! Cached: $cachedCategory, Requested: $requestedCategory',
          );
          await prefs.remove(key);
          await prefs.remove('${key}_expiry');
          return null;
        }

        final dataList = decoded['data'] as List;
        debugPrint(
          'Cache hit for category: $cachedCategory (${dataList.length} items)',
        );
        return dataList
            .map((item) => FoodRecommendation.fromJson(item))
            .toList();
      }

      // 구버전 캐시 구조 (하위 호환성) - 삭제하고 새로 가져오기
      debugPrint('Old cache format detected, clearing...');
      await prefs.remove(key);
      await prefs.remove('${key}_expiry');
      return null;
    } catch (e) {
      debugPrint('Error decoding cached data: $e');
      await prefs.remove(key);
      await prefs.remove('${key}_expiry');
      return null;
    }
  }

  static ({FoodRecommendation food, String reason}) pickSmartFood(
    List<FoodRecommendation> foods,
    List<String> recentFoods,
    UserPreferenceAnalysis preferences, {
    WeatherCondition? weather,
  }) {
    if (foods.isEmpty) {
      throw Exception("추천 가능한 음식이 없습니다.");
    }

    final random = Random();

    // 1. 기본 필터링 (최근 먹은 음식, 싫어하는 음식 제외)
    List<FoodRecommendation> available = foods
        .where((f) => !recentFoods.contains(f.name))
        .where((f) => !preferences.dislikedFoods.contains(f.name))
        .toList();

    // 필터링 후 남은 음식이 없으면 단계적으로 완화
    if (available.isEmpty) {
      debugPrint(
        'No foods after filtering recent and disliked. Relaxing filters...',
      );
      // 1단계: 최근 음식만 제외하고 다시 시도
      available = foods
          .where((f) => !preferences.dislikedFoods.contains(f.name))
          .toList();

      // 2단계: 그래도 없으면 모든 필터 제거
      if (available.isEmpty) {
        debugPrint('No foods after removing disliked filter. Using all foods.');
        available = List.from(foods);
      }
    }

    // 2. 가중치 기반 추천 시스템
    // 각 음식에 가중치를 부여 (기본 1.0)
    Map<FoodRecommendation, double> weightedFoods = {
      for (var f in available) f: 1.0,
    };

    // 2-1. 선호 음식 가중치 증가 (x 1.5)
    if (preferences.preferredFoods.isNotEmpty) {
      for (var f in available) {
        if (preferences.preferredFoods.contains(f.name)) {
          weightedFoods[f] = (weightedFoods[f] ?? 1.0) * 1.5;
        }
      }
    }

    // 2-2. 날씨 기반 가중치 증가 (x 2.0)
    if (weather != null) {
      _applyWeatherWeights(weightedFoods, weather);
    }

    // 3. 가중치에 따른 확률적 선택
    final selectedFood = _selectWeightedFood(weightedFoods, random);

    // 4. 추천 사유 생성
    String reason = _generateReason(selectedFood, preferences, weather);

    return (food: selectedFood, reason: reason);
  }

  static String _generateReason(
    FoodRecommendation food,
    UserPreferenceAnalysis preferences,
    WeatherCondition? weather,
  ) {
    // 1. 날씨 기반 사유 (가장 우선)
    if (weather != null) {
      if ((weather == WeatherCondition.rain ||
              weather == WeatherCondition.drizzle ||
              weather == WeatherCondition.thunderstorm) &&
          (food.name.contains('전') ||
              food.name.contains('국') ||
              food.name.contains('탕') ||
              food.name.contains('찌개') ||
              food.name.contains('우동') ||
              food.name.contains('짬뽕') ||
              food.name.contains('라면'))) {
        return '비 오는 날엔 역시 따뜻한 국물이나 전이죠! ☔';
      }
      if (weather == WeatherCondition.snow &&
          (food.name.contains('전골') ||
              food.name.contains('탕') ||
              food.name.contains('국'))) {
        return '눈 내리는 날, 몸을 녹여줄 따뜻한 요리 어때요? ❄️';
      }
      if (weather == WeatherCondition.clear &&
          (food.name.contains('냉면') ||
              food.name.contains('소바') ||
              food.name.contains('빙수') ||
              food.name.contains('아이스'))) {
        return '맑은 날씨에 시원한 메뉴가 딱이에요! ☀️';
      }
    }

    // 2. 선호 기반 사유
    if (preferences.preferredFoods.contains(food.name)) {
      return '평소에 좋아하시는 메뉴라 추천해봤어요! 👍';
    }

    // 3. 기본 사유 (랜덤)
    final defaultReasons = [
      '오늘은 이 메뉴가 유난히 맛있어 보이네요! 🤤',
      '기분 전환이 필요할 땐 이 메뉴가 딱이죠!',
      '한 번 드셔보시는 건 어때요?',
      '오늘의 행운의 메뉴입니다! 🍀',
      '탁월한 선택이 될 거예요!',
    ];
    return defaultReasons[Random().nextInt(defaultReasons.length)];
  }

  static void _applyWeatherWeights(
    Map<FoodRecommendation, double> weightedFoods,
    WeatherCondition weather,
  ) {
    for (var entry in weightedFoods.entries) {
      final food = entry.key;
      final name = food.name;
      // final tags = food.tags; // Assuming FoodRecommendation has tags, or we use name/category

      // 비/눈/흐림/천둥번개 -> 국물, 전, 따뜻한 음식
      if (weather == WeatherCondition.rain ||
          weather == WeatherCondition.drizzle ||
          weather == WeatherCondition.thunderstorm ||
          weather == WeatherCondition.snow) {
        if (name.contains('전') || // 파전, 김치전
            name.contains('국') || // 국수, 칼국수, 해장국
            name.contains('탕') || // 갈비탕, 설렁탕
            name.contains('찌개') || // 김치찌개
            name.contains('우동') ||
            name.contains('짬뽕') ||
            name.contains('라면')) {
          weightedFoods[food] = (weightedFoods[food] ?? 1.0) * 2.0;
        }
      }
      // 맑음 (여름 가정) -> 시원한 음식 (냉면, 콩국수 등)
      // 날씨 API에서 온도가 없으므로 'Clear'일 때 일부 시원한 음식 가중치 소폭 증가
      else if (weather == WeatherCondition.clear) {
        if (name.contains('냉면') ||
            name.contains('소바') ||
            name.contains('빙수') ||
            name.contains('아이스')) {
          weightedFoods[food] = (weightedFoods[food] ?? 1.0) * 1.5;
        }
      }
    }
  }

  static FoodRecommendation _selectWeightedFood(
    Map<FoodRecommendation, double> weightedFoods,
    Random random,
  ) {
    double totalWeight = weightedFoods.values.fold(0.0, (sum, w) => sum + w);
    double randomValue = random.nextDouble() * totalWeight;

    for (var entry in weightedFoods.entries) {
      randomValue -= entry.value;
      if (randomValue <= 0) {
        return entry.key;
      }
    }
    return weightedFoods.keys.first;
  }

  static Future<Map<String, dynamic>> getUserStats() async {
    final history = await UserPreferenceService.getFoodSelectionHistory();
    final analysis = await UserPreferenceService.analyzeUserPreferences();
    final dayOfWeekPrefs =
        await UserPreferenceService.analyzeDayOfWeekPreferences();

    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final recentSelections = history
        .where((s) => s.selectedAt.isAfter(thirtyDaysAgo))
        .toList();

    final categoryStats = <String, int>{};
    for (final selection in recentSelections) {
      categoryStats[selection.category] =
          (categoryStats[selection.category] ?? 0) + 1;
    }

    final foodFrequency = <String, int>{};
    final likedSelections = recentSelections.where((s) => s.liked).toList();

    for (final selection in likedSelections) {
      foodFrequency[selection.foodName] =
          (foodFrequency[selection.foodName] ?? 0) + 1;
    }

    final topFoods = foodFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'totalSelections': history.length,
      'recentSelections': recentSelections.length,
      'likedPercentage': recentSelections.isEmpty
          ? 0.0
          : (recentSelections.where((s) => s.liked).length /
                recentSelections.length *
                100),
      'categoryStats': categoryStats,
      'topFoods': topFoods
          .take(5)
          .map((e) => {'name': e.key, 'count': e.value})
          .toList(),
      'preferredCategories': analysis.preferredCategories,
      'dislikedFoodsCount': analysis.dislikedFoods.length,
      'dayOfWeekPreferences': dayOfWeekPrefs, // 요일별 데이터 추가
    };
  }
}
