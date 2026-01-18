import 'package:flutter/foundation.dart';
import 'package:review_ai/services/persistent_storage_service.dart';

// 사용자 선택 기록 모델
class FoodSelection {
  final String foodName;
  final String category;
  final DateTime selectedAt;
  final bool liked; // true: 좋아요, false: 싫어요

  FoodSelection({
    required this.foodName,
    required this.category,
    required this.selectedAt,
    required this.liked,
  });

  Map<String, dynamic> toJson() {
    return {
      'foodName': foodName,
      'category': category,
      'selectedAt': selectedAt.toIso8601String(),
      'liked': liked,
    };
  }

  factory FoodSelection.fromJson(Map<String, dynamic> json) {
    return FoodSelection(
      foodName: json['foodName'],
      category: json['category'],
      selectedAt: DateTime.parse(json['selectedAt']),
      liked: json['liked'],
    );
  }
}

// 사용자 취향 분석 결과
class UserPreferenceAnalysis {
  final List<String> preferredFoods;
  final List<String> dislikedFoods;
  final List<String> preferredCategories;
  final Map<String, double> categoryScores; // 카테고리별 선호도 점수

  UserPreferenceAnalysis({
    required this.preferredFoods,
    required this.dislikedFoods,
    required this.preferredCategories,
    required this.categoryScores,
  });
}

class UserPreferenceService {
  static final PersistentStorageService _storageService =
      PersistentStorageService();
  static const String _userPrefsFile = 'user_preferences.json';

  static const String _selectionHistoryKey = 'food_selection_history';
  static const String _dislikedFoodsKey = 'disliked_foods';
  static const int _maxHistorySize = 100; // 최대 기록 수
  static const String _reviewPromptLikeCountKey = 'review_prompt_like_count';

  // 음식 선택 기록 저장
  static Future<void> recordFoodSelection({
    required String foodName,
    required String category,
    required bool liked,
  }) async {
    final selection = FoodSelection(
      foodName: foodName,
      category: category,
      selectedAt: DateTime.now(),
      liked: liked,
    );

    final history = await getFoodSelectionHistory();
    history.add(selection);

    if (history.length > _maxHistorySize) {
      history.removeAt(0);
    }

    final jsonList = history.map((s) => s.toJson()).toList();
    await _storageService.setValue(
      _userPrefsFile,
      _selectionHistoryKey,
      jsonList,
    );

    if (!liked) {
      await _addDislikedFood(foodName);
    } else {
      int count =
          await _storageService.getValue<int>(
            _userPrefsFile,
            _reviewPromptLikeCountKey,
          ) ??
          0;
      await _storageService.setValue(
        _userPrefsFile,
        _reviewPromptLikeCountKey,
        count + 1,
      );
    }
  }

  // 음식 선택 기록 조회
  static Future<List<FoodSelection>> getFoodSelectionHistory() async {
    final jsonList = await _storageService.getValue<List<dynamic>>(
      _userPrefsFile,
      _selectionHistoryKey,
    );

    if (jsonList == null) return [];

    try {
      return jsonList
          .map((json) => FoodSelection.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('선택 기록 로드 오류: $e');
      return [];
    }
  }

  // 싫어하는 음식 추가
  static Future<void> _addDislikedFood(String foodName) async {
    final dislikedFoods = await getDislikedFoods();

    if (!dislikedFoods.contains(foodName)) {
      dislikedFoods.add(foodName);
      await _storageService.setValue(
        _userPrefsFile,
        _dislikedFoodsKey,
        dislikedFoods,
      );
    }
  }

  // 싫어하는 음식 목록 조회
  static Future<List<String>> getDislikedFoods() async {
    final dislikedList = await _storageService.getValue<List<dynamic>>(
      _userPrefsFile,
      _dislikedFoodsKey,
    );
    return dislikedList?.cast<String>() ?? [];
  }

  // 싫어하는 음식에서 제거
  static Future<void> removeFromDislikedFoods(String foodName) async {
    final dislikedFoods = await getDislikedFoods();
    dislikedFoods.remove(foodName);
    await _storageService.setValue(
      _userPrefsFile,
      _dislikedFoodsKey,
      dislikedFoods,
    );
  }

  // 사용자 취향 분석
  static Future<UserPreferenceAnalysis> analyzeUserPreferences() async {
    final history = await getFoodSelectionHistory();
    final dislikedFoods = await getDislikedFoods();

    if (history.isEmpty) {
      return UserPreferenceAnalysis(
        preferredFoods: [],
        dislikedFoods: dislikedFoods,
        preferredCategories: [],
        categoryScores: {},
      );
    }

    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final recentHistory = history
        .where((s) => s.selectedAt.isAfter(thirtyDaysAgo))
        .toList();

    final likedFoods = recentHistory
        .where((s) => s.liked)
        .map((s) => s.foodName)
        .toSet()
        .toList();

    final categoryScores = _calculateCategoryScores(recentHistory);

    final preferredCategories = categoryScores.entries
        .where((e) => e.value >= 0.6)
        .map((e) => e.key)
        .toList();

    return UserPreferenceAnalysis(
      preferredFoods: likedFoods,
      dislikedFoods: dislikedFoods,
      preferredCategories: preferredCategories,
      categoryScores: categoryScores,
    );
  }

  static Map<String, double> _calculateCategoryScores(
    List<FoodSelection> history,
  ) {
    final categoryScores = <String, double>{};
    final categoryStats = <String, Map<String, int>>{};

    if (history.isEmpty) return {};

    for (final selection in history) {
      final category = selection.category;

      categoryStats.putIfAbsent(category, () => {'liked': 0, 'total': 0});
      categoryStats[category]!['total'] =
          categoryStats[category]!['total']! + 1;

      if (selection.liked) {
        categoryStats[category]!['liked'] =
            categoryStats[category]!['liked']! + 1;
      }
    }

    for (final entry in categoryStats.entries) {
      final category = entry.key;
      final stats = entry.value;
      final likeRatio = stats['liked']! / stats['total']!;
      final frequencyBonus = (stats['total']! / history.length) * 0.3;

      categoryScores[category] = likeRatio + frequencyBonus;
    }
    return categoryScores;
  }

  static Future<Map<String, String>> getCategoryPreferenceTrends() async {
    final history = await getFoodSelectionHistory();

    if (history.length < 2) {
      return {};
    }

    final now = DateTime.now();
    final currentPeriodStart = now.subtract(const Duration(days: 30));
    final previousPeriodStart = now.subtract(const Duration(days: 60));

    final currentPeriodHistory = history
        .where((s) => s.selectedAt.isAfter(currentPeriodStart))
        .toList();
    final previousPeriodHistory = history
        .where(
          (s) =>
              s.selectedAt.isAfter(previousPeriodStart) &&
              s.selectedAt.isBefore(currentPeriodStart),
        )
        .toList();

    final currentScores = _calculateCategoryScores(currentPeriodHistory);
    final previousScores = _calculateCategoryScores(previousPeriodHistory);

    final trends = <String, String>{};

    for (final category in currentScores.keys) {
      final currentScore = currentScores[category]!;
      final previousScore = previousScores[category];

      if (previousScore == null) {
        trends[category] = '신규';
      } else {
        final diff = currentScore - previousScore;
        if (diff > 0.05) {
          trends[category] = '상승';
        } else if (diff < -0.05) {
          trends[category] = '하락';
        } else {
          trends[category] = '유지';
        }
      }
    }

    for (final category in previousScores.keys) {
      if (!currentScores.containsKey(category)) {
        trends[category] = '하락';
      }
    }

    return trends;
  }

  static Future<bool> shouldShowReviewPromptDialog() async {
    final likeCount =
        await _storageService.getValue<int>(
          _userPrefsFile,
          _reviewPromptLikeCountKey,
        ) ??
        0;
    return likeCount > 0 && likeCount % 10 == 0;
  }

  static Future<void> recordReviewPromptDialogShown() async {
    await _storageService.setValue(
      _userPrefsFile,
      _reviewPromptLikeCountKey,
      0,
    );
  }

  /// 요일별 카테고리 선호도 분석
  /// 반환: `Map<int, Map<String, int>>` - 요일(1=월요일...7=일요일) -> 카테고리 -> 횟수
  static Future<Map<int, Map<String, int>>>
  analyzeDayOfWeekPreferences() async {
    final history = await getFoodSelectionHistory();

    // 좋아요를 누른 항목만 필터링
    final likedHistory = history.where((s) => s.liked).toList();

    if (likedHistory.isEmpty) {
      return {};
    }

    // 요일별로 그룹화 (1=월요일, 7=일요일)
    final dayOfWeekStats = <int, Map<String, int>>{};

    for (final selection in likedHistory) {
      final weekday = selection.selectedAt.weekday; // 1-7
      final category = selection.category;

      // 상관없음 카테고리는 제외
      if (category == '상관없음') continue;

      dayOfWeekStats.putIfAbsent(weekday, () => <String, int>{});
      dayOfWeekStats[weekday]![category] =
          (dayOfWeekStats[weekday]![category] ?? 0) + 1;
    }

    return dayOfWeekStats;
  }
}
