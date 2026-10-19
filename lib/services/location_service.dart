import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:review_ai/data/models/location_models.dart';
import 'package:review_ai/utils/error_handler.dart';

/// 위치 서비스 클래스
/// 사용자의 현재 위치를 가져오고 권한을 관리합니다.
class LocationService {
  @visibleForTesting
  static Future<bool> Function()? mockIsLocationServiceEnabled;

  @visibleForTesting
  static Future<Position> Function(
    LocationAccuracy desiredAccuracy,
    Duration? timeLimit,
  )?
  mockGetCurrentPosition;

  @visibleForTesting
  static Future<LocationPermission> Function()? mockCheckPermission;

  @visibleForTesting
  static Future<LocationPermission> Function()? mockRequestPermission;

  @visibleForTesting
  static Future<void> Function()? mockOpenLocationSettings;

  @visibleForTesting
  static Future<void> Function()? mockOpenAppSettings;

  @visibleForTesting
  static double Function(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  )?
  mockDistanceBetween;

  static const Duration _locationTimeout = Duration(seconds: 10);
  static const Duration _locationCacheTimeout = Duration(minutes: 5);

  UserLocation? _cachedLocation;
  Stopwatch? _locationCacheAge;

  /// 현재 위치를 가져옵니다.
  /// 캐시된 위치가 있고 유효하면 캐시를 반환합니다.
  Future<UserLocation?> getCurrentLocation() async {
    try {
      final permission = await _checkLocationPermission();
      if (permission != LocationPermissionStatus.whileInUse &&
          permission != LocationPermissionStatus.always) {
        throw const UserPermissionDeniedException('위치 권한이 필요합니다.');
      }

      final serviceEnabled = await _isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const LocationException('위치 서비스가 비활성화되어 있습니다.');
      }

      if (_isLocationCacheValid()) {
        return _cachedLocation;
      }

      // 현재 위치 가져오기
      final position = await _getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: _locationTimeout,
      );

      final now = DateTime.now();
      // 위치 정보 캐싱
      _cachedLocation = UserLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: now,
      );
      _locationCacheAge = Stopwatch()..start();

      return _cachedLocation;
    } on UserPermissionDeniedException {
      rethrow;
    } on LocationException {
      rethrow;
    } catch (e) {
      throw LocationException(ErrorHandler.sanitizeMessage(e));
    }
  }

  /// Geolocator 권한을 앱 고유 상태 권한으로 매핑해주는 공통 헬퍼
  LocationPermissionStatus _mapPermission(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.denied:
        return LocationPermissionStatus.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.whileInUse;
      case LocationPermission.always:
        return LocationPermissionStatus.always;
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.unableToDetermine;
    }
  }

  /// 위치 권한 상태를 확인합니다.
  Future<LocationPermissionStatus> _checkLocationPermission() async {
    final permission = await _checkPermission();
    return _mapPermission(permission);
  }

  /// 위치 권한을 요청합니다.
  Future<LocationPermissionStatus> requestLocationPermission() async {
    final permission = await _requestPermission();
    return _mapPermission(permission);
  }

  /// 위치 서비스가 활성화되어 있는지 확인합니다.
  Future<LocationServiceStatus> checkLocationService() async {
    try {
      final serviceEnabled = await _isLocationServiceEnabled();
      return serviceEnabled
          ? LocationServiceStatus.enabled
          : LocationServiceStatus.disabled;
    } catch (e) {
      return LocationServiceStatus.unknown;
    }
  }

  /// 위치 서비스 설정으로 이동합니다.
  Future<void> openLocationSettings() async {
    await _openLocationSettings();
  }

  /// 앱 설정으로 이동합니다.
  Future<void> openAppSettings() async {
    await _openAppSettings();
  }

  /// 캐시된 위치가 유효한지 확인합니다.
  bool _isLocationCacheValid() {
    if (_cachedLocation == null || _locationCacheAge == null) {
      return false;
    }

    return _locationCacheAge!.elapsed < _locationCacheTimeout;
  }

  /// 위치 캐시를 초기화합니다.
  void clearLocationCache() {
    _cachedLocation = null;
    _locationCacheAge = null;
  }

  /// 두 위치 간의 거리를 계산합니다 (미터 단위).
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return _distanceBetween(lat1, lng1, lat2, lng2);
  }

  /// 위치가 유효한지 확인합니다.
  bool isValidLocation(double latitude, double longitude) {
    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  Future<bool> _isLocationServiceEnabled() async {
    if (mockIsLocationServiceEnabled != null) {
      return mockIsLocationServiceEnabled!();
    }
    return Geolocator.isLocationServiceEnabled();
  }

  Future<Position> _getCurrentPosition({
    required LocationAccuracy desiredAccuracy,
    required Duration timeLimit,
  }) async {
    if (mockGetCurrentPosition != null) {
      return mockGetCurrentPosition!(desiredAccuracy, timeLimit);
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: desiredAccuracy,
      timeLimit: timeLimit,
    );
  }

  Future<LocationPermission> _checkPermission() async {
    if (mockCheckPermission != null) {
      return mockCheckPermission!();
    }
    return Geolocator.checkPermission();
  }

  Future<LocationPermission> _requestPermission() async {
    if (mockRequestPermission != null) {
      return mockRequestPermission!();
    }
    return Geolocator.requestPermission();
  }

  Future<void> _openLocationSettings() async {
    if (mockOpenLocationSettings != null) {
      await mockOpenLocationSettings!();
    } else {
      await Geolocator.openLocationSettings();
    }
  }

  Future<void> _openAppSettings() async {
    if (mockOpenAppSettings != null) {
      await mockOpenAppSettings!();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  double _distanceBetween(double lat1, double lng1, double lat2, double lng2) {
    if (mockDistanceBetween != null) {
      return mockDistanceBetween!(lat1, lng1, lat2, lng2);
    }
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }
}
