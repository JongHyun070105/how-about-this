import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_ai/data/datasources/recommendation_local_data_source.dart';
import 'package:review_ai/data/models/food_recommendation.dart';

@GenerateNiceMocks([MockSpec<SharedPreferences>()])
void main() {
  late RecommendationLocalDataSourceImpl dataSource;

  setUp(() {
    dataSource = RecommendationLocalDataSourceImpl();
    // RecommendationLocalDataSourceImpl은 내부에서 SharedPreferences.getInstance()를 호출하므로
    // SharedPreferences.setMockInitialValues를 사용하여 테스트 환경을 구축해야 함.
  });

  group('RecommendationLocalDataSource', () {
    const category = '한식';
    const key = 'recommendation_cache_$category';
    const expiryKey = '${key}_expiry';

    final recommendations = [
      const FoodRecommendation(name: '김치찌개', imageUrl: 'url1'),
      const FoodRecommendation(name: '불고기', imageUrl: 'url2'),
    ];

    test('getCachedRecommendations returns data when cache is valid', () async {
      final cacheData = {
        'category': category,
        'data': recommendations.map((e) => e.toJson()).toList(),
        'cachedAt': DateTime.now().toIso8601String(),
      };

      final expiryTime = DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String();

      SharedPreferences.setMockInitialValues({
        key: jsonEncode(cacheData),
        expiryKey: expiryTime,
      });

      final result = await dataSource.getCachedRecommendations(category);

      expect(result, isNotNull);
      expect(result!.length, 2);
      expect(result[0].name, '김치찌개');
    });

    test(
      'getCachedRecommendations returns null when cache is expired',
      () async {
        final cacheData = {
          'category': category,
          'data': recommendations.map((e) => e.toJson()).toList(),
          'cachedAt': DateTime.now()
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
        };

        final expiryTime = DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toIso8601String();

        SharedPreferences.setMockInitialValues({
          key: jsonEncode(cacheData),
          expiryKey: expiryTime,
        });

        final result = await dataSource.getCachedRecommendations(category);

        expect(result, isNull);
      },
    );

    test(
      'getCachedRecommendations clears entries with malformed expiry',
      () async {
        SharedPreferences.setMockInitialValues({
          key: jsonEncode({
            'category': category,
            'data': recommendations.map((e) => e.toJson()).toList(),
          }),
          expiryKey: 'not-a-date',
        });

        final result = await dataSource.getCachedRecommendations(category);

        expect(result, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(key), isNull);
        expect(prefs.getString(expiryKey), isNull);
      },
    );

    test('cacheRecommendations stores data correctly', () async {
      SharedPreferences.setMockInitialValues({});

      await dataSource.cacheRecommendations(category, recommendations);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), isNotNull);
      expect(prefs.getString(expiryKey), isNotNull);

      final storedData = jsonDecode(prefs.getString(key)!);
      expect(storedData['category'], category);
      expect((storedData['data'] as List).length, 2);
    });
  });
}
