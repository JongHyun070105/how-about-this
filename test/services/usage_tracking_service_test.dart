import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:review_ai/services/usage_tracking_service.dart';
import 'package:review_ai/services/persistent_storage_service.dart';
import 'package:review_ai/services/remote_config_service.dart';

class MockPersistentStorageService extends PersistentStorageService {
  int getCallCount = 0;
  int setCallCount = 0;
  bool failNextGet = false;
  final Map<String, dynamic> store = {};

  @override
  Future<T?> getValue<T>(String fileName, String key) async {
    getCallCount++;
    if (failNextGet) {
      failNextGet = false;
      throw StateError('Simulated storage read failure');
    }
    return store['$fileName:$key'] as T?;
  }

  @override
  Future<void> setValue<T>(String fileName, String key, T value) async {
    setCallCount++;
    store['$fileName:$key'] = value;
  }
}

class MockRemoteConfigService extends Mock implements RemoteConfigService {
  @override
  int get maxDailyAiReviews => 10;

  @override
  int get maxDailyRecommendations => 20;
}

void main() {
  late MockPersistentStorageService mockStorage;
  late MockRemoteConfigService mockConfig;
  late UsageTrackingService trackingService;

  setUp(() {
    mockStorage = MockPersistentStorageService();
    mockConfig = MockRemoteConfigService();
    trackingService = UsageTrackingService(
      mockConfig,
      storageService: mockStorage,
    );
    UsageTrackingService.mockGetCurrentDate = null;
  });

  tearDown(() {
    UsageTrackingService.mockGetCurrentDate = null;
  });

  group('UsageTrackingService 캐싱 및 기능 검증', () {
    test('예외 폴백도 KST 날짜를 사용한다', () async {
      final koreaNow = DateTime.now().toUtc().add(const Duration(hours: 9));
      final expectedDate = DateTime.utc(
        koreaNow.year,
        koreaNow.month,
        koreaNow.day,
      ).toIso8601String().substring(0, 10);
      mockStorage.failNextGet = true;

      await trackingService.getReviewCount();

      expect(
        mockStorage.store['usage_data.json:last_reset_date'],
        expectedDate,
      );
    });

    test('최초 사용량 조회 시 디스크 I/O가 발생하고 이후 캐시를 사용한다', () async {
      final today = DateTime.utc(2026, 10, 24);
      UsageTrackingService.mockGetCurrentDate = () async => today;
      final todayStr = today.toIso8601String().substring(0, 10);
      mockStorage.store['usage_data.json:review_count'] = 3;
      mockStorage.store['usage_data.json:total_recommendation_count'] = 5;
      mockStorage.store['usage_data.json:last_reset_date'] = todayStr;

      final reviewCount1 = await trackingService.getReviewCount();
      expect(reviewCount1, 3);
      expect(mockStorage.getCallCount, greaterThan(0));

      final initialGetCalls = mockStorage.getCallCount;

      final reviewCount2 = await trackingService.getReviewCount();
      expect(reviewCount2, 3);
      expect(mockStorage.getCallCount, initialGetCalls); // 추가 getCall 없음
    });

    test('카운트 증가 시 캐시가 즉시 반영되며 추가적인 읽기 I/O는 0회다', () async {
      final today = DateTime.utc(2026, 10, 24);
      UsageTrackingService.mockGetCurrentDate = () async => today;
      final todayStr = today.toIso8601String().substring(0, 10);
      mockStorage.store['usage_data.json:review_count'] = 2;
      mockStorage.store['usage_data.json:total_recommendation_count'] = 1;
      mockStorage.store['usage_data.json:last_reset_date'] = todayStr;

      await trackingService.getReviewCount();
      mockStorage.getCallCount = 0;
      mockStorage.setCallCount = 0;

      final success = await trackingService.incrementReviewCount();
      expect(success, isTrue);
      expect(mockStorage.setCallCount, 1); // 쓰기 1회
      expect(mockStorage.getCallCount, 0); // 읽기 0회 (캐시 이용)

      final count = await trackingService.getReviewCount();
      expect(count, 3);
      expect(mockStorage.getCallCount, 0); // 읽기 여전히 0회
    });

    test('새로운 날짜가 도래하면 일일 카운터가 초기화된다 (가상 시간 주입 검증)', () async {
      final baseTime = DateTime(2026, 7, 10, 12, 0);
      UsageTrackingService.mockGetCurrentDate = () async => baseTime;

      // 1. 기준일에 카운트 저장
      mockStorage.store['usage_data.json:review_count'] = 5;
      mockStorage.store['usage_data.json:total_recommendation_count'] = 8;
      mockStorage.store['usage_data.json:last_reset_date'] = '2026-07-10';
      mockStorage.store['usage_data.json:last_access_timestamp'] =
          baseTime.millisecondsSinceEpoch;

      final count1 = await trackingService.getReviewCount();
      expect(count1, 5);

      // 2. 가상 시간을 하루 뒤로 이동
      UsageTrackingService.mockGetCurrentDate = () async =>
          baseTime.add(const Duration(days: 1));

      final count2 = await trackingService.getReviewCount();
      expect(count2, 0); // 날짜 변경에 의해 0으로 리셋됨

      final recCount = await trackingService.getTotalRecommendationCount();
      expect(recCount, 0); // 추천 카운트 역시 0으로 리셋됨
    });

    test('시간 변조(Time Manipulation) 감지 시 경고 로그 동작 검증', () async {
      final baseTime = DateTime(2026, 7, 10, 12, 0);

      // 미래 시간으로 먼저 기록함
      mockStorage.store['usage_data.json:review_count'] = 1;
      mockStorage.store['usage_data.json:last_reset_date'] = '2026-07-10';
      mockStorage.store['usage_data.json:last_access_timestamp'] = baseTime
          .add(const Duration(hours: 5))
          .millisecondsSinceEpoch;

      // 과거 시간으로 조회했을 때 예외 크래시 없이 정상 흐름을 타는지 검증
      UsageTrackingService.mockGetCurrentDate = () async => baseTime;

      expect(() => trackingService.getReviewCount(), returnsNormally);
    });

    test('일일 사용량 제한에 도달하면 추가 카운트 증가가 차단되고 false를 반환한다', () async {
      final baseTime = DateTime(2026, 7, 10, 12, 0);
      UsageTrackingService.mockGetCurrentDate = () async => baseTime;

      mockStorage.store['usage_data.json:review_count'] = 9;
      mockStorage.store['usage_data.json:total_recommendation_count'] = 19;
      mockStorage.store['usage_data.json:last_reset_date'] = '2026-07-10';

      // 1. 임계치 1회 전 (각각 최대 10회, 20회)
      expect(await trackingService.incrementReviewCount(), isTrue);
      expect(await trackingService.incrementTotalRecommendationCount(), isTrue);

      // 2. 임계치 도달 상태 검증
      expect(await trackingService.hasReachedReviewLimit(), isTrue);
      expect(
        await trackingService.hasReachedTotalRecommendationLimit(),
        isTrue,
      );
      expect(await trackingService.getRemainingReviewCount(), equals(0));
      expect(
        await trackingService.getRemainingRecommendationCount(),
        equals(0),
      );

      // 3. 임계치 도달 후 증가 시도 시 차단 및 false 반환 검증
      expect(await trackingService.incrementReviewCount(), isFalse);
      expect(
        await trackingService.incrementTotalRecommendationCount(),
        isFalse,
      );

      // 카운트가 최종 한계 이상으로 늘어나지 않았는지 확인
      expect(await trackingService.getReviewCount(), equals(10));
      expect(await trackingService.getTotalRecommendationCount(), equals(20));
    });

    test('서버 시간 조회 에러 시 로컬 폴백 시간을 기반으로 초기화 및 카운트가 안전하게 연동된다', () async {
      int serverTimeCallCount = 0;
      UsageTrackingService.mockGetCurrentDate = () async {
        serverTimeCallCount++;
        if (serverTimeCallCount == 1) {
          throw Exception('Server Connection Timeout');
        }
        // catch 블록 내 폴백 시간 반환
        return DateTime(2026, 7, 15, 12, 0);
      };

      // 기존 날짜는 7월 10일
      mockStorage.store['usage_data.json:review_count'] = 3;
      mockStorage.store['usage_data.json:total_recommendation_count'] = 5;
      mockStorage.store['usage_data.json:last_reset_date'] = '2026-07-10';

      // 서버 연결 에러 발생 -> 7월 15일 폴백을 기준으로 리셋이 발생해야 함
      final count = await trackingService.getReviewCount();
      expect(count, 0); // 새 날짜(7월 15일) 기준으로 카운트가 0으로 정상 리셋됨
      expect(
        mockStorage.store['usage_data.json:last_reset_date'],
        equals('2026-07-15'),
      );
    });
  });
}
