import 'package:firebase_app_check_platform_interface/firebase_app_check_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/services/app_attestation_service.dart';

class FakeAppCheckPlatform extends FirebaseAppCheckPlatform {
  int activateCalls = 0;
  bool? autoRefreshEnabled;
  String? token = 'verified-token';
  Object? tokenError;
  AndroidAppCheckProvider? androidProvider;
  AppleAppCheckProvider? appleProvider;

  @override
  FirebaseAppCheckPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAppCheckPlatform setInitialValues() => this;

  @override
  Future<void> activate({
    WebProvider? webProvider,
    AndroidProvider? androidProvider,
    AppleProvider? appleProvider,
    AndroidAppCheckProvider? providerAndroid,
    AppleAppCheckProvider? providerApple,
    WindowsAppCheckProvider? providerWindows,
  }) async {
    activateCalls += 1;
    this.androidProvider = providerAndroid;
    this.appleProvider = providerApple;
  }

  @override
  Future<void> setTokenAutoRefreshEnabled(bool enabled) async {
    autoRefreshEnabled = enabled;
  }

  @override
  Future<String?> getToken(bool forceRefresh) async {
    if (tokenError case final error?) throw error;
    return token;
  }
}

void main() {
  late FakeAppCheckPlatform fakePlatform;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    fakePlatform = FakeAppCheckPlatform();
    FirebaseAppCheckPlatform.instance = fakePlatform;
  });

  test('초기화 전에는 App Check 토큰을 반환하지 않는다', () async {
    expect(await AppAttestationService.getToken(), isNull);
  });

  test('디버그 빌드는 플랫폼 증명 없이 무결성 검사를 통과한다', () async {
    expect(await AppAttestationService.verifyIntegrity(), isTrue);
  });

  test('App Check를 한 번만 초기화하고 디버그 provider를 선택한다', () async {
    await AppAttestationService.initialize();
    await AppAttestationService.initialize();

    expect(fakePlatform.activateCalls, 1);
    expect(fakePlatform.autoRefreshEnabled, isTrue);
    expect(fakePlatform.androidProvider, isA<AndroidDebugProvider>());
    expect(fakePlatform.appleProvider, isA<AppleDebugProvider>());
  });

  test('초기화 후 플랫폼 App Check 토큰을 반환한다', () async {
    expect(await AppAttestationService.getToken(), 'verified-token');
  });

  test('플랫폼 토큰 오류는 호출자에게 노출하지 않고 null을 반환한다', () async {
    fakePlatform.tokenError = StateError('native token failure');

    expect(await AppAttestationService.getToken(), isNull);
  });
}
