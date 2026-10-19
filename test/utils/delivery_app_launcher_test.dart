import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/data/models/location_models.dart';
import 'package:review_ai/utils/delivery_app_launcher.dart';

void main() {
  // 테스트용 카카오 장소 데이터 객체 생성
  const mockRestaurant = KakaoPlace(
    id: '12345',
    placeName: '맛있는 파스타집',
    categoryName: '음식점 > 양식 > 이탈리아음식',
    phone: '02-123-4567',
    addressName: '서울 강남구 역삼동 123',
    roadAddressName: '서울 강남구 테헤란로 123',
    x: '127.0276197',
    y: '37.497942',
    placeUrl: 'http://place.map.kakao.com/12345',
    distance: '150',
  );

  tearDown(() {
    // 각 테스트 종료 후 정적 모크 리셋
    DeliveryAppLauncher.mockClipboardSetter = null;
    DeliveryAppLauncher.mockCanLaunchUrl = null;
    DeliveryAppLauncher.mockUrlLauncher = null;
  });

  group('DeliveryAppLauncher 카카오맵 실행 테스트', () {
    testWidgets('현재 위치가 존재할 때 카카오맵 길찾기 스키마 및 웹 URL 검증', (
      WidgetTester tester,
    ) async {
      Uri? capturedUri;
      Uri? capturedCanLaunchUri;

      DeliveryAppLauncher.mockCanLaunchUrl = (uri) async {
        capturedCanLaunchUri = uri;
        return true; // 앱 실행 가능
      };

      DeliveryAppLauncher.mockUrlLauncher = (uri, mode) async {
        capturedUri = uri;
        return true;
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => DeliveryAppLauncher.launch(
                    context,
                    mockRestaurant,
                    currentLat: 37.5665,
                    currentLng: 126.9780,
                    showDeliveryAppDialog: () async => 'kakao_map',
                  ),
                  child: const Text('실행'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // 검증
      expect(capturedCanLaunchUri, isNotNull);
      expect(capturedCanLaunchUri.toString(), contains('kakaomap://route'));
      expect(capturedCanLaunchUri.toString(), contains('sp=37.5665,126.978'));
      expect(
        capturedCanLaunchUri.toString(),
        contains('ep=37.497942,127.0276197'),
      );

      // 한글 인코딩 부분 검증
      expect(
        capturedCanLaunchUri.toString(),
        contains('sn=${Uri.encodeComponent("내 위치")}'),
      );
      expect(
        capturedCanLaunchUri.toString(),
        contains('en=${Uri.encodeComponent("맛있는 파스타집")}'),
      );
      expect(capturedUri, equals(capturedCanLaunchUri));
    });

    testWidgets('현재 위치가 없을 때 카카오맵 장소보기 스키마 및 웹 URL 실행 검증', (
      WidgetTester tester,
    ) async {
      Uri? capturedUri;
      Uri? capturedCanLaunchUri;

      DeliveryAppLauncher.mockCanLaunchUrl = (uri) async {
        capturedCanLaunchUri = uri;
        return false; // 앱 실행 불가능 -> 웹 브라우저로 런칭 시도
      };

      DeliveryAppLauncher.mockUrlLauncher = (uri, mode) async {
        capturedUri = uri;
        return true;
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => DeliveryAppLauncher.launch(
                    context,
                    mockRestaurant,
                    currentLat: null,
                    currentLng: null,
                    showDeliveryAppDialog: () async => 'kakao_map',
                  ),
                  child: const Text('실행'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // 앱 실행 불가 결과에 따라 웹 URL 실행 시도 검증
      expect(capturedCanLaunchUri.toString(), contains('kakaomap://look'));
      expect(capturedUri, isNotNull);
      expect(
        capturedUri.toString(),
        contains('https://map.kakao.com/link/map/'),
      );
      expect(capturedUri.toString(), contains(Uri.encodeComponent('맛있는 파스타집')));
    });
  });

  group('DeliveryAppLauncher 배달앱 실행 테스트', () {
    testWidgets('배민 선택 시 클립보드 복사 및 스키마 실행 시도 검증 (승인 시)', (
      WidgetTester tester,
    ) async {
      ClipboardData? copiedData;
      Uri? launchUri;
      bool canLaunchCalled = false;

      DeliveryAppLauncher.mockClipboardSetter = (data) {
        copiedData = data;
      };

      DeliveryAppLauncher.mockCanLaunchUrl = (uri) async {
        canLaunchCalled = true;
        expect(uri.toString(), equals('baemin://'));
        return true; // 배민 앱 설치됨
      };

      DeliveryAppLauncher.mockUrlLauncher = (uri, mode) async {
        launchUri = uri;
        return true;
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => DeliveryAppLauncher.launch(
                    context,
                    mockRestaurant,
                    currentLat: null,
                    currentLng: null,
                    showDeliveryAppDialog: () async => 'baemin',
                  ),
                  child: const Text('실행'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // 클립보드 복사 검증
      expect(copiedData, isNotNull);
      expect(copiedData!.text, equals('맛있는 파스타집'));

      // 다이얼로그 노출 확인
      expect(find.text('📋 복사 완료!'), findsOneWidget);
      expect(find.text('앱 열기'), findsOneWidget);

      // '앱 열기' 탭하여 계속 진행
      await tester.tap(find.text('앱 열기'));
      await tester.pumpAndSettle();

      // 스키마 런칭 검증
      expect(canLaunchCalled, isTrue);
      expect(launchUri.toString(), equals('baemin://'));
    });

    testWidgets('배달앱 실행 실패 시 스토어 오픈 유도 검증', (WidgetTester tester) async {
      Uri? storeLaunchUri;

      DeliveryAppLauncher.mockClipboardSetter = (data) {};

      DeliveryAppLauncher.mockCanLaunchUrl = (uri) async {
        return false; // 배민 앱 미설치
      };

      DeliveryAppLauncher.mockUrlLauncher = (uri, mode) async {
        storeLaunchUri = uri;
        return true;
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS), // iOS 환경 시뮬레이션
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => DeliveryAppLauncher.launch(
                    context,
                    mockRestaurant,
                    currentLat: null,
                    currentLng: null,
                    showDeliveryAppDialog: () async => 'baemin',
                  ),
                  child: const Text('실행'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // 1. 복사 완료 팝업
      await tester.tap(find.text('앱 열기'));
      await tester.pumpAndSettle();

      // 2. 앱 실행 불가에 따른 스토어 열기 팝업 검증 (iOS이므로 App Store)
      expect(find.text('배민 앱'), findsOneWidget);
      expect(find.textContaining('App Store에서 앱을 설치 또는 업데이트'), findsOneWidget);
      expect(find.text('App Store 열기'), findsOneWidget);

      // 스토어 열기 클릭
      await tester.tap(find.text('App Store 열기'));
      await tester.pumpAndSettle();

      // 스토어 URI 검증
      expect(storeLaunchUri, isNotNull);
      expect(storeLaunchUri.toString(), contains('apps.apple.com'));
      expect(
        storeLaunchUri.toString(),
        contains('378084485'),
      ); // 배민 iOS App Store ID
    });

    testWidgets('앱 실행 가능 조회 후 실제 실행이 실패하면 스토어 안내를 표시한다', (
      WidgetTester tester,
    ) async {
      DeliveryAppLauncher.mockClipboardSetter = (data) {};
      DeliveryAppLauncher.mockCanLaunchUrl = (uri) async => true;
      DeliveryAppLauncher.mockUrlLauncher = (uri, mode) async => false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => DeliveryAppLauncher.launch(
                  context,
                  mockRestaurant,
                  currentLat: null,
                  currentLng: null,
                  showDeliveryAppDialog: () async => 'baemin',
                ),
                child: const Text('실행'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('앱 열기'));
      await tester.pumpAndSettle();

      expect(find.text('배민 앱'), findsOneWidget);
    });
  });
}
