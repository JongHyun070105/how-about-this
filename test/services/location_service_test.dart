import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:review_ai/data/models/location_models.dart';
import 'package:review_ai/services/location_service.dart';

void main() {
  late LocationService locationService;

  // 모킹용 가짜 Position 생성 헬퍼
  Position createMockPosition({
    required double latitude,
    required double longitude,
  }) {
    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: 10.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
  }

  setUp(() {
    locationService = LocationService();
  });

  tearDown(() {
    // 모든 정적 모킹 필드 리셋
    LocationService.mockIsLocationServiceEnabled = null;
    LocationService.mockGetCurrentPosition = null;
    LocationService.mockCheckPermission = null;
    LocationService.mockRequestPermission = null;
    LocationService.mockOpenLocationSettings = null;
    LocationService.mockOpenAppSettings = null;
    LocationService.mockDistanceBetween = null;
  });

  group('LocationService - 권한 및 서비스 활성화 예외 테스트', () {
    test('위치 권한이 denied인 경우 UserPermissionDeniedException을 던져야 함', () async {
      LocationService.mockCheckPermission = () async =>
          LocationPermission.denied;

      expect(
        () => locationService.getCurrentLocation(),
        throwsA(isA<UserPermissionDeniedException>()),
      );
    });

    test(
      '위치 권한이 deniedForever인 경우 UserPermissionDeniedException을 던져야 함',
      () async {
        LocationService.mockCheckPermission = () async =>
            LocationPermission.deniedForever;

        expect(
          () => locationService.getCurrentLocation(),
          throwsA(isA<UserPermissionDeniedException>()),
        );
      },
    );

    test('위치 권한은 있으나 위치 서비스가 꺼져 있는 경우 LocationException을 던져야 함', () async {
      LocationService.mockCheckPermission = () async =>
          LocationPermission.whileInUse;
      LocationService.mockIsLocationServiceEnabled = () async => false;

      expect(
        () => locationService.getCurrentLocation(),
        throwsA(
          isA<LocationException>().having(
            (e) => e.message,
            'message',
            contains('위치 서비스가 비활성화'),
          ),
        ),
      );
    });
  });

  group('LocationService - 위치 획득 및 캐싱 테스트', () {
    test('위치 권한 및 서비스가 활성화된 정상 상태에서 위치 정보를 반환하고 캐싱해야 함', () async {
      LocationService.mockCheckPermission = () async =>
          LocationPermission.always;
      LocationService.mockIsLocationServiceEnabled = () async => true;

      int gpsCallCount = 0;
      LocationService.mockGetCurrentPosition = (accuracy, timeout) async {
        gpsCallCount++;
        return createMockPosition(latitude: 37.5665, longitude: 126.9780);
      };

      // 1. 첫 번째 조회: GPS 조회 수행
      final location1 = await locationService.getCurrentLocation();
      expect(location1, isNotNull);
      expect(location1!.latitude, equals(37.5665));
      expect(location1.longitude, equals(126.9780));
      expect(gpsCallCount, equals(1));

      // 2. 두 번째 조회: 캐시가 동작하여 GPS 조회를 다시 수행하지 않음
      final location2 = await locationService.getCurrentLocation();
      expect(location2, isNotNull);
      expect(location2!.latitude, equals(37.5665));
      expect(location2.longitude, equals(126.9780));
      expect(gpsCallCount, equals(1)); // 호출 횟수가 늘어나지 않음
    });

    test('캐시 초기화(clearLocationCache) 시 다시 GPS 조회를 수행해야 함', () async {
      LocationService.mockCheckPermission = () async =>
          LocationPermission.whileInUse;
      LocationService.mockIsLocationServiceEnabled = () async => true;

      int gpsCallCount = 0;
      LocationService.mockGetCurrentPosition = (accuracy, timeout) async {
        gpsCallCount++;
        return createMockPosition(latitude: 37.5665, longitude: 126.9780);
      };

      // 1. 최초 조회
      await locationService.getCurrentLocation();
      expect(gpsCallCount, equals(1));

      // 2. 캐시 지우기
      locationService.clearLocationCache();

      // 3. 재조회: 캐시가 유효하지 않아 다시 GPS 요청
      await locationService.getCurrentLocation();
      expect(gpsCallCount, equals(2));
    });

    test('캐시된 위치가 있어도 권한이 철회되면 위치를 반환하지 않아야 함', () async {
      LocationService.mockCheckPermission = () async =>
          LocationPermission.whileInUse;
      LocationService.mockIsLocationServiceEnabled = () async => true;
      LocationService.mockGetCurrentPosition = (accuracy, timeout) async {
        return createMockPosition(latitude: 37.5665, longitude: 126.9780);
      };

      await locationService.getCurrentLocation();
      LocationService.mockCheckPermission = () async =>
          LocationPermission.denied;

      expect(
        () => locationService.getCurrentLocation(),
        throwsA(isA<UserPermissionDeniedException>()),
      );
    });

    test('위치 서비스가 꺼져 있으면 캐시된 위치도 반환하지 않아야 함', () async {
      LocationService.mockCheckPermission = () async =>
          LocationPermission.whileInUse;
      LocationService.mockIsLocationServiceEnabled = () async => true;
      LocationService.mockGetCurrentPosition = (accuracy, timeout) async {
        return createMockPosition(latitude: 37.5665, longitude: 126.9780);
      };

      await locationService.getCurrentLocation();
      LocationService.mockIsLocationServiceEnabled = () async => false;

      expect(
        () => locationService.getCurrentLocation(),
        throwsA(isA<LocationException>()),
      );
    });
  });

  group('LocationService - 기타 유틸 메소드 및 설정 이동 테스트', () {
    test('isValidLocation 위경도 범위 유효성 검증', () {
      expect(locationService.isValidLocation(37.5, 127.0), isTrue);
      expect(locationService.isValidLocation(-91.0, 100.0), isFalse);
      expect(locationService.isValidLocation(45.0, 181.0), isFalse);
      expect(locationService.isValidLocation(90.0, -180.0), isTrue);
    });

    test('calculateDistance가 distanceBetween 모킹을 정상적으로 타는지 검증', () {
      LocationService.mockDistanceBetween = (lat1, lng1, lat2, lng2) {
        return 123.45;
      };

      final distance = locationService.calculateDistance(0, 0, 1, 1);
      expect(distance, equals(123.45));
    });

    test('checkLocationService 상태 매핑 검증', () async {
      LocationService.mockIsLocationServiceEnabled = () async => true;
      expect(
        await locationService.checkLocationService(),
        equals(LocationServiceStatus.enabled),
      );

      LocationService.mockIsLocationServiceEnabled = () async => false;
      expect(
        await locationService.checkLocationService(),
        equals(LocationServiceStatus.disabled),
      );
    });

    test('openLocationSettings 및 openAppSettings 정상 호출 확인', () async {
      bool settingsOpened = false;
      bool appSettingsOpened = false;

      LocationService.mockOpenLocationSettings = () async {
        settingsOpened = true;
      };
      LocationService.mockOpenAppSettings = () async {
        appSettingsOpened = true;
      };

      await locationService.openLocationSettings();
      await locationService.openAppSettings();

      expect(settingsOpened, isTrue);
      expect(appSettingsOpened, isTrue);
    });
  });
}
