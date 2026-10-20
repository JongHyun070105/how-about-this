import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:review_ai/services/auth_service.dart';
import 'package:review_ai/services/food_insight_service.dart';
import 'package:review_ai/services/ai_food_insight_service.dart';
import 'package:review_ai/presentation/providers/review_provider.dart';

/// 테스트용 ReviewHistoryEntry 생성 헬퍼
ReviewHistoryEntry _createEntry({
  String foodName = '김치찌개',
  String category = '한식',
  DateTime? createdAt,
}) {
  return ReviewHistoryEntry(
    foodName: foodName,
    category: category,
    tasteRating: 4.0,
    deliveryRating: 4.0,
    portionRating: 3.5,
    priceRating: 3.0,
    reviewStyle: '일반',
    generatedReviews: ['좋은 리뷰'],
    createdAt: createdAt,
  );
}

void main() {
  setUpAll(() {
    AuthService.setMockToken(
      accessToken: 'test_mock_jwt_token',
      expiry: DateTime.now().add(const Duration(days: 1)),
    );
  });

  tearDown(() {
    AiFoodInsightService().setClientForTesting(null);
  });

  group('AiInsightResult', () {
    test('AI 인사이트 결과 생성', () {
      const result = AiInsightResult(message: 'AI가 생성한 인사이트', isAi: true);

      expect(result.message, 'AI가 생성한 인사이트');
      expect(result.isAi, true);
    });

    test('로컬 폴백 결과 생성', () {
      const result = AiInsightResult(message: '로컬 메시지', isAi: false);

      expect(result.message, '로컬 메시지');
      expect(result.isAi, false);
    });
  });

  group('AiFoodInsightService - 폴백 로직', () {
    test('빈 히스토리일 때 로컬 폴백 반환', () async {
      final service = AiFoodInsightService();
      final result = await service.getInsight([]);

      expect(result.isAi, false);
      expect(result.message, isNotEmpty);
      expect(result.message, FoodInsightService.generateInsightMessage([]));
    });

    test('네트워크 실패 시 로컬 폴백 반환', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final service = AiFoodInsightService();
      service.setClientForTesting(mockClient);

      final history = <ReviewHistoryEntry>[
        _createEntry(foodName: '김치찌개', category: '한식'),
        _createEntry(
          foodName: '비빔밥',
          category: '한식',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];

      final result = await service.getInsight(history, forceRefresh: true);

      // 500 에러 → 로컬 폴백
      expect(result.isAi, false);
      expect(result.message, isNotEmpty);
    });
  });

  group('AiFoodInsightService - 모킹 성공 및 생명주기 검증', () {
    test('성공적인 AI 인사이트 반환 및 캐싱 검증', () async {
      int apiCallCount = 0;
      final mockClient = MockClient((request) async {
        apiCallCount++;
        return http.Response(
          json.encode({'insight': '오늘 점심은 가벼운 한식 어떠신가요?', 'cached': false}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = AiFoodInsightService();
      service.setClientForTesting(mockClient);

      final history = <ReviewHistoryEntry>[
        _createEntry(foodName: '된장찌개', category: '한식'),
      ];

      // 1. 첫 호출 - API를 타고 가져와야 함
      final result1 = await service.getInsight(history, forceRefresh: true);
      expect(result1.isAi, isTrue);
      expect(result1.message, '오늘 점심은 가벼운 한식 어떠신가요?');
      expect(apiCallCount, 1);

      // 2. 두 번째 호출 (forceRefresh: false) - 캐시가 반환되므로 API 호출이 늘어나면 안 됨
      final result2 = await service.getInsight(history, forceRefresh: false);
      expect(result2.isAi, isTrue);
      expect(result2.message, '오늘 점심은 가벼운 한식 어떠신가요?');
      expect(apiCallCount, 1);
    });

    test('forceRefresh가 true이면 캐시를 무시하고 강제 요청 검증', () async {
      int apiCallCount = 0;
      final mockClient = MockClient((request) async {
        apiCallCount++;
        return http.Response(
          json.encode({'insight': '식습관이 양호합니다.', 'cached': false}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = AiFoodInsightService();
      service.setClientForTesting(mockClient);

      final history = <ReviewHistoryEntry>[
        _createEntry(foodName: '된장찌개', category: '한식'),
      ];

      await service.getInsight(history, forceRefresh: true);
      expect(apiCallCount, 1);

      // forceRefresh: true 로 두 번째 호출
      await service.getInsight(history, forceRefresh: true);
      expect(apiCallCount, 2);
    });

    test('리뷰 요약이 바뀌면 이전 사용자 맞춤 인사이트를 재사용하지 않는다', () async {
      int apiCallCount = 0;
      final mockClient = MockClient((request) async {
        apiCallCount++;
        return http.Response(
          json.encode({'insight': '새 식습관 인사이트 $apiCallCount', 'cached': false}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = AiFoodInsightService();
      service.setClientForTesting(mockClient);

      await service.getInsight([
        _createEntry(foodName: '버섯전골', category: '한식'),
      ], forceRefresh: true);
      final changedHistoryResult = await service.getInsight([
        _createEntry(foodName: '쌀국수', category: '아시아 음식'),
        _createEntry(
          foodName: '쌀국수',
          category: '아시아 음식',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ]);

      expect(apiCallCount, 2);
      expect(changedHistoryResult.message, '새 식습관 인사이트 2');
    });

    test('dispose 호출 후 다시 요청 시 클라이언트 재생성 및 안정성 검증', () async {
      int apiCallCount = 0;
      final mockClient = MockClient((request) async {
        apiCallCount++;
        return http.Response(
          json.encode({'insight': '안정적으로 재연결되었습니다.', 'cached': false}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = AiFoodInsightService();
      service.setClientForTesting(mockClient);

      final history = <ReviewHistoryEntry>[
        _createEntry(foodName: '된장찌개', category: '한식'),
      ];

      // 첫 조회
      await service.getInsight(history, forceRefresh: true);
      expect(apiCallCount, 1);

      // dispose 실행 (클라이언트 닫기)
      service.dispose();

      // 두 번째 조회 - 재생성되어 에러 없이 정상 요청을 보내야 함
      final result = await service.getInsight(history, forceRefresh: true);
      expect(result.isAi, isTrue);
      expect(result.message, '안정적으로 재연결되었습니다.');
      expect(apiCallCount, 2);
    });
  });

  group('FoodInsightService와 연동', () {
    test('로컬 인사이트 메시지가 유효한 문자열', () {
      final history = <ReviewHistoryEntry>[
        _createEntry(foodName: '짜장면', category: '중식'),
      ];

      final message = FoodInsightService.generateInsightMessage(history);
      expect(message, isNotEmpty);
      expect(message, isA<String>());
    });

    test('빈 히스토리 인사이트 메시지', () {
      final message = FoodInsightService.generateInsightMessage([]);
      expect(message, contains('첫 리뷰'));
    });
  });
}
