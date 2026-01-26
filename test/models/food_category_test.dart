import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/models/food_category.dart';

void main() {
  group('FoodCategory', () {
    test('should create FoodCategory with required fields', () {
      const category = FoodCategory(
        name: '한식',
        imageUrl: 'assets/images/categories/korean.svg',
        color: Colors.orange,
      );

      expect(category.name, '한식');
      expect(category.imageUrl, 'assets/images/categories/korean.svg');
      expect(category.color, Colors.orange);
    });

    test('equality should work correctly', () {
      const category1 = FoodCategory(
        name: '일식',
        imageUrl: 'assets/images/categories/japanese.svg',
        color: Colors.red,
      );
      const category2 = FoodCategory(
        name: '일식',
        imageUrl: 'assets/images/categories/japanese.svg',
        color: Colors.red,
      );
      const category3 = FoodCategory(
        name: '양식',
        imageUrl: 'assets/images/categories/western.svg',
        color: Colors.blue,
      );

      expect(category1, equals(category2));
      expect(category1, isNot(equals(category3)));
    });

    test('hashCode should be consistent with equality', () {
      const category1 = FoodCategory(
        name: '중식',
        imageUrl: 'assets/images/categories/chinese.svg',
        color: Colors.yellow,
      );
      const category2 = FoodCategory(
        name: '중식',
        imageUrl: 'assets/images/categories/chinese.svg',
        color: Colors.yellow,
      );

      expect(category1.hashCode, equals(category2.hashCode));
    });

    test('toString should return readable string', () {
      const category = FoodCategory(
        name: '분식',
        imageUrl: 'assets/images/categories/snack.svg',
        color: Colors.pink,
      );

      final string = category.toString();
      expect(string, contains('FoodCategory'));
      expect(string, contains('분식'));
    });

    test('toJson and fromJson should be reversible', () {
      const original = FoodCategory(
        name: '카페',
        imageUrl: 'assets/images/categories/cafe.svg',
        color: Color(0xFFBBDEFB),
      );

      final json = original.toJson();
      final restored = FoodCategory.fromJson(json);

      expect(restored.name, original.name);
      expect(restored.imageUrl, original.imageUrl);
      expect(restored.color.toARGB32(), original.color.toARGB32());
    });
  });
}
