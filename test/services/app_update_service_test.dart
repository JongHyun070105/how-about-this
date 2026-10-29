import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:review_ai/services/app_update_service.dart';

// InAppUpdate 정보를 모킹하기 위한 가짜 AppUpdateInfo 클래스
class FakeAppUpdateInfo implements AppUpdateInfo {
  @override
  final UpdateAvailability updateAvailability;
  @override
  final int availableVersionCode;
  @override
  final bool immediateUpdateAllowed;
  @override
  final bool flexibleUpdateAllowed;
  @override
  final int clientVersionStalenessDays;
  @override
  final InstallStatus installStatus;

  FakeAppUpdateInfo({
    required this.updateAvailability,
    this.availableVersionCode = 0,
    this.immediateUpdateAllowed = false,
    this.flexibleUpdateAllowed = false,
    this.clientVersionStalenessDays = 0,
    this.installStatus = InstallStatus.unknown,
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(() {
    AppUpdateService.setMockCurrentVersion(null);
    AppUpdateService.setMockIsAndroid(null);
    AppUpdateService.mockCheckForUpdate = null;
    AppUpdateService.mockStartFlexibleUpdate = null;
    AppUpdateService.mockCompleteFlexibleUpdate = null;
  });

  group('AppUpdateService.isVersionGreater 테스트', () {
    final service = AppUpdateService();

    test('단순 메이저/마이너/패치 버전 비교 성공', () {
      expect(service.isVersionGreater('1.0.2', '1.0.1'), isTrue);
      expect(service.isVersionGreater('1.1.0', '1.0.9'), isTrue);
      expect(service.isVersionGreater('2.0.0', '1.9.9'), isTrue);
      expect(service.isVersionGreater('1.0.0', '1.0.0'), isFalse);
      expect(service.isVersionGreater('1.0.1', '1.0.2'), isFalse);
    });

    test('정식 버전은 같은 버전의 프리릴리스보다 우선한다', () {
      expect(service.isVersionGreater('1.0.2', '1.0.2-rc.1'), isTrue);
      expect(service.isVersionGreater('1.0.2-rc.1', '1.0.2'), isFalse);
    });

    test('프리릴리스 식별자를 숫자 순서와 이름 순서로 비교한다', () {
      expect(service.isVersionGreater('1.0.2-beta', '1.0.2-alpha'), isTrue);
      expect(service.isVersionGreater('1.0.2-rc.10', '1.0.2-rc.2'), isTrue);
    });

    test('빌드 메타데이터는 버전 우선순위를 바꾸지 않는다', () {
      expect(service.isVersionGreater('1.0.2+1', '1.0.2'), isFalse);
    });

    test('프리릴리스 태그가 있어도 상위 패치 버전은 더 높다', () {
      expect(service.isVersionGreater('1.0.2-beta', '1.0.1'), isTrue);
      expect(service.isVersionGreater('2.0.1-rc3', '2.0.0'), isTrue);
    });

    test('자릿수가 다른 버전 비교 성공', () {
      expect(service.isVersionGreater('1.0.0.1', '1.0.0'), isTrue);
      expect(service.isVersionGreater('1.0', '1.0.1'), isFalse);
    });
  });

  group('AppUpdateService.isUpdateAvailable 및 inAppUpdate 모킹 테스트', () {
    test('새 업데이트가 존재할 때 최신 버전 문자열 반환 검증', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({'latest_version': '1.1.0'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = AppUpdateService(client: mockClient);
      AppUpdateService.setMockCurrentVersion('1.0.0');

      final result = await service.isUpdateAvailable();
      expect(result, '1.1.0');
    });

    test('현재 버전이 최신 버전과 같거나 더 높을 때 null 반환 검증', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({'latest_version': '1.0.0'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = AppUpdateService(client: mockClient);
      AppUpdateService.setMockCurrentVersion('1.0.0');

      final result = await service.isUpdateAvailable();
      expect(result, isNull);
    });

    test('프리릴리스 앱은 정식 버전 업데이트를 안내한다', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({'latest_version': '1.0.2'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = AppUpdateService(client: mockClient);
      AppUpdateService.setMockCurrentVersion('1.0.2-rc.1');

      final result = await service.isUpdateAvailable();
      expect(result, '1.0.2');
    });

    test('정식 앱은 프리릴리스 manifest 버전을 업데이트로 안내하지 않는다', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({'latest_version': '1.0.2-rc.1'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = AppUpdateService(client: mockClient);
      AppUpdateService.setMockCurrentVersion('1.0.2');

      final result = await service.isUpdateAvailable();
      expect(result, isNull);
    });

    test('서버 에러(500) 발생 시 null 반환 및 안전 예외 처리 검증', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final service = AppUpdateService(client: mockClient);
      AppUpdateService.setMockCurrentVersion('1.0.0');

      final result = await service.isUpdateAvailable();
      expect(result, isNull);
    });

    test(
      'Android 플랫폼에서 인앱 업데이트가 없는 경우(updateAvailable 아님) 다운로드 안함 검증',
      () async {
        final service = AppUpdateService();
        AppUpdateService.setMockIsAndroid(true);

        bool startFlexibleCalled = false;
        bool completeFlexibleCalled = false;

        AppUpdateService.mockCheckForUpdate = () async {
          return FakeAppUpdateInfo(
            updateAvailability: UpdateAvailability.updateNotAvailable,
          );
        };
        AppUpdateService.mockStartFlexibleUpdate = () async {
          startFlexibleCalled = true;
          return AppUpdateResult.success;
        };
        AppUpdateService.mockCompleteFlexibleUpdate = () async {
          completeFlexibleCalled = true;
        };

        await service.checkForInAppUpdate();

        expect(startFlexibleCalled, isFalse);
        expect(completeFlexibleCalled, isFalse);
      },
    );

    test('Android 플랫폼에서 인앱 업데이트가 있을 경우 다운로드 및 설치 순차 실행 검증', () async {
      final service = AppUpdateService();
      AppUpdateService.setMockIsAndroid(true);

      bool startFlexibleCalled = false;
      bool completeFlexibleCalled = false;

      AppUpdateService.mockCheckForUpdate = () async {
        return FakeAppUpdateInfo(
          updateAvailability: UpdateAvailability.updateAvailable,
        );
      };
      AppUpdateService.mockStartFlexibleUpdate = () async {
        startFlexibleCalled = true;
        return AppUpdateResult.success;
      };
      AppUpdateService.mockCompleteFlexibleUpdate = () async {
        completeFlexibleCalled = true;
      };

      await service.checkForInAppUpdate();

      expect(startFlexibleCalled, isTrue);
      expect(completeFlexibleCalled, isTrue);
    });

    test('Android 플랫폼에서 인앱 업데이트 조회 중 예외 발생 시 에러 핸들링 검증', () async {
      final service = AppUpdateService();
      AppUpdateService.setMockIsAndroid(true);

      AppUpdateService.mockCheckForUpdate = () async {
        throw Exception('InAppUpdate service is not available');
      };

      // 예외 발생 시 에러를 받아 처리하고 안전하게 루프가 종료되어야 함
      await expectLater(service.checkForInAppUpdate(), completes);
    });
  });
}
