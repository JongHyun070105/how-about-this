import '../entities/food_recommendation.dart';

abstract class RecommendationRepository {
  Future<FoodRecommendation> getRecommendation({
    required String category,
    required List<String> recentFoods,
  });
}
