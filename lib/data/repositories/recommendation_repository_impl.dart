import '../../domain/entities/food_recommendation.dart' as domain;
import '../../domain/repositories/recommendation_repository.dart';
import '../datasources/recommendation_remote_data_source.dart';

class RecommendationRepositoryImpl implements RecommendationRepository {
  final RecommendationRemoteDataSource remoteDataSource;

  RecommendationRepositoryImpl(this.remoteDataSource);

  @override
  Future<domain.FoodRecommendation> getRecommendation({
    required String category,
    required List<String> recentFoods,
  }) async {
    // Data Source로부터 음식 추천 목록을 가져옴
    final recommendations = await remoteDataSource.getFoodRecommendations(
      category: category,
      recentFoods: recentFoods,
    );

    if (recommendations.isEmpty) {
      throw Exception('추천을 불러오지 못했습니다.');
    }

    // 첫 번째 추천을 반환 (또는 스마트 선택 로직을 여기 추가 가능)
    final firstRecommendation = recommendations.first;

    // Model을 Entity로 변환
    return domain.FoodRecommendation(
      name: firstRecommendation.name,
      imageUrl: firstRecommendation.imageUrl,
    );
  }
}
