import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review_ai/models/food_category.dart';
import 'package:review_ai/models/food_recommendation.dart';
import 'package:review_ai/services/recommendation_service.dart';
import 'package:flutter/material.dart';

// =============================================================================
// StateNotifier 클래스들
// =============================================================================

/// 음식 히스토리를 관리하는 StateNotifier
class FoodHistoryNotifier extends StateNotifier<List<String>> {
  FoodHistoryNotifier() : super([]);

  /// 음식을 히스토리에 추가 (중복 제거)
  void addFood(String foodName) {
    if (foodName.isEmpty) return;

    if (!state.contains(foodName)) {
      state = [...state, foodName];

      // 최대 50개까지만 유지 (메모리 관리)
      if (state.length > 50) {
        state = state.sublist(state.length - 50);
      }
    }
  }

  /// 특정 음식을 히스토리에서 제거
  void removeFood(String foodName) {
    state = state.where((food) => food != foodName).toList();
  }

  /// 히스토리 초기화
  void clearHistory() {
    state = [];
  }

  /// 최근 N개의 음식 가져오기
  List<String> getRecentFoods(int count) {
    if (state.length <= count) return List.from(state);
    return state.sublist(state.length - count);
  }
}

/// 추천 목록을 관리하는 StateNotifier
class RecommendationNotifier extends StateNotifier<List<String>> {
  RecommendationNotifier() : super([]);

  void setRecommendations(List<String> recommendations) {
    state = List.from(recommendations);
  }

  void addRecommendation(String recommendation) {
    if (!state.contains(recommendation)) {
      state = [...state, recommendation];
    }
  }

  void removeRecommendation(String recommendation) {
    state = state.where((item) => item != recommendation).toList();
  }

  void clear() {
    state = [];
  }
}

// =============================================================================
// Provider 정의들
// =============================================================================

/// 음식 카테고리 목록 Provider
final foodCategoriesProvider = Provider<List<FoodCategory>>((ref) {
  return const [
    FoodCategory(
      name: '한식',
      imageUrl: 'assets/images/categories/korean.svg',
      color: Color(0xFFFFCDD2), // Red.shade100
    ),
    FoodCategory(
      name: '중식',
      imageUrl: 'assets/images/categories/china.svg',
      color: Color(0xFFFFE0B2), // Orange.shade100
    ),
    FoodCategory(
      name: '일식',
      imageUrl: 'assets/images/categories/japan.svg',
      color: Color(0xFFBBDEFB), // Blue.shade100
    ),
    FoodCategory(
      name: '양식',
      imageUrl: 'assets/images/categories/yangsick.svg',
      color: Color(0xFFC8E6C9), // Green.shade100
    ),
    FoodCategory(
      name: '분식',
      imageUrl: 'assets/images/categories/boonsick.svg',
      color: Color(0xFFE1BEE7), // Purple.shade100
    ),
    FoodCategory(
      name: '아시안',
      imageUrl: 'assets/images/categories/asiafood.svg',
      color: Color(0xFFB2DFDB), // Teal.shade100
    ),
    FoodCategory(
      name: '패스트푸드',
      imageUrl: 'assets/images/categories/fastfood.svg',
      color: Color(0xFFFFF9C4), // Yellow.shade100
    ),
    FoodCategory(
      name: '편의점',
      imageUrl: 'assets/images/categories/CVS.svg',
      color: Color(0xFFFFCCBC), // Deep Orange.shade100
    ),
    FoodCategory(
      name: '카페',
      imageUrl: 'assets/images/categories/cafe.svg',
      color: Color(0xFFD7CCC8), // Brown.shade100
    ),
    FoodCategory(
      name: '상관없음',
      imageUrl: 'assets/images/categories/good.svg',
      color: Color(0xFFF5F5F5), // Grey.shade100
    ),
  ];
});

/// 사용자가 선택한 카테고리 Provider
final selectedCategoryProvider = StateProvider<String?>((ref) => null);

/// 사용자가 최종 선택한 추천 음식 Provider
final selectedFoodProvider = StateProvider<FoodRecommendation?>((ref) => null);

/// 음식 히스토리 Provider
final foodHistoryProvider =
    StateNotifierProvider<FoodHistoryNotifier, List<String>>((ref) {
      return FoodHistoryNotifier();
    });

/// 추천 목록 Provider
final recommendationListProvider =
    StateNotifierProvider<RecommendationNotifier, List<String>>((ref) {
      return RecommendationNotifier();
    });

/// 음식 추천 목록 Provider (카테고리별)
final recommendationProvider = FutureProvider.autoDispose
    .family<List<FoodRecommendation>, String>((ref, category) async {
      try {
        // 서비스에서 추천 목록 가져오기
        final recommendations =
            await RecommendationService.getFoodRecommendations(
              category: category,
            );

        // 추천 목록을 recommendationListProvider에도 동기화
        final recommendationNames = recommendations
            .map((food) => food.name)
            .toList();
        ref
            .read(recommendationListProvider.notifier)
            .setRecommendations(recommendationNames);

        return recommendations;
      } catch (e) {
        // 에러 로깅 (배포 시 적절한 로깅 시스템 사용)
        throw Exception('음식 추천을 가져오는데 실패했습니다: $e');
      }
    });

// =============================================================================
// 유틸리티 함수들
// =============================================================================

/// 카테고리 이름으로 FoodCategory 객체를 찾는 함수
FoodCategory? findCategoryByName(List<FoodCategory> categories, String name) {
  try {
    return categories.firstWhere((category) => category.name == name);
  } catch (e) {
    return null;
  }
}

/// 추천 음식 목록에서 특정 이름의 음식을 찾는 함수
FoodRecommendation? findFoodByName(
  List<FoodRecommendation> foods,
  String name,
) {
  try {
    return foods.firstWhere((food) => food.name == name);
  } catch (e) {
    return null;
  }
}

/// 히스토리에서 중복을 제거하고 최근 항목을 반환하는 함수
List<String> getUniqueRecentHistory(List<String> history, int maxCount) {
  final uniqueHistory = history.toSet().toList();
  if (uniqueHistory.length <= maxCount) return uniqueHistory;
  return uniqueHistory.sublist(uniqueHistory.length - maxCount);
}
