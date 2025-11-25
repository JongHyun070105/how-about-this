import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/location_models.dart';
import 'auth_service.dart';
import '../utils/error_handler.dart';
import '../utils/network_utils.dart';

/// 카카오 로컬 API 서비스
/// 맛집 검색을 위한 카카오 로컬 API를 호출합니다.
class KakaoApiService {
  static const Duration _timeout = Duration(seconds: 10);

  late final Dio _dio;

  // 검색 결과 캐시
  final Map<String, _CachedSearchResult> _searchCache = {};

  KakaoApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.proxyUrl,
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );
  }

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
      final cachedResult = _searchCache[cacheKey];

      if (cachedResult != null && !cachedResult.isExpired) {
        debugPrint('Serving restaurant search from cache: $cacheKey');
        return cachedResult.response;
      }

      // 네트워크 연결 확인
      if (!await NetworkUtils.checkInternetConnectivity()) {
        throw KakaoApiException('인터넷 연결을 확인해주세요.');
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
          throw KakaoApiException('API 응답 데이터가 없습니다.');
        }

        final searchResponse = KakaoSearchResponse.fromJson(response.data);

        // 캐시 저장
        _searchCache[cacheKey] = _CachedSearchResult(
          response: searchResponse,
          timestamp: DateTime.now(),
        );
        debugPrint('Cached restaurant search result: $cacheKey');

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
        throw KakaoApiException('네트워크 연결 시간이 초과되었습니다.');
      } else if (e.type == DioExceptionType.connectionError) {
        throw KakaoApiException('네트워크 연결에 실패했습니다.');
      } else if (e.response?.statusCode == 401) {
        throw KakaoApiException('인증이 필요합니다. 앱을 다시 시작해주세요.');
      } else if (e.response?.statusCode == 403) {
        throw KakaoApiException('API 사용 권한이 없습니다.');
      } else if (e.response?.statusCode == 429) {
        throw KakaoApiException('API 호출 한도를 초과했습니다.');
      } else {
        throw KakaoApiException('API 호출 중 오류가 발생했습니다: ${e.message}');
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
      final categoryCode = _getCategoryCode(category);

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

  /// 카테고리에 맞는 카카오 카테고리 코드를 반환합니다.
  /// 카카오 로컬 API 카테고리 그룹 코드:
  /// - FD6: 음식점
  /// - CE7: 카페
  /// - CS2: 편의점
  String? _getCategoryCode(String? category) {
    if (category == null) return 'FD6'; // 기본값: 음식점

    switch (category) {
      case '카페':
        return 'CE7';
      case '편의점':
        return 'CS2';
      case '한식':
      case '중식':
      case '일식':
      case '양식':
      case '분식':
      case '아시안':
      case '패스트푸드':
        return 'FD6'; // 모두 음식점
      default:
        return 'FD6';
    }
  }

  /// 카테고리별 검색어를 생성합니다.
  String getCategorySearchQuery(String category, String foodName) {
    switch (category) {
      case '한식':
        return foodName; // "짜장면" 그대로
      case '중식':
        return foodName;
      case '일식':
        return foodName;
      case '양식':
        return foodName;
      case '분식':
        return foodName;
      case '아시안':
        return foodName;
      case '패스트푸드':
        return foodName;
      case '편의점':
        return '편의점';
      case '카페':
        return foodName;
      default:
        return foodName;
    }
  }

  /// 검색 결과를 필터링합니다. (카테고리 필터링 강화)
  List<KakaoPlace> filterRestaurants(
    List<KakaoPlace> restaurants, {
    String? targetCategory, // 원하는 카테고리
    String? foodName, // 음식명 추가: 정확한 매칭을 위해
    double? minRating,
    int? maxDistance,
    List<String>? excludeCategories,
  }) {
    return restaurants.where((restaurant) {
      // 거리 필터링
      if (maxDistance != null && restaurant.distanceInMeters != null) {
        if (restaurant.distanceInMeters! > maxDistance) {
          return false;
        }
      }

      // 음식명 필터링: 음식점 이름이나 카테고리에 음식명이 포함되어야 함
      if (foodName != null && foodName.isNotEmpty) {
        final nameLower = restaurant.placeName.toLowerCase();
        final categoryLower = restaurant.categoryName.toLowerCase();
        final foodLower = foodName.toLowerCase();

        // 음식점 이름이나 카테고리에 음식명이 포함되어 있으면 관련성이 높음
        final hasRelevance =
            nameLower.contains(foodLower) || categoryLower.contains(foodLower);

        // 관련성이 전혀 없으면 제외
        if (!hasRelevance && targetCategory != null) {
          // 단, 카테고리만 맞는 경우는 허용 (예: "한식" 카테고리에서 한식당 찾기)
          // 이 경우 아래 카테고리 필터링을 통과하면 OK
        }
      }

      // 카테고리 정확도 필터링 강화
      if (targetCategory != null) {
        final categoryLower = restaurant.categoryName.toLowerCase();

        switch (targetCategory) {
          case '중식':
            // "중식" 또는 "중국음식"이 카테고리에 포함되어야 함
            if (!categoryLower.contains('중식') &&
                !categoryLower.contains('중국')) {
              return false;
            }
            break;
          case '한식':
            // 한식 관련 키워드 확장
            if (!categoryLower.contains('한식') &&
                !categoryLower.contains('한정식') &&
                !categoryLower.contains('백반') &&
                !categoryLower.contains('고기') &&
                !categoryLower.contains('삼겹살') &&
                !categoryLower.contains('갈비') &&
                !categoryLower.contains('찌개') &&
                !categoryLower.contains('국밥')) {
              return false;
            }
            break;
          case '일식':
            if (!categoryLower.contains('일식') &&
                !categoryLower.contains('일본') &&
                !categoryLower.contains('스시') &&
                !categoryLower.contains('초밥') &&
                !categoryLower.contains('라멘') &&
                !categoryLower.contains('우동')) {
              return false;
            }
            break;
          case '양식':
            if (!categoryLower.contains('양식') &&
                !categoryLower.contains('이탈리안') &&
                !categoryLower.contains('스테이크') &&
                !categoryLower.contains('파스타') &&
                !categoryLower.contains('피자')) {
              return false;
            }
            break;
          case '분식':
            if (!categoryLower.contains('분식')) {
              return false;
            }
            break;
          case '아시안':
            if (!categoryLower.contains('아시아') &&
                !categoryLower.contains('베트남') &&
                !categoryLower.contains('태국') &&
                !categoryLower.contains('인도') &&
                !categoryLower.contains('동남아')) {
              return false;
            }
            break;
        }
      }

      // 카테고리 제외 필터링
      if (excludeCategories != null && excludeCategories.isNotEmpty) {
        for (final category in excludeCategories) {
          if (restaurant.categoryName.contains(category)) {
            return false;
          }
        }
      }

      return true;
    }).toList();
  }

  /// 검색 결과를 정렬합니다.
  List<KakaoPlace> sortRestaurants(
    List<KakaoPlace> restaurants, {
    RestaurantSortType sortType = RestaurantSortType.distance,
  }) {
    switch (sortType) {
      case RestaurantSortType.distance:
        return restaurants..sort((a, b) {
          final distanceA = a.distanceInMeters ?? double.infinity;
          final distanceB = b.distanceInMeters ?? double.infinity;
          return distanceA.compareTo(distanceB);
        });
      case RestaurantSortType.name:
        return restaurants..sort((a, b) => a.placeName.compareTo(b.placeName));
      case RestaurantSortType.category:
        return restaurants
          ..sort((a, b) => a.categoryName.compareTo(b.categoryName));
    }
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

/// 맛집 정렬 타입
enum RestaurantSortType {
  distance, // 거리순
  name, // 이름순
  category, // 카테고리순
}

/// 검색 결과 캐시
class _CachedSearchResult {
  final KakaoSearchResponse response;
  final DateTime timestamp;

  _CachedSearchResult({required this.response, required this.timestamp});

  bool get isExpired {
    return DateTime.now().difference(timestamp) > const Duration(minutes: 5);
  }
}
