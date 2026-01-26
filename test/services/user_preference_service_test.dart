import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/services/user_preference_service.dart';

void main() {
  group('FoodSelection', () {
    test('should create FoodSelection with required fields', () {
      final selection = FoodSelection(
        foodName: '피자',
        category: '양식',
        selectedAt: DateTime(2024, 1, 1, 12, 0),
        liked: true,
      );

      expect(selection.foodName, '피자');
      expect(selection.category, '양식');
      expect(selection.liked, true);
      expect(selection.selectedAt, DateTime(2024, 1, 1, 12, 0));
    });

    test('toJson should return correct map', () {
      final selection = FoodSelection(
        foodName: '김치찌개',
        category: '한식',
        selectedAt: DateTime(2024, 1, 15, 18, 30),
        liked: false,
      );

      final json = selection.toJson();

      expect(json['foodName'], '김치찌개');
      expect(json['category'], '한식');
      expect(json['liked'], false);
      expect(json['selectedAt'], '2024-01-15T18:30:00.000');
    });

    test('fromJson should create FoodSelection from map', () {
      final json = {
        'foodName': '초밥',
        'category': '일식',
        'selectedAt': '2024-02-20T19:00:00.000',
        'liked': true,
      };

      final selection = FoodSelection.fromJson(json);

      expect(selection.foodName, '초밥');
      expect(selection.category, '일식');
      expect(selection.liked, true);
      expect(selection.selectedAt, DateTime(2024, 2, 20, 19, 0));
    });

    test('toJson and fromJson should be reversible', () {
      final original = FoodSelection(
        foodName: '떡볶이',
        category: '분식',
        selectedAt: DateTime(2024, 3, 10, 14, 30),
        liked: true,
      );

      final json = original.toJson();
      final restored = FoodSelection.fromJson(json);

      expect(restored.foodName, original.foodName);
      expect(restored.category, original.category);
      expect(restored.liked, original.liked);
      expect(restored.selectedAt, original.selectedAt);
    });
  });

  group('UserPreferenceAnalysis', () {
    test('should create UserPreferenceAnalysis with required fields', () {
      final analysis = UserPreferenceAnalysis(
        preferredFoods: ['피자', '파스타'],
        dislikedFoods: ['낙지', '번데기'],
        preferredCategories: ['양식', '한식'],
        categoryScores: {'양식': 0.8, '한식': 0.7, '일식': 0.5},
      );

      expect(analysis.preferredFoods.length, 2);
      expect(analysis.dislikedFoods.length, 2);
      expect(analysis.preferredCategories.length, 2);
      expect(analysis.categoryScores['양식'], 0.8);
    });

    test('should handle empty lists correctly', () {
      final analysis = UserPreferenceAnalysis(
        preferredFoods: [],
        dislikedFoods: [],
        preferredCategories: [],
        categoryScores: {},
      );

      expect(analysis.preferredFoods, isEmpty);
      expect(analysis.dislikedFoods, isEmpty);
      expect(analysis.preferredCategories, isEmpty);
      expect(analysis.categoryScores, isEmpty);
    });
  });
}
