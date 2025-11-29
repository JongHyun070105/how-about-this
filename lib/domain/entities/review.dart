import 'package:equatable/equatable.dart';

class Review extends Equatable {
  final String content;
  final String? imageUrl;
  final DateTime createdAt;

  const Review({required this.content, this.imageUrl, required this.createdAt});

  @override
  List<Object?> get props => [content, imageUrl, createdAt];
}
