import 'dart:io';
import '../repositories/review_repository.dart';

class GenerateReviewUseCase {
  final ReviewRepository repository;

  GenerateReviewUseCase(this.repository);

  Future<List<String>> call({
    required String foodName,
    required double deliveryRating,
    required double tasteRating,
    required double portionRating,
    required double priceRating,
    required String reviewStyle,
    File? foodImage,
  }) {
    return repository.generateReviews(
      foodName: foodName,
      deliveryRating: deliveryRating,
      tasteRating: tasteRating,
      portionRating: portionRating,
      priceRating: priceRating,
      reviewStyle: reviewStyle,
      foodImage: foodImage,
    );
  }
}
