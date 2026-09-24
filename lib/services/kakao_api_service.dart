import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:review_ai/config/api_config.dart';
import 'package:review_ai/data/models/location_models.dart';
import 'package:review_ai/utils/kakao_api_filter_util.dart';
import 'package:review_ai/core/utils/logger_service.dart';
export 'package:review_ai/utils/kakao_api_filter_util.dart'; // 추가: RestaurantSortType 등의 참조 유지
import 'auth_service.dart';
import 'package:review_ai/utils/error_handler.dart';
import 'package:review_ai/utils/network_utils.dart';

/// 카카오 로컬 API 서비스
/// 맛집 검색을 위한 카카오 로컬 API를 호출합니다.
class KakaoApiService {
  static const Duration _timeout = Duration(seconds: 10);

  final Dio _dio;

  // 검색 결과 캐시
  @visibleForTesting
  final Map<String, CachedSearchResult> searchCache = {};

  KakaoApiService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: ApiConfig.proxyUrl,
              connectTimeout: _timeout,
              receiveTimeout: _timeout,
              headers: {'Content-Type': 'application/json'},
            ),
          );

  /// 캐시 키 생성
  String _getCacheKey(RestaurantSearchParams params) {
    return '${params.query}_${params.latitude}_${params.longitude}_${params.categoryGroupCode ?? "none"}';
  }

  /// 키워드로 장소를 검색합니다.
  Future<KakaoSearchResponse> searchPlaces(
    RestaurantSearchParams params,
  ) async {
    try {
      // 캐시 확인
      final cacheKey = _getCacheKey(params);
      final cachedResult = searchCache[cacheKey];

      if (cachedResult != null && !cachedResult.isExpired) {
        LoggerService.d('Serving restaurant search from cache: $cacheKey');
        return cachedResult.response;
      }

      // 네트워크 연결 확인
      if (!await NetworkUtils.checkInternetConnectivity()) {
        throw const KakaoApiException('인터넷 연결을 확인해주세요.');
      }

      // JWT 토큰 가져오기
      final token = await AuthService.getValidAccessToken();

      final response = await _dio.get(
        '/api/kakao-local',
        queryParameters: params.toJson(),
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        if (response.data == null) {
          throw const KakaoApiException('API 응답 데이터가 없습니다.');
        }

        final searchResponse = KakaoSearchResponse.fromJson(response.data);

        // 캐시 저장 (메모리 누수 방지를 위한 용량 상한 관리)
        const int maxCacheEntries = 50;
        if (searchCache.length >= maxCacheEntries) {
          searchCache.remove(searchCache.keys.first);
        }
        searchCache[cacheKey] = CachedSearchResult(
          response: searchResponse,
          timestamp: DateTime.now(),
        );
        LoggerService.d('Cached restaurant search result: $cacheKey');

        return searchResponse;
      } else {
        throw KakaoApiException(
          'API 호출 실패: ${response.statusCode}',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw const KakaoApiException('네트워크 연결 시간이 초과되었습니다.');
      } else if (e.type == DioExceptionType.connectionError) {
        throw const KakaoApiException('네트워크 연결에 실패했습니다.');
      } else if (e.response?.statusCode == 401) {
        throw const KakaoApiException('인증이 필요합니다. 앱을 다시 시작해주세요.');
      } else if (e.response?.statusCode == 403) {
        throw const KakaoApiException('API 사용 권한이 없습니다.');
      } else if (e.response?.statusCode == 429) {
        throw const KakaoApiException('API 호출 한도를 초과했습니다.');
      } else {
        throw const KakaoApiException('API 호출 중 오류가 발생했습니다.');
      }
    } catch (e) {
      throw KakaoApiException(ErrorHandler.sanitizeMessage(e));
    }
  }

  /// 음식 이름으로 맛집을 검색합니다.
  Future<List<KakaoPlace>> searchRestaurants({
    required String foodName,
    required double latitude,
    required double longitude,
    String? category,
    int radius = 1000,
    int page = 1,
    int size = 15,
  }) async {
    try {
      final categoryCode = KakaoApiFilterUtil.getCategoryCode(category);

      final params = RestaurantSearchParams(
        query: foodName, // "짜장면 맛집" 대신 그냥 "짜장면"
        latitude: latitude,
        longitude: longitude,
        radius: radius,
        page: page,
        size: size,
        categoryGroupCode: categoryCode, // 카테고리 필터 추가
      );

      final response = await searchPlaces(params);
      return response.documents;
    } catch (e) {
      rethrow;
    }
  }

  /// 카테고리별 검색어를 생성합니다. (기존 호환성 유지)
  String getCategorySearchQuery(String category, String foodName) {
    return KakaoApiFilterUtil.getCategorySearchQuery(category, foodName);
  }

  /// 검색 결과를 필터링합니다. (기존 호환성 유지)
  List<KakaoPlace> filterRestaurants(
    List<KakaoPlace> restaurants, {
    String? targetCategory, // 원하는 카테고리
    String? foodName, // 음식명 추가: 정확한 매칭을 위해
    double? minRating,
    int? maxDistance,
    List<String>? excludeCategories,
  }) {
    return KakaoApiFilterUtil.filterRestaurants(
      restaurants,
      targetCategory: targetCategory,
      foodName: foodName,
      minRating: minRating,
      maxDistance: maxDistance,
      excludeCategories: excludeCategories,
    );
  }

  /// 검색 결과를 정렬합니다. (기존 호환성 유지)
  List<KakaoPlace> sortRestaurants(
    List<KakaoPlace> restaurants, {
    RestaurantSortType sortType = RestaurantSortType.distance,
  }) {
    return KakaoApiFilterUtil.sortRestaurants(restaurants, sortType: sortType);
  }

  /// 검색 결과 캐시 초기화 (테스트 및 메모리 관리용)
  void clearCache() {
    searchCache.clear();
    LoggerService.d('KakaoApiService search cache cleared');
  }
}

/// 카카오 API 예외 클래스
class KakaoApiException implements Exception {
  final String message;
  final int? statusCode;

  const KakaoApiException(this.message, [this.statusCode]);

  @override
  String toString() {
    if (statusCode != null) {
      return 'KakaoApiException: $message (Status: $statusCode)';
    }
    return 'KakaoApiException: $message';
  }
}

/// 검색 결과 캐시
class CachedSearchResult {
  final KakaoSearchResponse response;
  final DateTime timestamp;

  CachedSearchResult({required this.response, required this.timestamp});

  bool get isExpired {
    return DateTime.now().difference(timestamp) > const Duration(minutes: 5);
  }
}
