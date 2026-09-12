import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/services/user_preference_service.dart';
import 'package:review_ai/services/persistent_storage_service.dart';

class MockPersistentStorageService extends PersistentStorageService {
  int getCallCount = 0;
  int setCallCount = 0;
  final Map<String, dynamic> store = {};

  @override
  Future<T?> getValue<T>(String fileName, String key) async {
    getCallCount++;
    return store['$fileName:$key'] as T?;
  }

  @override
  Future<void> setValue<T>(String fileName, String key, T value) async {
    setCallCount++;
    store['$fileName:$key'] = value;
  }
}

void main() {
  late MockPersistentStorageService mockStorage;

  setUp(() {
    mockStorage = MockPersistentStorageService();
    UserPreferenceService.setStorageServiceForTesting(mockStorage);
    UserPreferenceService.clearCache();
    UserPreferenceService.mockCurrentTime = null;
  });

  tearDown(() {
    UserPreferenceService.mockCurrentTime = null;
  });

  group('UserPreferenceService 캐싱 및 기능 검증', () {
    test('음식 선택 기록 최초 조회 시 디스크 I/O가 1회 발생한다', () async {
      mockStorage.store['user_preferences.json:food_selection_history'] = [
        {
          'foodName': '치킨',
          'category': '한식',
          'selectedAt': DateTime.now().toIso8601String(),
          'liked': true,
        },
      ];

      final history1 = await UserPreferenceService.getFoodSelectionHistory();
      expect(history1.length, 1);
      expect(history1[0].foodName, '치킨');
      expect(mockStorage.getCallCount, 1);

      // 두 번째 호출 시 메모리 캐시를 사용하여 getCallCount가 여전히 1이어야 함
      final history2 = await UserPreferenceService.getFoodSelectionHistory();
      expect(history2.length, 1);
      expect(mockStorage.getCallCount, 1); // 추가 호출 없음
    });

    test('음식 기록 저장 시 캐시가 즉시 업데이트되며 쓰기 I/O가 발생한다', () async {
      await UserPreferenceService.recordFoodSelection(
        foodName: '피자',
        category: '양식',
        liked: true,
      );

      // 쓰기 I/O 발생 검증
      expect(mockStorage.setCallCount, greaterThan(0));

      // 디스크 호출 횟수를 초기화하고 다시 읽어올 때 캐시를 타서 getCallCount가 0이어야 함
      mockStorage.getCallCount = 0;
      final history = await UserPreferenceService.getFoodSelectionHistory();
      expect(history.length, 1);
      expect(history[0].foodName, '피자');
      expect(mockStorage.getCallCount, 0); // 디스크 안 거침
    });

    test('싫어하는 음식 캐시 동작 검증', () async {
      mockStorage.store['user_preferences.json:disliked_foods'] = ['가지', '오이'];

      final disliked1 = await UserPreferenceService.getDislikedFoods();
      expect(disliked1, contains('가지'));
      expect(mockStorage.getCallCount, 1);

      // 캐싱되어 getCallCount 증가하지 않음
      final disliked2 = await UserPreferenceService.getDislikedFoods();
      expect(disliked2, contains('오이'));
      expect(mockStorage.getCallCount, 1);
    });
  });

  group('UserPreferenceService 취향 및 트렌드 분석 비즈니스 검증', () {
    test(
      '30일 이내의 선호 데이터가 분석에 포함되고 0.6 점수 이상 카테고리가 Preferred Categories로 추출되는지 검증',
      () async {
        final baseTime = DateTime(2026, 7, 10, 12, 0);
        UserPreferenceService.mockCurrentTime = baseTime;

        // 45일 전 한식 좋아요 (30일 초과이므로 제외됨)
        // 10일 전 한식 좋아요 (포함)
        // 5일 전 한식 좋아요 (포함)
        // 2일 전 일식 싫어요 (포함)
        mockStorage.store['user_preferences.json:food_selection_history'] = [
          {
            'foodName': '비빔밥',
            'category': '한식',
            'selectedAt': baseTime
                .subtract(const Duration(days: 45))
                .toIso8601String(),
            'liked': true,
          },
          {
            'foodName': '불고기',
            'category': '한식',
            'selectedAt': baseTime
                .subtract(const Duration(days: 10))
                .toIso8601String(),
            'liked': true,
          },
          {
            'foodName': '치킨',
            'category': '한식',
            'selectedAt': baseTime
                .subtract(const Duration(days: 5))
                .toIso8601String(),
            'liked': true,
          },
          {
            'foodName': '초밥',
            'category': '일식',
            'selectedAt': baseTime
                .subtract(const Duration(days: 2))
                .toIso8601String(),
            'liked': false,
          },
        ];

        final analysis = await UserPreferenceService.analyzeUserPreferences();

        // 한식: recentHistory 내 total=2, liked=2, ratio=1.0. frequencyBonus = (2/3) * 0.3 = 0.2. 최종점수 = 1.2
        // 일식: recentHistory 내 total=1, liked=0, ratio=0.0. frequencyBonus = (1/3) * 0.3 = 0.1. 최종점수 = 0.1
        expect(analysis.preferredCategories, contains('한식'));
        expect(analysis.preferredCategories, isNot(contains('일식')));
        expect(analysis.categoryScores['한식'], closeTo(1.2, 0.001));
        expect(analysis.categoryScores['일식'], closeTo(0.1, 0.001));
      },
    );

    test('getCategoryPreferenceTrends 최근/이전 30일 구간 비교 트렌드 산출 검증', () async {
      final baseTime = DateTime(2026, 7, 10, 12, 0);
      UserPreferenceService.mockCurrentTime = baseTime;

      mockStorage.store['user_preferences.json:food_selection_history'] = [
        // 이전 구간(30~60일 전): 한식 total=2, liked=1, ratio=0.5, bonus=(2/2)*0.3=0.3, 총점=0.8
        {
          'foodName': '김치찌개',
          'category': '한식',
          'selectedAt': baseTime
              .subtract(const Duration(days: 40))
              .toIso8601String(),
          'liked': true,
        },
        {
          'foodName': '된장찌개',
          'category': '한식',
          'selectedAt': baseTime
              .subtract(const Duration(days: 41))
              .toIso8601String(),
          'liked': false,
        },
        // 최근 구간(30일 이내): 한식 total=2, liked=2, ratio=1.0, bonus=(2/2)*0.3=0.3, 총점=1.3 -> 상승(차이 0.5 > 0.05)
        {
          'foodName': '불고기',
          'category': '한식',
          'selectedAt': baseTime
              .subtract(const Duration(days: 10))
              .toIso8601String(),
          'liked': true,
        },
        {
          'foodName': '갈비',
          'category': '한식',
          'selectedAt': baseTime
              .subtract(const Duration(days: 5))
              .toIso8601String(),
          'liked': true,
        },
      ];

      final trends = await UserPreferenceService.getCategoryPreferenceTrends();
      expect(trends['한식'], equals('상승'));
    });

    test('analyzeDayOfWeekPreferences 요일별 선호 맵핑 수립 검증', () async {
      final baseTime = DateTime(2026, 7, 10, 12, 0); // 금요일 (weekday=5)
      UserPreferenceService.mockCurrentTime = baseTime;

      mockStorage.store['user_preferences.json:food_selection_history'] = [
        {
          'foodName': '김치찌개',
          'category': '한식',
          'selectedAt': baseTime.toIso8601String(), // 금요일(5)
          'liked': true,
        },
        {
          'foodName': '탕수육',
          'category': '중식',
          'selectedAt': baseTime.toIso8601String(), // 금요일(5)
          'liked': true,
        },
      ];

      final dayStats =
          await UserPreferenceService.analyzeDayOfWeekPreferences();
      expect(dayStats[5], isNotNull);
      expect(dayStats[5]!['한식'], equals(1));
      expect(dayStats[5]!['중식'], equals(1));
    });

    test('shouldShowReviewPromptDialog 좋아요 횟수 10의 배수 시나리오 검증', () async {
      // 1. 0개일 때
      mockStorage.store['user_preferences.json:review_prompt_like_count'] = 0;
      expect(
        await UserPreferenceService.shouldShowReviewPromptDialog(),
        isFalse,
      );

      // 2. 9개일 때
      mockStorage.store['user_preferences.json:review_prompt_like_count'] = 9;
      expect(
        await UserPreferenceService.shouldShowReviewPromptDialog(),
        isFalse,
      );

      // 3. 10개일 때
      mockStorage.store['user_preferences.json:review_prompt_like_count'] = 10;
      expect(
        await UserPreferenceService.shouldShowReviewPromptDialog(),
        isTrue,
      );

      // 4. 노출 플래그 완료 기록 시 0으로 클리어
      await UserPreferenceService.recordReviewPromptDialogShown();
      expect(
        await UserPreferenceService.shouldShowReviewPromptDialog(),
        isFalse,
      );
      expect(
        mockStorage.store['user_preferences.json:review_prompt_like_count'],
        equals(0),
      );
    });

    test('이전에 싫어하는 음식으로 등록되었던 음식을 좋아요 선택 시 싫어하는 음식 목록에서 제거된다', () async {
      // 1. 싫어하는 음식으로 등록 (liked: false)
      await UserPreferenceService.recordFoodSelection(
        foodName: '마라탕',
        category: '중식',
        liked: false,
      );
      var disliked = await UserPreferenceService.getDislikedFoods();
      expect(disliked, contains('마라탕'));

      // 2. 이후 해당 음식을 좋아요 선택 (liked: true)
      await UserPreferenceService.recordFoodSelection(
        foodName: '마라탕',
        category: '중식',
        liked: true,
      );
      disliked = await UserPreferenceService.getDislikedFoods();
      expect(disliked, isNot(contains('마라탕')));
    });
  });
}
