import 'package:json_annotation/json_annotation.dart';

part 'location_models.g.dart';

/// 사용자 위치 정보
@JsonSerializable()
class UserLocation {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime timestamp;

  const UserLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.timestamp,
  });

  factory UserLocation.fromJson(Map<String, dynamic> json) =>
      _$UserLocationFromJson(json);

  Map<String, dynamic> toJson() => _$UserLocationToJson(this);

  @override
  String toString() {
    return 'UserLocation(lat: $latitude, lng: $longitude, accuracy: $accuracy)';
  }
}

/// 카카오 로컬 API 응답 - 장소 정보
@JsonSerializable()
class KakaoPlace {
  final String id;
  @JsonKey(name: 'place_name')
  final String placeName;
  @JsonKey(name: 'category_name')
  final String categoryName;
  @JsonKey(name: 'category_group_code')
  final String? categoryGroupCode;
  @JsonKey(name: 'category_group_name')
  final String? categoryGroupName;
  final String phone;
  @JsonKey(name: 'address_name')
  final String addressName;
  @JsonKey(name: 'road_address_name')
  final String? roadAddressName;
  final String x; // 경도
  final String y; // 위도
  @JsonKey(name: 'place_url')
  final String? placeUrl;
  final String? distance;

  const KakaoPlace({
    required this.id,
    required this.placeName,
    required this.categoryName,
    this.categoryGroupCode,
    this.categoryGroupName,
    required this.phone,
    required this.addressName,
    this.roadAddressName,
    required this.x,
    required this.y,
    this.placeUrl,
    this.distance,
  });

  factory KakaoPlace.fromJson(Map<String, dynamic> json) =>
      _$KakaoPlaceFromJson(json);

  Map<String, dynamic> toJson() => _$KakaoPlaceToJson(this);

  /// 거리를 미터 단위로 반환
  double? get distanceInMeters {
    if (distance == null) return null;
    return double.tryParse(distance!);
  }

  /// 거리를 킬로미터 단위로 반환 (소수점 1자리)
  String get distanceFormatted {
    final meters = distanceInMeters;
    if (meters == null) return '';

    if (meters < 1000) {
      return '${meters.toInt()}m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
  }

  /// 카카오맵 URL 생성
  String get kakaoMapUrl {
    return 'https://map.kakao.com/link/map/$placeName,$y,$x';
  }

  @override
  String toString() {
    return 'KakaoPlace(name: $placeName, address: $addressName, distance: $distanceFormatted)';
  }
}

/// 카카오 로컬 API 응답 - 메타 정보
@JsonSerializable()
class KakaoMeta {
  @JsonKey(name: 'total_count')
  final int totalCount;
  @JsonKey(name: 'pageable_count')
  final int pageableCount;
  @JsonKey(name: 'is_end')
  final bool isEnd;

  const KakaoMeta({
    required this.totalCount,
    required this.pageableCount,
    required this.isEnd,
  });

  factory KakaoMeta.fromJson(Map<String, dynamic> json) =>
      _$KakaoMetaFromJson(json);

  Map<String, dynamic> toJson() => _$KakaoMetaToJson(this);
}

/// 카카오 로컬 API 전체 응답
@JsonSerializable()
class KakaoSearchResponse {
  final KakaoMeta meta;
  final List<KakaoPlace> documents;

  const KakaoSearchResponse({required this.meta, required this.documents});

  factory KakaoSearchResponse.fromJson(Map<String, dynamic> json) =>
      _$KakaoSearchResponseFromJson(json);

  Map<String, dynamic> toJson() => _$KakaoSearchResponseToJson(this);
}

/// 맛집 검색 요청 파라미터
class RestaurantSearchParams {
  final String query;
  final double latitude;
  final double longitude;
  final int radius; // 미터 단위
  final int page;
  final int size;
  final String? categoryGroupCode; // 카카오 카테고리 그룹 코드

  const RestaurantSearchParams({
    required this.query,
    required this.latitude,
    required this.longitude,
    this.radius = 1000,
    this.page = 1,
    this.size = 15,
    this.categoryGroupCode,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'query': query,
      'x': longitude.toString(),
      'y': latitude.toString(),
      'radius': radius,
      'page': page,
      'size': size,
      'sort': 'distance',
    };

    // 카테고리 그룹 코드가 있으면 추가
    if (categoryGroupCode != null) {
      json['category_group_code'] = categoryGroupCode!;
    }

    return json;
  }
}

/// 위치 권한 상태
enum LocationPermissionStatus {
  denied,
  deniedForever,
  whileInUse,
  always,
  unableToDetermine,
}

/// 위치 서비스 상태
enum LocationServiceStatus { disabled, enabled, unknown }

/// 맛집 검색 상태
enum RestaurantSearchStatus {
  idle,
  loading,
  success,
  error,
  noPermission,
  noLocation,
}

/// 맛집 검색 결과 상태
class RestaurantSearchState {
  final RestaurantSearchStatus status;
  final List<KakaoPlace> restaurants;
  final String? errorMessage;
  final UserLocation? currentLocation;

  const RestaurantSearchState({
    this.status = RestaurantSearchStatus.idle,
    this.restaurants = const [],
    this.errorMessage,
    this.currentLocation,
  });

  RestaurantSearchState copyWith({
    RestaurantSearchStatus? status,
    List<KakaoPlace>? restaurants,
    String? errorMessage,
    UserLocation? currentLocation,
  }) {
    return RestaurantSearchState(
      status: status ?? this.status,
      restaurants: restaurants ?? this.restaurants,
      errorMessage: errorMessage ?? this.errorMessage,
      currentLocation: currentLocation ?? this.currentLocation,
    );
  }

  bool get isLoading => status == RestaurantSearchStatus.loading;
  bool get hasError => status == RestaurantSearchStatus.error;
  bool get hasRestaurants => restaurants.isNotEmpty;
  bool get hasLocation => currentLocation != null;
}

/// 위치 관련 예외
class LocationException implements Exception {
  final String message;
  const LocationException(this.message);

  @override
  String toString() => message;
}

/// 위치 권한 거부 예외
class UserPermissionDeniedException implements Exception {
  final String message;
  const UserPermissionDeniedException(this.message);

  @override
  String toString() => message;
}
