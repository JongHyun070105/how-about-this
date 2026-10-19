import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/food_recommendation.dart';
import 'package:review_ai/core/utils/logger_service.dart';

abstract class RecommendationLocalDataSource {
  Future<List<FoodRecommendation>?> getCachedRecommendations(String category);
  Future<void> cacheRecommendations(
    String category,
    List<FoodRecommendation> recommendations,
  );
  Future<void> clearCache(String category);
}

class RecommendationLocalDataSourceImpl
    implements RecommendationLocalDataSource {
  static const String _cacheKeyPrefix = 'recommendation_cache_';
  static const Duration _cacheExpiration = Duration(hours: 1);

  @override
  Future<List<FoodRecommendation>?> getCachedRecommendations(
    String category,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cacheKeyPrefix$category';

    final encodedData = prefs.getString(key);
    final expiryTimeStr = prefs.getString('${key}_expiry');

    if (encodedData == null || expiryTimeStr == null) return null;

    try {
      final expiryTime = DateTime.parse(expiryTimeStr);
      if (DateTime.now().isAfter(expiryTime)) {
        await clearCache(category);
        return null;
      }

      final decoded = jsonDecode(encodedData);
      if (decoded is Map<String, dynamic> && decoded['category'] == category) {
        final dataList = decoded['data'] as List;
        return dataList
            .map((item) => FoodRecommendation.fromJson(item))
            .toList();
      }
      return null;
    } catch (e) {
      LoggerService.e('Error reading cached recommendations', e);
      await clearCache(category);
      return null;
    }
  }

  @override
  Future<void> cacheRecommendations(
    String category,
    List<FoodRecommendation> recommendations,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cacheKeyPrefix$category';

    final cacheData = {
      'category': category,
      'data': recommendations.map((e) => e.toJson()).toList(),
      'cachedAt': DateTime.now().toIso8601String(),
    };

    final encodedData = jsonEncode(cacheData);
    final expirationTime = DateTime.now()
        .add(_cacheExpiration)
        .toIso8601String();

    await prefs.setString(key, encodedData);
    await prefs.setString('${key}_expiry', expirationTime);
  }

  @override
  Future<void> clearCache(String category) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cacheKeyPrefix$category';
    await prefs.remove(key);
    await prefs.remove('${key}_expiry');
  }
}
