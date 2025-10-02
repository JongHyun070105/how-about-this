import 'dart:convert';
import 'package:flutter/foundation.dart';
// dotenv는 더 이상 사용하지 않음 (API 키가 서버로 이전됨)
import 'package:review_ai/models/food_recommendation.dart';
import 'package:review_ai/services/api_proxy_service.dart';
import 'package:review_ai/config/api_config.dart';
import 'user_preference_service.dart';
import 'dart:math';
import 'package:review_ai/config/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class RecommendationService {
  static const String _cacheKeyPrefix = 'recommendation_cache_';
  static const Duration _cacheExpiration = Duration(hours: 24);

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

    final apiProxyService = ApiProxyService(http.Client(), ApiConfig.proxyUrl);

    // 개인화 추천 사용 (타 카테고리 혼동 방지)
    final prompt = await apiProxyService.buildPersonalizedRecommendationPrompt(
      category: category,
      recentFoods: [], // 빈 배열로 최근 음식 제외 기능 비활성화
    );

    try {
      final response = await apiProxyService.generateContent(prompt);
      final jsonString =
          response['candidates'][0]['content']['parts'][0]['text'];

      if (jsonString == null) {
        throw Exception('Gemini API로부터 응답을 받지 못했습니다.');
      }

      final cleanedJson = jsonString
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final List<dynamic> decodedList = jsonDecode(cleanedJson);

      final recommendations = decodedList
          .map((item) => FoodRecommendation.fromJson(item))
          .toList();

      await _saveToCache(cacheKey, recommendations);

      return recommendations;
    } catch (e) {
      debugPrint('Gemini API 호출 또는 파싱 오류: $e');
      return Future.error('음식 추천을 받아오는 데 실패했습니다. 다시 시도해주세요.');
    }
  }

  static Future<void> _saveToCache(
    String key,
    List<FoodRecommendation> data,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = data.map((e) => e.toJson()).toList();
    final encodedData = jsonEncode(jsonList);
    final expirationTime = DateTime.now()
        .add(_cacheExpiration)
        .toIso8601String();

    await prefs.setString(key, encodedData);
    await prefs.setString('${key}_expiry', expirationTime);
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
      final decodedList = jsonDecode(encodedData) as List;
      return decodedList
          .map((item) => FoodRecommendation.fromJson(item))
          .toList();
    } catch (e) {
      debugPrint('Error decoding cached data: $e');
      await prefs.remove(key);
      await prefs.remove('${key}_expiry');
      return null;
    }
  }

  static FoodRecommendation pickSmartFood(
    List<FoodRecommendation> foods,
    List<String> recentFoods,
    UserPreferenceAnalysis preferences,
  ) {
    if (foods.isEmpty) {
      throw Exception("추천 가능한 음식이 없습니다.");
    }

    final random = Random();

    List<FoodRecommendation> available = foods
        .where((f) => !recentFoods.contains(f.name))
        .where((f) => !preferences.dislikedFoods.contains(f.name))
        .toList();

    if (available.isEmpty) {
      recentFoods.clear();
      available = foods
          .where((f) => !preferences.dislikedFoods.contains(f.name))
          .toList();

      if (available.isEmpty) {
        available = List.from(foods);
      }
    }

    if (preferences.preferredFoods.isNotEmpty) {
      final preferredAvailable = available
          .where((f) => preferences.preferredFoods.contains(f.name))
          .toList();

      if (preferredAvailable.isNotEmpty && random.nextDouble() < 0.7) {
        available = preferredAvailable;
      }
    }

    final chosen = available[random.nextInt(available.length)];

    recentFoods.add(chosen.name);
    if (recentFoods.length > AppConstants.recentFoodsLimit) {
      recentFoods.removeAt(0);
    }

    return chosen;
  }

  static Future<Map<String, dynamic>> getUserStats() async {
    final history = await UserPreferenceService.getFoodSelectionHistory();
    final analysis = await UserPreferenceService.analyzeUserPreferences();

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
    };
  }
}
