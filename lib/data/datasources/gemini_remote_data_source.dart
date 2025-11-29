import 'dart:io';

import '../../services/api_proxy_service.dart';

abstract class GeminiRemoteDataSource {
  Future<List<String>> generateReviews({
    required String foodName,
    required double deliveryRating,
    required double tasteRating,
    required double portionRating,
    required double priceRating,
    required String reviewStyle,
    File? foodImage,
  });

  Future<bool> validateImage(File image);
}

class GeminiRemoteDataSourceImpl implements GeminiRemoteDataSource {
  final ApiProxyService _apiProxyService;

  GeminiRemoteDataSourceImpl(this._apiProxyService);

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
    return _apiProxyService.generateReviews(
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
    return _apiProxyService.validateImage(image);
  }
}
