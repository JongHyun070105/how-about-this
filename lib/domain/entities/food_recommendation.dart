import 'package:equatable/equatable.dart';

class FoodRecommendation extends Equatable {
  final String name;
  final String? imageUrl;

  const FoodRecommendation({required this.name, this.imageUrl});

  @override
  List<Object?> get props => [name, imageUrl];
}
