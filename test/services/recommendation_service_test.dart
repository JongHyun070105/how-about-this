import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/models/food_recommendation.dart';
import 'package:review_ai/services/recommendation_service.dart';
import 'package:review_ai/services/user_preference_service.dart';

void main() {
  group('RecommendationService Tests', () {
    group('pickSmartFood', () {
      test('추천 가능한 음식이 없으면 예외를 던진다', () {
        // Arrange
        final foods = <FoodRecommendation>[];
        final recentFoods = <String>[];
        final preferences = UserPreferenceAnalysis(
          preferredFoods: [],
          preferredCategories: [],
          dislikedFoods: [],
          categoryScores: {},
        );

        // Act & Assert
        expect(
          () => RecommendationService.pickSmartFood(
            foods,
            recentFoods,
            preferences,
          ),
          throwsException,
        );
      });

      test('싫어하는 음식은 제외된다', () {
        // Arrange
        final foods = [
          const FoodRecommendation(name: '짜장면'),
          const FoodRecommendation(name: '짬뽕'),
        ];
        final recentFoods = <String>[];
        final preferences = UserPreferenceAnalysis(
          preferredFoods: [],
          preferredCategories: [],
          dislikedFoods: ['짜장면'],
          categoryScores: {},
        );

        // Act
        final result = RecommendationService.pickSmartFood(
          foods,
          recentFoods,
          preferences,
        );

        // Assert
        expect(result.name, '짬뽕');
      });

      test('최근 먹은 음식은 제외된다', () {
        // Arrange
        final foods = [
          const FoodRecommendation(name: '김치찌개'),
          const FoodRecommendation(name: '된장찌개'),
        ];
        final recentFoods = ['김치찌개'];
        final preferences = UserPreferenceAnalysis(
          preferredFoods: [],
          preferredCategories: [],
          dislikedFoods: [],
          categoryScores: {},
        );

        // Act
        final result = RecommendationService.pickSmartFood(
          foods,
          recentFoods,
          preferences,
        );

        // Assert
        expect(result.name, '된장찌개');
      });

      test('선택한 음식이 최근 음식 목록에 추가된다', () {
        // Arrange
        final foods = [const FoodRecommendation(name: '비빔밥')];
        final recentFoods = <String>[];
        final preferences = UserPreferenceAnalysis(
          preferredFoods: [],
          preferredCategories: [],
          dislikedFoods: [],
          categoryScores: {},
        );

        // Act
        RecommendationService.pickSmartFood(foods, recentFoods, preferences);

        // Assert
        expect(recentFoods.contains('비빔밥'), true);
      });
    });
  });
}

