import 'dart:io';

class ReviewState {
  final File? image;
  final String foodName;
  final String restaurantName;
  final String category;
  final String emphasis;
  final double deliveryRating;
  final double tasteRating;
  final double portionRating;
  final double priceRating;
  final String selectedReviewStyle;
  final bool isLoading;
  final List<String> generatedReviews;

  const ReviewState({
    this.image,
    this.foodName = '',
    this.restaurantName = '',
    this.category = '',
    this.emphasis = '',
    this.deliveryRating = 0.0,
    this.tasteRating = 0.0,
    this.portionRating = 0.0,
    this.priceRating = 0.0,
    this.selectedReviewStyle = '재미있게',
    this.isLoading = false,
    this.generatedReviews = const [],
  });

  const ReviewState.initial()
    : image = null,
      foodName = '',
      restaurantName = '',
      category = '',
      emphasis = '',
      deliveryRating = 0.0,
      tasteRating = 0.0,
      portionRating = 0.0,
      priceRating = 0.0,
      selectedReviewStyle = '재미있게',
      isLoading = false,
      generatedReviews = const [];

  ReviewState copyWith({
    File? image,
    String? foodName,
    String? restaurantName,
    String? category,
    String? emphasis,
    double? deliveryRating,
    double? tasteRating,
    double? portionRating,
    double? priceRating,
    String? selectedReviewStyle,
    bool? isLoading,
    List<String>? generatedReviews,
  }) {
    return ReviewState(
      image: image ?? this.image,
      foodName: foodName ?? this.foodName,
      restaurantName: restaurantName ?? this.restaurantName,
      category: category ?? this.category,
      emphasis: emphasis ?? this.emphasis,
      deliveryRating: deliveryRating ?? this.deliveryRating,
      tasteRating: tasteRating ?? this.tasteRating,
      portionRating: portionRating ?? this.portionRating,
      priceRating: priceRating ?? this.priceRating,
      selectedReviewStyle: selectedReviewStyle ?? this.selectedReviewStyle,
      isLoading: isLoading ?? this.isLoading,
      generatedReviews: generatedReviews ?? this.generatedReviews,
    );
  }
}
