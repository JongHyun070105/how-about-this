import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:review_ai/data/datasources/recommendation_local_data_source.dart';
import 'package:review_ai/data/datasources/recommendation_remote_data_source.dart';
import 'package:review_ai/data/repositories/recommendation_repository_impl.dart';
import 'package:review_ai/data/models/food_recommendation.dart' as model;

@GenerateNiceMocks([
  MockSpec<RecommendationRemoteDataSource>(),
  MockSpec<RecommendationLocalDataSource>(),
])
import 'recommendation_repository_impl_test.mocks.dart';

void main() {
  late RecommendationRepositoryImpl repository;
  late MockRecommendationRemoteDataSource mockRemoteDataSource;
  late MockRecommendationLocalDataSource mockLocalDataSource;

  setUp(() {
    mockRemoteDataSource = MockRecommendationRemoteDataSource();
    mockLocalDataSource = MockRecommendationLocalDataSource();
    repository = RecommendationRepositoryImpl(
      remoteDataSource: mockRemoteDataSource,
      localDataSource: mockLocalDataSource,
    );
  });

  group('RecommendationRepositoryImpl', () {
    const category = '한식';
    final recentFoods = ['비빔밥'];
    final foodModels = [
      const model.FoodRecommendation(name: '김치찌개', imageUrl: 'url1'),
    ];

    test('getRecommendations returns cached data when available', () async {
      when(
        mockLocalDataSource.getCachedRecommendations(category),
      ).thenAnswer((_) async => foodModels);

      final result = await repository.getRecommendations(
        category: category,
        recentFoods: recentFoods,
      );

      expect(result.length, 1);
      expect(result[0].name, '김치찌개');
      verify(mockLocalDataSource.getCachedRecommendations(category)).called(1);
      verifyZeroInteractions(mockRemoteDataSource);
    });

    test('최근 먹은 음식이 캐시에 있으면 새 추천을 받아온다', () async {
      const recentlyEaten = model.FoodRecommendation(
        name: '비빔밥',
        imageUrl: 'cached-url',
      );
      const refreshedRecommendation = model.FoodRecommendation(
        name: '불고기',
        imageUrl: 'fresh-url',
      );
      when(
        mockLocalDataSource.getCachedRecommendations(category),
      ).thenAnswer((_) async => [recentlyEaten]);
      when(
        mockRemoteDataSource.getFoodRecommendations(
          category: category,
          recentFoods: recentFoods,
        ),
      ).thenAnswer((_) async => [refreshedRecommendation]);

      final result = await repository.getRecommendations(
        category: category,
        recentFoods: recentFoods,
      );

      expect(result.single.name, '불고기');
      verify(
        mockRemoteDataSource.getFoodRecommendations(
          category: category,
          recentFoods: recentFoods,
        ),
      ).called(1);
    });

    test(
      'getRecommendations fetches from remote and caches when no cache available',
      () async {
        when(
          mockLocalDataSource.getCachedRecommendations(category),
        ).thenAnswer((_) async => null);
        when(
          mockRemoteDataSource.getFoodRecommendations(
            category: category,
            recentFoods: recentFoods,
          ),
        ).thenAnswer((_) async => foodModels);

        final result = await repository.getRecommendations(
          category: category,
          recentFoods: recentFoods,
        );

        expect(result.length, 1);
        expect(result[0].name, '김치찌개');
        verify(
          mockLocalDataSource.getCachedRecommendations(category),
        ).called(1);
        verify(
          mockRemoteDataSource.getFoodRecommendations(
            category: category,
            recentFoods: recentFoods,
          ),
        ).called(1);
        verify(
          mockLocalDataSource.cacheRecommendations(category, foodModels),
        ).called(1);
      },
    );
  });
}
