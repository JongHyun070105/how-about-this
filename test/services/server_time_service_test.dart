import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:review_ai/services/auth_service.dart';
import 'package:review_ai/services/server_time_service.dart';

void main() {
  setUpAll(() {
    AuthService.setMockToken(
      accessToken: 'test_mock_jwt_token',
      expiry: DateTime.now().add(const Duration(days: 1)),
    );
  });

  setUp(() {
    ServerTimeService.clearCache();
    ServerTimeService.cacheExpiry = const Duration(minutes: 5);
    ServerTimeService.failureCacheExpiry = const Duration(seconds: 30);
    ServerTimeService.setClockForTesting(null);
  });

  tearDown(() {
    ServerTimeService.clearCache();
    ServerTimeService.setClientForTesting(null);
    ServerTimeService.setClockForTesting(null);
  });

  group('ServerTimeService 유닛 테스트', () {
    test('성공적인 서버 시간 API 응답 파싱 및 캐싱 검증', () async {
      int apiCallCount = 0;
      final mockClient = MockClient((request) async {
        apiCallCount++;
        return http.Response(
          json.encode({
            'serverTime': '2026-06-17T12:30:00.000Z',
            'timestamp': 1781699400000,
          }),
          200,
        );
      });

      ServerTimeService.setClientForTesting(mockClient);

      // 첫 호출 - API 호출 발생
      final time1 = await ServerTimeService.getServerTime();
      expect(time1, DateTime.parse('2026-06-17T12:30:00.000Z'));
      expect(apiCallCount, 1);

      // 두 번째 호출 - 캐시 반환 (API 호출 없음)
      final time2 = await ServerTimeService.getServerTime();
      expect(time2, isNotNull);
      expect(apiCallCount, 1);
    });

    test('캐시 만료 후 재요청 시 API가 재호출되는지 검증', () async {
      int apiCallCount = 0;
      final mockClient = MockClient((request) async {
        apiCallCount++;
        return http.Response(
          json.encode({
            'serverTime': '2026-06-17T12:30:00.000Z',
            'timestamp': 1781699400000,
          }),
          200,
        );
      });

      ServerTimeService.setClientForTesting(mockClient);

      // 첫 호출
      await ServerTimeService.getServerTime();
      expect(apiCallCount, 1);

      // 캐시 만료 설정 (0초 만료)
      ServerTimeService.cacheExpiry = Duration.zero;

      // 두 번째 호출 - 캐시 만료로 인해 API 재호출
      await ServerTimeService.getServerTime();
      expect(apiCallCount, 2);
    });

    test('서버 시간 조회 실패(500 에러) 시 로컬 시간 폴백 처리 검증', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      ServerTimeService.setClientForTesting(mockClient);

      final before = DateTime.now();
      final time = await ServerTimeService.getServerTime();
      final after = DateTime.now();

      // 에러 시 로컬 시간을 반환하므로 before와 after 범위 내여야 함
      expect(
        time.millisecondsSinceEpoch,
        greaterThanOrEqualTo(before.millisecondsSinceEpoch),
      );
      expect(
        time.millisecondsSinceEpoch,
        lessThanOrEqualTo(after.millisecondsSinceEpoch),
      );
    });

    test('서버 시간 조회 실패 폴백도 한국 날짜 기준을 사용한다', () async {
      ServerTimeService.setClockForTesting(
        () => DateTime.utc(2026, 10, 23, 15, 30),
      );
      ServerTimeService.setClientForTesting(
        MockClient((request) async => http.Response('Server Error', 500)),
      );

      expect(
        await ServerTimeService.getCurrentDate(),
        DateTime.utc(2026, 10, 24),
      );
    });

    test('시간 조회 실패 후 짧은 backoff 동안 중복 서버 요청을 생략한다', () async {
      var apiCallCount = 0;
      final mockClient = MockClient((request) async {
        apiCallCount++;
        return http.Response('Server Error', 500);
      });
      ServerTimeService.setClientForTesting(mockClient);

      await ServerTimeService.getServerTime();
      await ServerTimeService.getServerTime();

      expect(apiCallCount, 1);

      ServerTimeService.failureCacheExpiry = Duration.zero;
      await ServerTimeService.getServerTime();
      expect(apiCallCount, 2);
    });

    test('동시에 시작한 서버 시간 조회는 진행 중 요청을 공유한다', () async {
      var apiCallCount = 0;
      final responseCompleter = Completer<http.Response>();
      final mockClient = MockClient((request) {
        apiCallCount++;
        return responseCompleter.future;
      });
      ServerTimeService.setClientForTesting(mockClient);

      final firstRequest = ServerTimeService.getServerTime();
      final secondRequest = ServerTimeService.getServerTime();

      await Future<void>.delayed(Duration.zero);
      expect(apiCallCount, 1);

      responseCompleter.complete(http.Response('Server Error', 500));
      await Future.wait([firstRequest, secondRequest]);

      expect(apiCallCount, 1);
    });

    test('로컬 시스템 시간 조작 감지(detectTimeManipulation) 검증', () async {
      int apiCallCount = 0;
      // 첫 호출 시 offset = 0 (서버시간 == 로컬시간)
      // 두 번째 호출 시 10분 오차 발생 시뮬레이션
      final mockClient = MockClient((request) async {
        apiCallCount++;
        if (apiCallCount == 1) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          return http.Response(
            json.encode({
              'serverTime': DateTime.now().toIso8601String(),
              'timestamp': nowMs,
            }),
            200,
          );
        } else {
          // 10분 오프셋을 더한 시간 응답
          final manipulatedMs = DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch;
          return http.Response(
            json.encode({
              'serverTime': DateTime.now()
                  .add(const Duration(minutes: 10))
                  .toIso8601String(),
              'timestamp': manipulatedMs,
            }),
            200,
          );
        }
      });

      ServerTimeService.setClientForTesting(mockClient);

      // 1. 처음엔 감지되지 않아야 함 (false)
      final initialDetection = await ServerTimeService.detectTimeManipulation();
      expect(initialDetection, isFalse);

      // 캐시를 만료시켜서 두 번째 detectTimeManipulation 호출 시 실제 API 통신을 유발
      ServerTimeService.cacheExpiry = Duration.zero;

      // 2. 오차가 10분 발생했으므로 조작 감지되어야 함 (true)
      final detectionResult = await ServerTimeService.detectTimeManipulation();
      expect(detectionResult, isTrue);
    });

    test('로컬 시계를 뒤로 돌려도 서버 캐시 시각은 뒤로 이동하지 않아야 함', () async {
      var localTime = DateTime(2026, 10, 19, 12);
      ServerTimeService.setClockForTesting(() => localTime);
      var apiCallCount = 0;
      ServerTimeService.setClientForTesting(
        MockClient((request) async {
          apiCallCount++;
          return http.Response(
            json.encode({
              'serverTime': localTime.toIso8601String(),
              'timestamp': localTime.millisecondsSinceEpoch,
            }),
            200,
          );
        }),
      );

      await ServerTimeService.getServerTime();
      localTime = localTime.subtract(const Duration(minutes: 10));

      expect(await ServerTimeService.detectTimeManipulation(), isTrue);
      expect(apiCallCount, 1);
    });

    test('시간 조작이 없고 오차가 5분 이내일 때는 감지하지 않는지 검증', () async {
      int apiCallCount = 0;
      final mockClient = MockClient((request) async {
        apiCallCount++;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (apiCallCount == 1) {
          return http.Response(
            json.encode({
              'serverTime': DateTime.now().toIso8601String(),
              'timestamp': nowMs,
            }),
            200,
          );
        } else {
          // 1분 오차만 주어 5분 이내로 유지
          final minorDiffMs = DateTime.now()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch;
          return http.Response(
            json.encode({
              'serverTime': DateTime.now()
                  .add(const Duration(minutes: 1))
                  .toIso8601String(),
              'timestamp': minorDiffMs,
            }),
            200,
          );
        }
      });

      ServerTimeService.setClientForTesting(mockClient);

      // 1. 첫 호출
      final initialDetection = await ServerTimeService.detectTimeManipulation();
      expect(initialDetection, isFalse);

      // 캐시 만료
      ServerTimeService.cacheExpiry = Duration.zero;

      // 2. 오차가 1분이므로 감지하지 않아야 함 (false)
      final detectionResult = await ServerTimeService.detectTimeManipulation();
      expect(detectionResult, isFalse);
    });

    test('getCurrentDate가 getServerTime의 날짜 부분을 정확히 반환하는지 검증', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'serverTime': '2026-06-17T12:30:00.000Z',
            'timestamp': 1781699400000,
          }),
          200,
        );
      });

      ServerTimeService.setClientForTesting(mockClient);

      final date = await ServerTimeService.getCurrentDate();
      expect(date.year, 2026);
      expect(date.month, 6);
      expect(date.day, 17);
      expect(date.hour, 0);
      expect(date.minute, 0);
    });

    test('UTC 서버 시각을 한국 날짜로 변환해 자정 경계에서 날짜를 맞춘다', () async {
      ServerTimeService.setClientForTesting(
        MockClient((request) async {
          return http.Response(
            json.encode({
              'serverTime': '2026-10-23T15:30:00.000Z',
              'timestamp': DateTime.utc(
                2026,
                10,
                23,
                15,
                30,
              ).millisecondsSinceEpoch,
            }),
            200,
          );
        }),
      );

      expect(
        await ServerTimeService.getCurrentDate(),
        DateTime.utc(2026, 10, 24),
      );
    });
  });
}
