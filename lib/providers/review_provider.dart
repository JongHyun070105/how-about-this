import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review_ai/models/review_state.dart';
import 'package:review_ai/services/persistent_storage_service.dart';

// 리뷰 기록 항목을 위한 데이터 모델
class ReviewHistoryEntry {
  final String foodName;
  final String? restaurantName;
  final String? imagePath; // 이미지 파일 경로
  final String category;
  final double deliveryRating;
  final double tasteRating;
  final double portionRating;
  final double priceRating;
  final String reviewStyle;
  final String? emphasis;
  final List<String> generatedReviews;
  final DateTime createdAt;

  ReviewHistoryEntry({
    required this.foodName,
    this.restaurantName,
    this.imagePath,
    required this.category,
    required this.deliveryRating,
    required this.tasteRating,
    required this.portionRating,
    required this.priceRating,
    required this.reviewStyle,
    this.emphasis,
    required this.generatedReviews,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'foodName': foodName,
    'restaurantName': restaurantName,
    'imagePath': imagePath,
    'category': category,
    'deliveryRating': deliveryRating,
    'tasteRating': tasteRating,
    'portionRating': portionRating,
    'priceRating': priceRating,
    'reviewStyle': reviewStyle,
    'emphasis': emphasis,
    'generatedReviews': generatedReviews,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ReviewHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ReviewHistoryEntry(
      foodName: json['foodName'] ?? '',
      restaurantName: json['restaurantName'] as String?,
      imagePath: json['imagePath'] as String?,
      category: json['category'] ?? '기타',
      deliveryRating: (json['deliveryRating'] as num?)?.toDouble() ?? 0.0,
      tasteRating: (json['tasteRating'] as num?)?.toDouble() ?? 0.0,
      portionRating: (json['portionRating'] as num?)?.toDouble() ?? 0.0,
      priceRating: (json['priceRating'] as num?)?.toDouble() ?? 0.0,
      reviewStyle: json['reviewStyle'] ?? '일반',
      emphasis: json['emphasis'] as String?,
      generatedReviews: List<String>.from(json['generatedReviews'] ?? []),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

class ReviewNotifier extends StateNotifier<ReviewState> {
  ReviewNotifier() : super(ReviewState());

  void setImage(File? image) {
    state = state.copyWith(image: image);
  }

  void setFoodName(String foodName) {
    state = state.copyWith(foodName: foodName);
  }

  void setRestaurantName(String restaurantName) {
    state = state.copyWith(restaurantName: restaurantName);
  }

  void setCategory(String category) {
    state = state.copyWith(category: category);
  }

  void setEmphasis(String emphasis) {
    state = state.copyWith(emphasis: emphasis);
  }

  void setDeliveryRating(double rating) {
    state = state.copyWith(deliveryRating: rating);
  }

  void setTasteRating(double rating) {
    state = state.copyWith(tasteRating: rating);
  }

  void setPortionRating(double rating) {
    state = state.copyWith(portionRating: rating);
  }

  void setPriceRating(double rating) {
    state = state.copyWith(priceRating: rating);
  }

  void setSelectedReviewStyle(String style) {
    state = state.copyWith(selectedReviewStyle: style);
  }

  void setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  void setGeneratedReviews(List<String> reviews) {
    state = state.copyWith(generatedReviews: reviews);
  }

  void reset() {
    state = ReviewState();
  }
}

final reviewProvider = StateNotifierProvider<ReviewNotifier, ReviewState>((
  ref,
) {
  return ReviewNotifier();
});

final reviewStylesProvider = Provider<List<String>>(
  (ref) => ['재미있게', '전문가처럼', '간결하게', 'SNS 스타일', '감성적으로'],
);

class ReviewHistoryNotifier extends StateNotifier<List<ReviewHistoryEntry>> {
  final PersistentStorageService _storageService = PersistentStorageService();
  static const String _historyFile = 'review_history.json';

  ReviewHistoryNotifier() : super([]) {
    loadHistory();
  }

  Future<void> loadHistory() async {
    try {
      debugPrint('📂 리뷰 히스토리 로드 시작');
      final historyJson = await _storageService.getValue<List<dynamic>>(
        _historyFile,
        'history',
      );
      if (historyJson == null) {
        debugPrint('📂 리뷰 히스토리 없음 (처음 실행 또는 삭제됨)');
        state = [];
        return;
      }

      final entries = historyJson
          .map(
            (data) => ReviewHistoryEntry.fromJson(data as Map<String, dynamic>),
          )
          .toList();
      debugPrint('📂 리뷰 히스토리 로드 완료: ${entries.length}개');
      state = entries;
    } catch (e) {
      debugPrint('리뷰 히스토리 로드 오류: $e');
      await clearHistory();
    }
  }

  Future<void> addReview(ReviewHistoryEntry newEntry) async {
    try {
      List<ReviewHistoryEntry> currentHistory = [...state];

      final now = DateTime.now();
      bool isDuplicate = currentHistory.any((entry) {
        final timeDiff = now.difference(entry.createdAt).inMinutes;
        return timeDiff <= 1 &&
            entry.foodName == newEntry.foodName &&
            listEquals(entry.generatedReviews, newEntry.generatedReviews);
      });

      if (!isDuplicate) {
        currentHistory.add(newEntry);
        if (currentHistory.length > 50) {
          currentHistory.removeAt(0);
        }

        final historyJson = currentHistory
            .map((entry) => entry.toJson())
            .toList();
        await _storageService.setValue(_historyFile, 'history', historyJson);
        debugPrint(
          '💾 리뷰 저장 완료: ${newEntry.foodName} (총 ${currentHistory.length}개)',
        );
        state = currentHistory;
      } else {
        debugPrint('중복 리뷰 감지, 저장하지 않음');
      }
    } catch (e) {
      debugPrint('리뷰 저장 오류: $e');
    }
  }

  Future<void> deleteReview(DateTime createdAt) async {
    try {
      List<ReviewHistoryEntry> currentHistory = [...state];
      currentHistory.removeWhere((entry) => entry.createdAt == createdAt);

      final historyJson = currentHistory
          .map((entry) => entry.toJson())
          .toList();
      await _storageService.setValue(_historyFile, 'history', historyJson);
      state = currentHistory;
    } catch (e) {
      debugPrint('Error deleting review from history: $e');
    }
  }

  Future<void> clearHistory() async {
    try {
      await _storageService.clearFile(_historyFile);
      state = [];
    } catch (e) {
      debugPrint('Error clearing review history: $e');
    }
  }
}

final reviewHistoryProvider =
    StateNotifierProvider<ReviewHistoryNotifier, List<ReviewHistoryEntry>>(
      (ref) => ReviewHistoryNotifier(),
    );

void resetAllProviders(WidgetRef ref) {
  ref.read(reviewProvider.notifier).reset();
}
