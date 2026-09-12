import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/data/models/food_recommendation.dart';
import 'package:review_ai/presentation/screens/restaurant_search_screen.dart';
import 'package:review_ai/presentation/widgets/history/dialogs/recommendation_dialog_widgets.dart';
import 'package:review_ai/services/persistent_storage_service.dart';
import 'package:review_ai/services/user_preference_service.dart';

class MockPersistentStorageService extends PersistentStorageService {
  final Map<String, dynamic> store = {};

  @override
  Future<T?> getValue<T>(String fileName, String key) async {
    return store['$fileName:$key'] as T?;
  }

  @override
  Future<void> setValue<T>(String fileName, String key, T value) async {
    store['$fileName:$key'] = value;
  }
}

void main() {
  late MockPersistentStorageService mockStorage;

  setUp(() {
    mockStorage = MockPersistentStorageService();
    UserPreferenceService.setStorageServiceForTesting(mockStorage);
    UserPreferenceService.clearCache();
  });

  Widget createTestWidget({
    required FoodRecommendation recommended,
    required String category,
  }) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () {
                    showDialog<dynamic>(
                      context: context,
                      builder: (_) => AlertDialog(
                        content: RecommendationDialogButtons(
                          recommended: recommended,
                          category: category,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  testWidgets('좋아요! 버튼 탭 시 취향 저장(liked: true) 후 맛집 검색 화면으로 이동한다', (
    tester,
  ) async {
    const food = FoodRecommendation(name: '김치찌개');
    const category = '한식';

    await tester.pumpWidget(
      createTestWidget(recommended: food, category: category),
    );

    // 다이얼로그 열기
    await tester.tap(find.text('Open Dialog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('좋아요!'), findsOneWidget);
    expect(find.text('다른 걸로'), findsOneWidget);
    expect(find.text('근처 음식점 찾기'), findsNothing);

    // 좋아요! 탭
    await tester.tap(find.text('좋아요!'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 취향 저장 확인
    final history = await UserPreferenceService.getFoodSelectionHistory();
    expect(history.length, 1);
    expect(history.first.foodName, '김치찌개');
    expect(history.first.liked, isTrue);

    // 맛집 검색 화면(RestaurantSearchScreen)으로 이동 확인
    expect(find.byType(RestaurantSearchScreen), findsOneWidget);
  });

  testWidgets('다른 걸로 버튼 탭 시 취향 저장(liked: false) 후 다이얼로그가 true를 반환하며 닫힌다', (
    tester,
  ) async {
    const food = FoodRecommendation(name: '파스타');
    const category = '양식';
    dynamic dialogResult;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      dialogResult = await showDialog<dynamic>(
                        context: context,
                        builder: (_) => const AlertDialog(
                          content: RecommendationDialogButtons(
                            recommended: food,
                            category: category,
                          ),
                        ),
                      );
                    },
                    child: const Text('Open Dialog'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    // 다이얼로그 열기
    await tester.tap(find.text('Open Dialog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 다른 걸로 탭
    await tester.tap(find.text('다른 걸로'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 취향 저장 확인
    final history = await UserPreferenceService.getFoodSelectionHistory();
    expect(history.length, 1);
    expect(history.first.foodName, '파스타');
    expect(history.first.liked, isFalse);

    // 다이얼로그 결과 확인
    expect(dialogResult, isTrue);
    expect(find.byType(RestaurantSearchScreen), findsNothing);
  });
}
