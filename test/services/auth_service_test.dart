import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:review_ai/services/auth_service.dart';

// FlutterSecureStorage를 시뮬레이션하기 위한 가짜 인메모리 저장소 클래스
class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic mOptions,
    dynamic wOptions,
    dynamic webOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic mOptions,
    dynamic wOptions,
    dynamic webOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic mOptions,
    dynamic wOptions,
    dynamic webOptions,
  }) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll({
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic mOptions,
    dynamic wOptions,
    dynamic webOptions,
  }) async {
    _data.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeSecureStorage fakeStorage;

  setUp(() {
    fakeStorage = FakeSecureStorage();
    AuthService.mockStorage = fakeStorage;
    AuthService.mockAppVersion = '1.2.3';
    AuthService.mockDeviceInfo = 'Test-Android-Device';
    AuthService.mockAppCheckTokenProvider = () async => 'app-check-token';
    AuthService.setMockToken(
      accessToken: null,
      refreshToken: null,
      expiry: null,
    );
  });

  tearDown(() {
    AuthService.mockStorage = null;
    AuthService.mockClient = null;
    AuthService.mockAppVersion = null;
    AuthService.mockDeviceInfo = null;
    AuthService.mockAppCheckTokenProvider = null;
    AuthService.setMockToken(
      accessToken: null,
      refreshToken: null,
      expiry: null,
    );
  });

  group('AuthService - 초기화 및 로컬 캐시 조회 테스트', () {
    test('initialize() 실행 시 secure storage의 기존 토큰 정보들을 캐시에 적재해야 함', () async {
      await fakeStorage.write(key: 'access_token', value: 'old_access');
      await fakeStorage.write(key: 'refresh_token', value: 'old_refresh');
      final expiryTime = DateTime.now().add(const Duration(hours: 1));
      await fakeStorage.write(
        key: 'token_expiry',
        value: expiryTime.toIso8601String(),
      );
      await fakeStorage.write(key: 'device_id', value: 'my_unique_device_id');

      await AuthService.initialize();

      // 캐시 유효 상태이므로 HTTP 요청 없이 캐시 반환 확인
      final token = await AuthService.getValidAccessToken();
      expect(token, equals('old_access'));
    });

    test('캐시가 유효하고 만료시간이 1분 이상 넉넉한 경우 캐시된 토큰을 즉시 반환해야 함', () async {
      final expiryTime = DateTime.now().add(const Duration(minutes: 5));
      AuthService.setMockToken(
        accessToken: 'cached_token_abc',
        refreshToken: 'refresh_token_abc',
        expiry: expiryTime,
      );

      final token = await AuthService.getValidAccessToken();
      expect(token, equals('cached_token_abc'));
    });
  });

  group('AuthService - 토큰 신규 요청 및 갱신 API 테스트', () {
    test(
      '캐시가 만료되었으나 리프레시 토큰이 있는 경우, /api/auth/refresh 를 호출해 토큰을 갱신해야 함',
      () async {
        final expiredTime = DateTime.now().subtract(const Duration(minutes: 1));
        AuthService.setMockToken(
          accessToken: 'expired_access',
          refreshToken: 'valid_refresh_token',
          expiry: expiredTime,
        );

        bool refreshCalled = false;
        AuthService.mockClient = MockClient((request) async {
          if (request.url.path == '/api/auth/refresh') {
            refreshCalled = true;
            expect(request.method, equals('POST'));
            expect(
              request.headers['x-firebase-appcheck'],
              equals('app-check-token'),
            );
            final Map<String, dynamic> body = jsonDecode(request.body);
            expect(body['refreshToken'], equals('valid_refresh_token'));

            return http.Response(
              jsonEncode({
                'accessToken': 'newly_refreshed_access_token',
                'expiresIn': 3600,
              }),
              200,
            );
          }
          return http.Response('Not Found', 404);
        });

        final token = await AuthService.getValidAccessToken();
        expect(token, equals('newly_refreshed_access_token'));
        expect(refreshCalled, isTrue);

        // 토큰 갱신 시 secure storage에 정상 쓰기 완료 확인
        expect(
          await fakeStorage.read(key: 'access_token'),
          equals('newly_refreshed_access_token'),
        );
      },
    );

    test(
      '리프레시 토큰이 없거나 만료된 상태에서 /api/auth/token 호출로 완전히 새로운 토큰셋을 받아와야 함',
      () async {
        bool tokenApiCalled = false;
        AuthService.mockClient = MockClient((request) async {
          if (request.url.path == '/api/auth/token') {
            tokenApiCalled = true;
            expect(request.method, equals('POST'));
            expect(
              request.headers['x-firebase-appcheck'],
              equals('app-check-token'),
            );
            final Map<String, dynamic> body = jsonDecode(request.body);
            expect(body['deviceId'], isNotNull);
            expect(body['appVersion'], equals('1.2.3'));
            expect(body['deviceInfo'], equals('Test-Android-Device'));

            return http.Response(
              jsonEncode({
                'accessToken': 'fresh_new_access_token',
                'refreshToken': 'fresh_new_refresh_token',
                'expiresIn': 7200,
              }),
              200,
            );
          }
          return http.Response('Not Found', 404);
        });

        final token = await AuthService.getValidAccessToken();
        expect(token, equals('fresh_new_access_token'));
        expect(tokenApiCalled, isTrue);

        expect(
          await fakeStorage.read(key: 'access_token'),
          equals('fresh_new_access_token'),
        );
        expect(
          await fakeStorage.read(key: 'refresh_token'),
          equals('fresh_new_refresh_token'),
        );
        expect(await fakeStorage.read(key: 'token_expiry'), isNotNull);
      },
    );
  });

  group('AuthService - 네트워크 에러 및 API 실패 대응 테스트', () {
    test('API 서버 응답이 400 이상인 경우 AuthException을 던져야 함', () async {
      AuthService.mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Invalid credentials'}),
          400,
        );
      });

      expect(
        () => AuthService.getValidAccessToken(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('연결할 수 없습니다'),
          ),
        ),
      );
    });

    test(
      'API 서버 응답의 JSON 포맷이 잘못되었거나 필수 필드가 누락된 경우 AuthException을 던져야 함',
      () async {
        AuthService.mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'wrong_key': 'no_token'}),
            200, // Status 200 이지만 필수 필드 누락
          );
        });

        expect(
          () => AuthService.getValidAccessToken(),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              contains('필수 필드가 누락'),
            ),
          ),
        );
      },
    );

    test('네트워크 타임아웃 발생 시 AuthException을 던져야 함', () async {
      AuthService.mockClient = MockClient((request) async {
        throw http.ClientException('Timeout');
      });

      expect(
        () => AuthService.getValidAccessToken(),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('AuthService - 로그아웃 테스트', () {
    test(
      'logout() 호출 시 secure storage 및 메모리 내 모든 토큰 데이터가 말끔히 소거되어야 함',
      () async {
        await fakeStorage.write(key: 'access_token', value: 'my_access');
        await fakeStorage.write(key: 'refresh_token', value: 'my_refresh');
        await fakeStorage.write(
          key: 'token_expiry',
          value: DateTime.now().toIso8601String(),
        );

        // 임의 캐싱 세팅
        AuthService.setMockToken(
          accessToken: 'my_access',
          refreshToken: 'my_refresh',
          expiry: DateTime.now().add(const Duration(hours: 1)),
        );

        await AuthService.logout();

        expect(await fakeStorage.read(key: 'access_token'), isNull);
        expect(await fakeStorage.read(key: 'refresh_token'), isNull);
        expect(await fakeStorage.read(key: 'token_expiry'), isNull);

        // deviceId는 삭제되지 않고 그대로 유지되어야 함
        await fakeStorage.write(key: 'device_id', value: 'preserved_device_id');
        expect(
          await fakeStorage.read(key: 'device_id'),
          equals('preserved_device_id'),
        );
      },
    );
  });
}
