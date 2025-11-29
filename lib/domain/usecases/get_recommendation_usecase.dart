import '../entities/food_recommendation.dart';
import '../repositories/recommendation_repository.dart';

class GetRecommendationUseCase {
  final RecommendationRepository repository;

  GetRecommendationUseCase(this.repository);

  Future<FoodRecommendation> call({
    required String category,
    required List<String> recentFoods,
  }) {
    return repository.getRecommendation(
      category: category,
      recentFoods: recentFoods,
    );
  }
}
