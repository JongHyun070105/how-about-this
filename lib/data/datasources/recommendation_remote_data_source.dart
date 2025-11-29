import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/food_recommendation.dart';
import '../../services/api_proxy_service.dart';

abstract class RecommendationRemoteDataSource {
  Future<List<FoodRecommendation>> getFoodRecommendations({
    required String category,
    required List<String> recentFoods,
  });
}

class RecommendationRemoteDataSourceImpl
    implements RecommendationRemoteDataSource {
  final ApiProxyService _apiProxyService;

  RecommendationRemoteDataSourceImpl(this._apiProxyService);

  @override
  Future<List<FoodRecommendation>> getFoodRecommendations({
    required String category,
    required List<String> recentFoods,
  }) async {
    try {
      // 개인화 추천 프롬프트 생성
      final prompt = await _apiProxyService
          .buildPersonalizedRecommendationPrompt(
            category: category,
            recentFoods: recentFoods,
          );

      // Gemini API 호출
      final response = await _apiProxyService.generateContent(prompt);
      final jsonString =
          response['candidates'][0]['content']['parts'][0]['text'];

      if (jsonString == null) {
        debugPrint('ERROR: No text in Gemini response');
        throw Exception('Gemini API로부터 응답을 받지 못했습니다.');
      }

      debugPrint(
        'Raw Gemini response (first 200 chars): ${jsonString.substring(0, jsonString.length > 200 ? 200 : jsonString.length)}',
      );

      // JSON 정리
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

      // JSON 파싱
      final List<dynamic> decodedList = jsonDecode(cleanedJson);

      debugPrint('AI가 생성한 음식 개수: ${decodedList.length}개');

      // FoodRecommendation 객체로 변환
      final recommendations = decodedList.map((item) {
        if (item is Map<String, dynamic> && item['name'] != null) {
          // 숫자 접두사 제거 (예: "1. 치킨" -> "치킨")
          final cleanedName = (item['name'] as String).replaceFirst(
            RegExp(r'^\d+\.\s*'),
            '',
          );
          item['name'] = cleanedName;
        }
        return FoodRecommendation.fromJson(item);
      }).toList();

      debugPrint('파싱 완료: ${recommendations.length}개 음식 추천');

      return recommendations;
    } catch (e, stackTrace) {
      debugPrint('Gemini API 호출 또는 파싱 오류: $e');
      debugPrint('Stack trace: $stackTrace');
      throw Exception('음식 추천을 받아오는 데 실패했습니다. 다시 시도해주세요.');
    }
  }
}
