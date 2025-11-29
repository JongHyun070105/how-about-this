import 'dart:io';
import '../../domain/repositories/review_repository.dart';
import '../datasources/gemini_remote_data_source.dart';

class ReviewRepositoryImpl implements ReviewRepository {
  final GeminiRemoteDataSource remoteDataSource;

  ReviewRepositoryImpl(this.remoteDataSource);

  @override
  Future<List<String>> generateReviews({
    required String foodName,
    required double deliveryRating,
    required double tasteRating,
    required double portionRating,
    required double priceRating,
    required String reviewStyle,
    File? foodImage,
  }) {
    return remoteDataSource.generateReviews(
      foodName: foodName,
      deliveryRating: deliveryRating,
      tasteRating: tasteRating,
      portionRating: portionRating,
      priceRating: priceRating,
      reviewStyle: reviewStyle,
      foodImage: foodImage,
    );
  }

  @override
  Future<bool> validateImage(File image) {
    return remoteDataSource.validateImage(image);
  }
}
