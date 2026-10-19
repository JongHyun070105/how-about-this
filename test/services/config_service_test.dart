import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:review_ai/services/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const mockServerResponse = {
    'adMob': {
      'ios': {'rewarded': 'ios_rewarded_123', 'banner': 'ios_banner_123'},
      'android': {
        'rewarded': 'android_rewarded_123',
        'banner': 'android_banner_123',
      },
    },
    'clarityProjectId': 'my_clarity_project_id',
    'firebase': {
      'apiKeyAndroid': 'android_firebase_key',
      'apiKeyIos': 'ios_firebase_key',
    },
  };

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 캐시 메모리 오염 차단 및 모킹 데이터 리셋
    ConfigService.mockClient = null;
    ConfigService.mockPrefs = null;
    ConfigService.mockTimeMs = null;
    ConfigService.resetInMemoryCache();
  });

  tearDown(() {
    ConfigService.mockClient = null;
    ConfigService.mockPrefs = null;
    ConfigService.mockTimeMs = null;
    ConfigService.resetInMemoryCache();
  });

  group('ConfigService - 서버 로딩 및 캐싱 검증 테스트', () {
    test('로컬 캐시가 없을 때 서버 API를 호출하여 설정을 캐싱하고 반환해야 함', () async {
      SharedPreferences.setMockInitialValues({});

      bool apiCalled = false;
      ConfigService.mockClient = MockClient((request) async {
        apiCalled = true;
        expect(request.url.path, equals('/api/config'));
        return http.Response(jsonEncode(mockServerResponse), 200);
      });

      // 캐시 리셋
      await ConfigService.clearCache();

      final config = await ConfigService.getAdMobConfig();
      expect(config, isNotNull);
      expect(config['clarityProjectId'], equals('my_clarity_project_id'));
      expect(apiCalled, isTrue);

      // SharedPreferences에 정상 캐싱 확인
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('remote_config_cache'), isNotNull);
      expect(prefs.getInt('remote_config_cache_time'), isNotNull);
    });

    test('캐시 유효시간(24시간) 이내인 경우 서버 재호출 없이 캐시 데이터를 즉시 반환해야 함', () async {
      final initialTime = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'remote_config_cache': jsonEncode(mockServerResponse),
        'remote_config_cache_time': initialTime,
      });

      int apiCallCount = 0;
      ConfigService.mockClient = MockClient((request) async {
        apiCallCount++;
        return http.Response(jsonEncode(mockServerResponse), 200);
      });

      // 캐시 리셋 (메모리 캐시만 리셋하기 위해 SharedPreferences 정보는 유지해야 함)
      // ConfigService.clearCache()를 부르면 prefs 캐시도 삭제되므로,
      // 내부 static _cachedConfig = null을 초기화하기 위해 clearCache를 부르는 대신
      // prefs 데이터는 놔두고 메모리 캐시만 리셋해야 한다.
      // ConfigService.dart 에서는 캐시 클리어 시 prefs까지 지우므로,
      // 이 테스트를 위해서는 ConfigService.getAdMobConfig()를 최초 1회 빈 상태로 부르되
      // SharedPreferences 모킹 데이터가 복구되도록 세팅해야 한다.

      ConfigService.mockTimeMs =
          initialTime + const Duration(hours: 5).inMilliseconds; // 5시간 경과

      // 첫 호출: SharedPreferences 로컬 캐시로부터 데이터 획득 (서버 호출 없음)
      final config = await ConfigService.getAdMobConfig();
      expect(config['clarityProjectId'], equals('my_clarity_project_id'));
      expect(apiCallCount, equals(0));
    });

    test('메모리 설정 캐시도 24시간 후 서버 설정으로 갱신한다', () async {
      SharedPreferences.setMockInitialValues({});
      final initialTime = DateTime.now().millisecondsSinceEpoch;
      ConfigService.mockTimeMs = initialTime;
      var apiCallCount = 0;
      ConfigService.mockClient = MockClient((request) async {
        apiCallCount++;
        final response = Map<String, dynamic>.from(mockServerResponse);
        response['clarityProjectId'] = apiCallCount == 1
            ? 'first_config'
            : 'refreshed_config';
        return http.Response(jsonEncode(response), 200);
      });

      final firstConfig = await ConfigService.getAdMobConfig();
      expect(firstConfig['clarityProjectId'], 'first_config');

      ConfigService.mockTimeMs =
          initialTime + const Duration(hours: 25).inMilliseconds;
      final refreshedConfig = await ConfigService.getAdMobConfig();

      expect(refreshedConfig['clarityProjectId'], 'refreshed_config');
      expect(apiCallCount, 2);
    });

    test('캐시 유효시간(24시간)이 지난 경우 캐시를 무시하고 서버 API를 재호출해야 함', () async {
      final initialTime = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'remote_config_cache': jsonEncode(mockServerResponse),
        'remote_config_cache_time': initialTime,
      });

      bool apiCalled = false;
      ConfigService.mockClient = MockClient((request) async {
        apiCalled = true;
        return http.Response(jsonEncode(mockServerResponse), 200);
      });

      // 25시간 경과 시뮬레이션
      ConfigService.mockTimeMs =
          initialTime + const Duration(hours: 25).inMilliseconds;

      final config = await ConfigService.getAdMobConfig();
      expect(config['clarityProjectId'], equals('my_clarity_project_id'));
      expect(apiCalled, isTrue); // 서버 재호출 정상 트리거됨
    });

    test('기기 시간이 캐시 저장 시각보다 과거면 서버 설정을 다시 확인한다', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'remote_config_cache': jsonEncode(mockServerResponse),
        'remote_config_cache_time':
            now + const Duration(days: 3).inMilliseconds,
      });
      ConfigService.mockTimeMs = now;
      var apiCalled = false;
      ConfigService.mockClient = MockClient((request) async {
        apiCalled = true;
        return http.Response(jsonEncode(mockServerResponse), 200);
      });

      await ConfigService.getAdMobConfig();

      expect(apiCalled, isTrue);
    });

    test('캐시에 firebase 블록이 없는 구버전 캐시의 경우 캐시를 무시하고 서버 재요청을 해야 함', () async {
      final initialTime = DateTime.now().millisecondsSinceEpoch;
      final oldServerResponse = {
        'adMob': {
          'ios': {'rewarded': 'old', 'banner': 'old'},
          'android': {'rewarded': 'old', 'banner': 'old'},
        }, // firebase 및 clarityProjectId 누락
      };

      SharedPreferences.setMockInitialValues({
        'remote_config_cache': jsonEncode(oldServerResponse),
        'remote_config_cache_time': initialTime,
      });

      bool apiCalled = false;
      ConfigService.mockClient = MockClient((request) async {
        apiCalled = true;
        return http.Response(jsonEncode(mockServerResponse), 200);
      });

      ConfigService.mockTimeMs =
          initialTime +
          const Duration(hours: 1).inMilliseconds; // 1시간 경과(만료 미만)

      final config = await ConfigService.getAdMobConfig();
      expect(config['firebase'], isNotNull); // 새 서버 데이터로 교체됨
      expect(apiCalled, isTrue);
    });
  });

  group('ConfigService - 오류 복구 및 Fallback 검증 테스트', () {
    test('서버 에러(500) 발생 시 만료된 캐시가 존재하면 해당 만료 캐시로 폴백 복구해야 함', () async {
      final initialTime = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'remote_config_cache': jsonEncode(mockServerResponse),
        'remote_config_cache_time': initialTime,
      });

      ConfigService.mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      // 30시간 경과 시뮬레이션 (캐시 만료됨)
      ConfigService.mockTimeMs =
          initialTime + const Duration(hours: 30).inMilliseconds;

      final config = await ConfigService.getAdMobConfig();
      expect(
        config['clarityProjectId'],
        equals('my_clarity_project_id'),
      ); // 예외 없이 만료 캐시 정상 복구 확인
    });

    test('서버 통신이 완전히 실패하고 로컬 캐시도 없는 경우 default 설정을 안전하게 반환해야 함', () async {
      SharedPreferences.setMockInitialValues({});
      await ConfigService.clearCache();

      ConfigService.mockClient = MockClient((request) async {
        throw Exception('Connection failed');
      });

      final config = await ConfigService.getAdMobConfig();
      expect(config, isNotNull);
      expect(config['adMob'], isNotNull);
      expect(config['adMob']['ios']['rewarded'], equals(''));
    });
  });

  group('ConfigService - 개별 플랫폼 파라미터 파싱 검증 테스트', () {
    test('getAdUnitId 플랫폼별 ID 올바르게 반환 확인', () async {
      SharedPreferences.setMockInitialValues({
        'remote_config_cache': jsonEncode(mockServerResponse),
        'remote_config_cache_time': DateTime.now().millisecondsSinceEpoch,
      });

      final iosAdId = await ConfigService.getAdUnitId(
        platform: 'ios',
        adType: 'rewarded',
      );
      final androidAdId = await ConfigService.getAdUnitId(
        platform: 'android',
        adType: 'banner',
      );

      expect(iosAdId, equals('ios_rewarded_123'));
      expect(androidAdId, equals('android_banner_123'));
    });

    test('getClarityProjectId 프로젝트 ID 반환 검증', () async {
      SharedPreferences.setMockInitialValues({
        'remote_config_cache': jsonEncode(mockServerResponse),
        'remote_config_cache_time': DateTime.now().millisecondsSinceEpoch,
      });

      final clarityId = await ConfigService.getClarityProjectId();
      expect(clarityId, equals('my_clarity_project_id'));
    });

    test('getFirebaseApiKey 플랫폼별 API key 획득 검증', () async {
      SharedPreferences.setMockInitialValues({
        'remote_config_cache': jsonEncode(mockServerResponse),
        'remote_config_cache_time': DateTime.now().millisecondsSinceEpoch,
      });

      final androidApiKey = await ConfigService.getFirebaseApiKey(
        platform: 'Android',
      );
      final iosApiKey = await ConfigService.getFirebaseApiKey(platform: 'iOS');

      expect(androidApiKey, equals('android_firebase_key'));
      expect(iosApiKey, equals('ios_firebase_key'));
    });
  });
}
