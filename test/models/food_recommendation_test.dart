import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/models/food_recommendation.dart';

void main() {
  group('FoodRecommendation Tests', () {
    test('JSON으로 변환 후 다시 객체로 변환이 정상 작동한다', () {
      // Arrange
      const inputFood = FoodRecommendation(
        name: '짜장면',
        imageUrl: 'https://test.com/image.jpg',
      );

      // Act
      final json = inputFood.toJson();
      final outputFood = FoodRecommendation.fromJson(json);

      // Assert
      expect(outputFood.name, inputFood.name);
      expect(outputFood.imageUrl, inputFood.imageUrl);
    });

    test('같은 이름과 이미지 URL을 가진 객체는 동일하다', () {
      // Arrange
      const food1 = FoodRecommendation(
        name: '김치찌개',
        imageUrl: 'https://test.com/kimchi.jpg',
      );
      const food2 = FoodRecommendation(
        name: '김치찌개',
        imageUrl: 'https://test.com/kimchi.jpg',
      );

      // Act & Assert
      expect(food1, food2);
      expect(food1.hashCode, food2.hashCode);
    });

    test('다른 이름을 가진 객체는 다르다', () {
      // Arrange
      const food1 = FoodRecommendation(name: '짜장면');
      const food2 = FoodRecommendation(name: '짬뽕');

      // Act & Assert
      expect(food1, isNot(food2));
    });

    test('toString이 정상적으로 출력된다', () {
      // Arrange
      const food = FoodRecommendation(name: '탕수육');

      // Act
      final result = food.toString();

      // Assert
      expect(result, contains('탕수육'));
      expect(result, contains('FoodRecommendation'));
    });
  });
}

