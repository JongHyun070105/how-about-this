import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
// permission_handler는 더 이상 사용하지 않음
import '../models/location_models.dart';

/// 위치 서비스 클래스
/// 사용자의 현재 위치를 가져오고 권한을 관리합니다.
class LocationService {
  static const Duration _locationTimeout = Duration(seconds: 10);
  static const Duration _locationCacheTimeout = Duration(minutes: 5);

  UserLocation? _cachedLocation;
  DateTime? _lastLocationUpdate;

  /// 현재 위치를 가져옵니다.
  /// 캐시된 위치가 있고 유효하면 캐시를 반환합니다.
  Future<UserLocation?> getCurrentLocation() async {
    try {
      // 캐시된 위치가 유효한지 확인
      if (_isLocationCacheValid()) {
        return _cachedLocation;
      }

      // 위치 권한 확인
      final permission = await _checkLocationPermission();
      debugPrint('현재 위치 권한 상태: $permission');
      if (permission != LocationPermissionStatus.whileInUse &&
          permission != LocationPermissionStatus.always) {
        debugPrint('위치 권한이 부족합니다. 현재 상태: $permission');
        throw LocationException('위치 권한이 필요합니다.');
      }

      // 위치 서비스 활성화 확인
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw LocationException('위치 서비스가 비활성화되어 있습니다.');
      }

      // 현재 위치 가져오기
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: _locationTimeout,
      );

      // 위치 정보 캐싱
      _cachedLocation = UserLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: DateTime.now(),
      );
      _lastLocationUpdate = DateTime.now();

      return _cachedLocation;
    } catch (e) {
      throw LocationException('위치를 가져올 수 없습니다: ${e.toString()}');
    }
  }

  /// 위치 권한 상태를 확인합니다.
  Future<LocationPermissionStatus> _checkLocationPermission() async {
    final permission = await Geolocator.checkPermission();

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

  /// 위치 권한을 요청합니다.
  Future<LocationPermissionStatus> requestLocationPermission() async {
    final permission = await Geolocator.requestPermission();

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

  /// 위치 서비스가 활성화되어 있는지 확인합니다.
  Future<LocationServiceStatus> checkLocationService() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      return serviceEnabled
          ? LocationServiceStatus.enabled
          : LocationServiceStatus.disabled;
    } catch (e) {
      return LocationServiceStatus.unknown;
    }
  }

  /// 위치 서비스 설정으로 이동합니다.
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// 앱 설정으로 이동합니다.
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  /// 캐시된 위치가 유효한지 확인합니다.
  bool _isLocationCacheValid() {
    if (_cachedLocation == null || _lastLocationUpdate == null) {
      return false;
    }

    final now = DateTime.now();
    final timeDiff = now.difference(_lastLocationUpdate!);
    return timeDiff < _locationCacheTimeout;
  }

  /// 위치 캐시를 초기화합니다.
  void clearLocationCache() {
    _cachedLocation = null;
    _lastLocationUpdate = null;
  }

  /// 두 위치 간의 거리를 계산합니다 (미터 단위).
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  /// 위치가 유효한지 확인합니다.
  bool isValidLocation(double latitude, double longitude) {
    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }
}

/// 위치 관련 예외 클래스
class LocationException implements Exception {
  final String message;

  const LocationException(this.message);

  @override
  String toString() => 'LocationException: $message';
}
