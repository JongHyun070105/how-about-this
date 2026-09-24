import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:dio/dio.dart';
import 'package:review_ai/services/kakao_api_service.dart';
import 'package:review_ai/services/auth_service.dart';
import 'package:review_ai/utils/network_utils.dart';
import 'package:review_ai/data/models/location_models.dart';

class MockDio extends Mock implements Dio {
  int getCallCount = 0;
  String? lastPath;
  Map<String, dynamic>? lastQueryParams;
  Options? lastOptions;

  Response? mockResponse;
  Object? mockError;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    getCallCount++;
    lastPath = path;
    lastQueryParams = queryParameters;
    lastOptions = options;

    if (mockError != null) {
      throw mockError!;
    }

    final res = mockResponse;
    if (res != null) {
      return Response<T>(
        data: res.data as T?,
        headers: res.headers,
        requestOptions: res.requestOptions,
        isRedirect: res.isRedirect,
        statusCode: res.statusCode,
        statusMessage: res.statusMessage,
        redirects: res.redirects,
        extra: res.extra,
      );
    }

    throw Exception('MockResponse not configured');
  }
}

void main() {
  late MockDio mockDio;
  late KakaoApiService kakaoApiService;

  final testResponseData = {
    'documents': [
      {
        'id': '12345',
        'place_name': '맛있는 짜장면집',
        'distance': '150',
        'road_address_name': '서울 강남구 역삼로 123',
        'address_name': '서울 강남구 역삼동 789',
        'phone': '02-123-4567',
        'category_name': '음식점 > 중식 > 중화요리',
        'x': '127.027610',
        'y': '37.497942',
        'place_url': 'http://place.map.kakao.com/123456',
      },
    ],
    'meta': {'is_end': true, 'pageable_count': 1, 'total_count': 1},
  };

  setUp(() {
    mockDio = MockDio();
    kakaoApiService = KakaoApiService(dio: mockDio);

    // NetworkUtils 인터넷 연결 우회 설정
    NetworkUtils.mockConnectivityResult = true;

    // AuthService JWT 우회 토큰 설정 (만료시간 1시간 뒤)
    AuthService.setMockToken(
      accessToken: 'mock_jwt_access_token',
      expiry: DateTime.now().add(const Duration(hours: 1)),
    );
  });

  group('KakaoApiService 캐싱 및 예외 단위 테스트', () {
    test('최초 맛집 검색 시 네트워크 API(Dio) 호출이 발생하고, 이후 캐시 맵에서 서빙한다', () async {
      mockDio.mockResponse = Response(
        requestOptions: RequestOptions(path: '/api/kakao-local'),
        data: testResponseData,
        statusCode: 200,
      );

      const params = RestaurantSearchParams(
        query: '짜장면',
        latitude: 37.497942,
        longitude: 127.027610,
        radius: 1000,
      );

      // 1. 최초 검색
      final response1 = await kakaoApiService.searchPlaces(params);
      expect(response1.documents.length, 1);
      expect(response1.documents.first.placeName, '맛있는 짜장면집');
      expect(mockDio.getCallCount, 1); // Dio 1회 호출 발생

      final initialGetCalls = mockDio.getCallCount;

      // 2. 2회차 연속 검색 (동일 파라미터)
      final response2 = await kakaoApiService.searchPlaces(params);
      expect(response2.documents.length, 1);
      expect(response2.documents.first.placeName, '맛있는 짜장면집');
      expect(mockDio.getCallCount, initialGetCalls); // 캐시 적용되어 추가 Dio 호출 없음
    });

    test('캐시 유효기간(5분)이 지난 뒤 검색하면 캐시를 파기하고 다시 API를 조회한다', () async {
      mockDio.mockResponse = Response(
        requestOptions: RequestOptions(path: '/api/kakao-local'),
        data: testResponseData,
        statusCode: 200,
      );

      const params = RestaurantSearchParams(
        query: '짬뽕',
        latitude: 37.497942,
        longitude: 127.027610,
      );

      // 1. 최초 검색
      await kakaoApiService.searchPlaces(params);
      expect(mockDio.getCallCount, 1);

      // 2. 캐시 강제 만료 처리 (6분 전 시각으로 캐시 타임스탬프 조작)
      const cacheKey = '짬뽕_37.497942_127.02761_none';
      expect(kakaoApiService.searchCache.containsKey(cacheKey), isTrue);

      final originalResponse = kakaoApiService.searchCache[cacheKey]!.response;
      kakaoApiService.searchCache[cacheKey] = CachedSearchResult(
        response: originalResponse,
        timestamp: DateTime.now().subtract(const Duration(minutes: 6)),
      );

      // 3. 만료 후 재조회
      await kakaoApiService.searchPlaces(params);
      expect(mockDio.getCallCount, 2); // 캐시 만료로 인해 Dio 추가 1회 호출됨
    });

    test('clearCache()를 실행하면 등록된 캐시 데이터가 완전히 정리되어 다시 API 조회를 일으킨다', () async {
      mockDio.mockResponse = Response(
        requestOptions: RequestOptions(path: '/api/kakao-local'),
        data: testResponseData,
        statusCode: 200,
      );

      const params = RestaurantSearchParams(
        query: '탕수육',
        latitude: 37.497942,
        longitude: 127.027610,
      );

      await kakaoApiService.searchPlaces(params);
      expect(mockDio.getCallCount, 1);

      // 캐시 클리어
      kakaoApiService.clearCache();
      expect(kakaoApiService.searchCache.isEmpty, isTrue);

      // 재조회
      await kakaoApiService.searchPlaces(params);
      expect(mockDio.getCallCount, 2); // 캐시 클리어로 인해 다시 Dio를 호출함
    });

    test('Dio 예외 발생 시 - Connection Timeout에 대해 네트워크 시간 초과 에러를 반환한다', () async {
      mockDio.mockError = DioException(
        requestOptions: RequestOptions(path: '/api/kakao-local'),
        type: DioExceptionType.connectionTimeout,
      );

      const params = RestaurantSearchParams(
        query: '울면',
        latitude: 37.497942,
        longitude: 127.027610,
      );

      expect(
        () => kakaoApiService.searchPlaces(params),
        throwsA(
          isA<KakaoApiException>().having(
            (e) => e.message,
            'message',
            contains('시간이 초과되었습니다'),
          ),
        ),
      );
    });

    test('Dio 예외 발생 시 - 401 응답에 대해 인증 에러를 반환한다', () async {
      mockDio.mockError = DioException(
        requestOptions: RequestOptions(path: '/api/kakao-local'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/api/kakao-local'),
          statusCode: 401,
        ),
      );

      const params = RestaurantSearchParams(
        query: '짜장면',
        latitude: 37.497942,
        longitude: 127.027610,
      );

      expect(
        () => kakaoApiService.searchPlaces(params),
        throwsA(
          isA<KakaoApiException>().having(
            (e) => e.message,
            'message',
            contains('인증이 필요합니다'),
          ),
        ),
      );
    });

    test('searchCache는 50개 항목을 초과하지 않고 가장 오래된 항목을 제거해야 함', () async {
      mockDio.mockResponse = Response(
        requestOptions: RequestOptions(path: '/api/kakao-local'),
        statusCode: 200,
        data: testResponseData,
      );

      for (int i = 0; i < 55; i++) {
        await kakaoApiService.searchPlaces(
          RestaurantSearchParams(
            query: '음식_$i',
            latitude: 37.0 + (i * 0.001),
            longitude: 127.0,
          ),
        );
      }

      expect(kakaoApiService.searchCache.length, lessThanOrEqualTo(50));
      // 가장 처음 들어갔던 0번은 퇴출되어 캐시에 없어야 함
      const firstKey = '음식_0_37.0_127.0_none';
      expect(kakaoApiService.searchCache.containsKey(firstKey), isFalse);
    });
  });
}
