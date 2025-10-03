import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/location_service.dart';
import '../services/kakao_api_service.dart';
import '../models/location_models.dart';

/// 위치 서비스 프로바이더
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

/// 카카오 API 서비스 프로바이더
final kakaoApiServiceProvider = Provider<KakaoApiService>((ref) {
  return KakaoApiService();
});

/// 맛집 검색 상태 프로바이더
final restaurantSearchProvider =
    StateNotifierProvider<RestaurantSearchNotifier, RestaurantSearchState>((
      ref,
    ) {
      final locationService = ref.watch(locationServiceProvider);
      final kakaoApiService = ref.watch(kakaoApiServiceProvider);
      return RestaurantSearchNotifier(locationService, kakaoApiService);
    });

/// 맛집 검색 상태 관리 클래스
class RestaurantSearchNotifier extends StateNotifier<RestaurantSearchState> {
  final LocationService _locationService;
  final KakaoApiService _kakaoApiService;

  RestaurantSearchNotifier(this._locationService, this._kakaoApiService)
    : super(const RestaurantSearchState());

  /// 음식 이름으로 맛집을 검색합니다.
  Future<void> searchRestaurants({
    required String foodName,
    required String category,
    int radius = 1000,
    int page = 1,
    int size = 15,
  }) async {
    try {
      state = state.copyWith(status: RestaurantSearchStatus.loading);

      // 현재 위치 가져오기
      final location = await _locationService.getCurrentLocation();
      if (location == null) {
        state = state.copyWith(
          status: RestaurantSearchStatus.noLocation,
          errorMessage: '위치 정보를 가져올 수 없습니다.',
        );
        return;
      }

      state = state.copyWith(currentLocation: location);

      // 검색어 최적화
      final searchQuery = _kakaoApiService.getCategorySearchQuery(
        category,
        foodName,
      );

      // 맛집 검색 (카테고리 코드 사용)
      final restaurants = await _kakaoApiService.searchRestaurants(
        foodName: searchQuery,
        latitude: location.latitude,
        longitude: location.longitude,
        category: category, // 카테고리 전달
        radius: radius,
        page: page,
        size: size,
      );

      // 검색 결과 필터링 및 정렬 (카테고리 필터링 강화)
      final filteredRestaurants = _kakaoApiService.filterRestaurants(
        restaurants,
        targetCategory: category, // 원하는 카테고리 지정
        maxDistance: radius,
        excludeCategories: _getExcludeCategories(category),
      );

      final sortedRestaurants = _kakaoApiService.sortRestaurants(
        filteredRestaurants,
        sortType: RestaurantSortType.distance,
      );

      state = state.copyWith(
        status: RestaurantSearchStatus.success,
        restaurants: sortedRestaurants,
        errorMessage: null,
      );
    } on LocationException catch (e) {
      if (e.message.contains('권한')) {
        state = state.copyWith(
          status: RestaurantSearchStatus.noPermission,
          errorMessage: e.message,
        );
      } else {
        state = state.copyWith(
          status: RestaurantSearchStatus.error,
          errorMessage: e.message,
        );
      }
    } on KakaoApiException catch (e) {
      state = state.copyWith(
        status: RestaurantSearchStatus.error,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        status: RestaurantSearchStatus.error,
        errorMessage: '예상치 못한 오류가 발생했습니다: ${e.toString()}',
      );
    }
  }

  /// 위치 권한을 요청합니다.
  Future<void> requestLocationPermission() async {
    try {
      final permission = await _locationService.requestLocationPermission();

      if (permission == LocationPermissionStatus.deniedForever) {
        state = state.copyWith(
          status: RestaurantSearchStatus.noPermission,
          errorMessage: '위치 권한이 영구적으로 거부되었습니다. 설정에서 권한을 허용해주세요.',
        );
      } else if (permission == LocationPermissionStatus.denied) {
        state = state.copyWith(
          status: RestaurantSearchStatus.noPermission,
          errorMessage: '위치 권한이 거부되었습니다.',
        );
      } else {
        // 권한이 허용된 경우, 현재 위치 가져오기
        final location = await _locationService.getCurrentLocation();
        state = state.copyWith(
          status: RestaurantSearchStatus.idle,
          currentLocation: location,
          errorMessage: null,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: RestaurantSearchStatus.error,
        errorMessage: '권한 요청 중 오류가 발생했습니다: ${e.toString()}',
      );
    }
  }

  /// 위치 서비스 설정을 엽니다.
  Future<void> openLocationSettings() async {
    await _locationService.openLocationSettings();
  }

  /// 앱 설정을 엽니다.
  Future<void> openAppSettings() async {
    await _locationService.openAppSettings();
  }

  /// 검색 상태를 초기화합니다.
  void clearSearch() {
    state = state.copyWith(
      status: RestaurantSearchStatus.idle,
      restaurants: [],
      errorMessage: null,
    );
  }

  /// 위치 캐시를 초기화합니다.
  void clearLocationCache() {
    _locationService.clearLocationCache();
    state = state.copyWith(
      currentLocation: null,
      status: RestaurantSearchStatus.idle,
    );
  }

  /// 카테고리별 제외할 카테고리 목록을 반환합니다.
  List<String> _getExcludeCategories(String category) {
    switch (category) {
      case '한식':
        return ['중식', '일식', '양식', '분식', '아시안', '패스트푸드', '편의점', '카페'];
      case '중식':
        return ['한식', '일식', '양식', '분식', '아시안', '패스트푸드', '편의점', '카페'];
      case '일식':
        return ['한식', '중식', '양식', '분식', '아시안', '패스트푸드', '편의점', '카페'];
      case '양식':
        return ['한식', '중식', '일식', '분식', '아시안', '패스트푸드', '편의점', '카페'];
      case '분식':
        return ['한식', '중식', '일식', '양식', '아시안', '패스트푸드', '편의점', '카페'];
      case '아시안':
        return ['한식', '중식', '일식', '양식', '분식', '패스트푸드', '편의점', '카페'];
      case '패스트푸드':
        return ['한식', '중식', '일식', '양식', '분식', '아시안', '편의점', '카페'];
      case '편의점':
        return ['한식', '중식', '일식', '양식', '분식', '아시안', '패스트푸드', '카페'];
      case '카페':
        return ['한식', '중식', '일식', '양식', '분식', '아시안', '패스트푸드', '편의점'];
      default:
        return [];
    }
  }
}

/// 위치 권한 상태 프로바이더
final locationPermissionProvider = FutureProvider<LocationPermissionStatus>((
  ref,
) async {
  final locationService = ref.watch(locationServiceProvider);
  return await locationService.requestLocationPermission();
});

/// 위치 서비스 상태 프로바이더
final locationServiceStatusProvider = FutureProvider<LocationServiceStatus>((
  ref,
) async {
  final locationService = ref.watch(locationServiceProvider);
  return await locationService.checkLocationService();
});

/// 현재 위치 프로바이더
final currentLocationProvider = FutureProvider<UserLocation?>((ref) async {
  final locationService = ref.watch(locationServiceProvider);
  return await locationService.getCurrentLocation();
});
