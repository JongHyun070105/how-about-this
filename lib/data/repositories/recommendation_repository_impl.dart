import 'package:review_ai/domain/entities/food_recommendation.dart' as domain;
import 'package:review_ai/domain/repositories/recommendation_repository.dart';
import 'package:review_ai/data/datasources/recommendation_remote_data_source.dart';
import 'package:review_ai/data/datasources/recommendation_local_data_source.dart';

class RecommendationRepositoryImpl implements RecommendationRepository {
  final RecommendationRemoteDataSource remoteDataSource;
  final RecommendationLocalDataSource localDataSource;

  RecommendationRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<List<domain.FoodRecommendation>> getRecommendations({
    required String category,
    required List<String> recentFoods,
  }) async {
    // 1. 로컬 캐시 확인
    final cached = await localDataSource.getCachedRecommendations(category);
    final recentFoodNames = recentFoods
        .map((food) => food.trim().toLowerCase())
        .toSet();
    final cacheIncludesRecentFood =
        cached?.any(
          (recommendation) => recentFoodNames.contains(
            recommendation.name.trim().toLowerCase(),
          ),
        ) ??
        false;

    if (cached != null && cached.isNotEmpty && !cacheIncludesRecentFood) {
      return cached
          .map(
            (m) =>
                domain.FoodRecommendation(name: m.name, imageUrl: m.imageUrl),
          )
          .toList();
    }

    // 2. 캐시 없으면 리모트 fetch
    final remoteModels = await remoteDataSource.getFoodRecommendations(
      category: category,
      recentFoods: recentFoods,
    );

    if (remoteModels.isEmpty) {
      throw Exception('추천을 불러오지 못했습니다.');
    }

    // 3. 로컬 캐시 저장
    await localDataSource.cacheRecommendations(category, remoteModels);

    // 4. Entity로 변환하여 반환
    return remoteModels
        .map(
          (m) => domain.FoodRecommendation(name: m.name, imageUrl: m.imageUrl),
        )
        .toList();
  }
}
