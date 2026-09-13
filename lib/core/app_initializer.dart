import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:review_ai/services/crash_reporting_service.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:review_ai/core/utils/logger_service.dart';

import '../firebase_options.dart';
import 'package:review_ai/config/security_config.dart';
import 'package:review_ai/services/auth_service.dart';
import 'package:review_ai/services/app_attestation_service.dart';
import 'package:review_ai/services/config_service.dart';
import 'package:review_ai/services/remote_config_service.dart';
import 'package:review_ai/services/server_time_service.dart';
import 'package:review_ai/services/notification_service.dart';

class AppInitializer {
  static Future<void> initializePreRun() async {
    WidgetsFlutterBinding.ensureInitialized();
    await _configureSystemUI();
  }

  static Future<void> initializePostRun() async {
    // 가장 먼저 서버 설정 및 Firebase 키 로드 (Firebase 초기화에 필수)
    await ConfigService.getAdMobConfig(); // 캐시/서버로부터 설정 미리 가져오기
    await DefaultFirebaseOptions.loadServerKeys();

    // Firebase 초기화
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 정식 빌드는 Play Integrity/App Attest, 디버그 빌드는 Firebase Debug
    // provider를 사용합니다. 서버 강제 전환 전에는 실패를 기록하고 진행합니다.
    await AppAttestationService.initialize().catchError((error, stack) {
      LoggerService.e('App attestation initialization failed', error, stack);
    });

    // Crash Reporting 시스템 초기화 (내부적으로 Crashlytics 설정)
    await CrashReportingService().initialize();

    // Flutter 프레임워크 에러
    FlutterError.onError = (errorDetails) {
      CrashReportingService().recordError(
        errorDetails.exception,
        errorDetails.stack,
        fatal: true,
      );
    };

    // 잡히지 않은 비동기 에러
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashReportingService().recordError(error, stack, fatal: true);
      return true;
    };

    // Firebase Performance & Analytics
    await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);

    // 필수 서비스 초기화 (UI 비차단) - 각 서비스별 에러 캡처로 부분 실패 허용
    await Future.wait([
      SecurityInitializer.initialize().catchError((e) {
        LoggerService.e('SecurityInitializer failed: $e');
      }),
      MobileAds.instance.initialize().catchError((e) {
        LoggerService.e('MobileAds initialization failed: $e');
        return InitializationStatus({});
      }),
      AuthService.initialize().catchError((e) {
        LoggerService.e('AuthService initialization failed: $e');
      }),
      RemoteConfigService().initialize().catchError((e) {
        LoggerService.e('RemoteConfigService initialization failed: $e');
      }),
      ServerTimeService.initialize().catchError((e) {
        LoggerService.e('ServerTimeService initialization failed: $e');
      }),
      NotificationService().initialize().catchError((e) {
        LoggerService.e('NotificationService initialization failed: $e');
      }),
    ]);

    SecurityConfig.logAdConfiguration();
  }

  static Future<void> _configureSystemUI() async {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
}
