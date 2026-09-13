import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:review_ai/presentation/screens/security_block_screen.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:review_ai/core/utils/logger_service.dart';
import 'package:review_ai/services/app_attestation_service.dart';
// Added url_launcher import
import 'app_constants.dart';
import 'environment_config.dart';

/// 앱의 보안 설정을 관리하는 클래스
class SecurityConfig {
  SecurityConfig._();

  // Ad ID Management

  static const String _testRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _testBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  // iOS Production Ad Unit IDs
  static const String _prodRewardedAdUnitIdIOS =
      'ca-app-pub-6555743055922387/1329741925';
  static const String _prodBannerAdUnitIdIOS =
      'ca-app-pub-6555743055922387/7591365110';

  // Android Production Ad Unit IDs
  static const String _prodRewardedAdUnitIdAndroid =
      'ca-app-pub-6555743055922387/7073803440';
  static const String _prodBannerAdUnitIdAndroid =
      'ca-app-pub-6555743055922387/8087007370';

  static String get rewardedAdUnitId {
    if (kReleaseMode) {
      if (Platform.isAndroid) {
        return _prodRewardedAdUnitIdAndroid;
      } else if (Platform.isIOS) {
        return _prodRewardedAdUnitIdIOS;
      }
    }
    return _testRewardedAdUnitId;
  }

  static String get bannerAdUnitId {
    if (kReleaseMode) {
      if (Platform.isAndroid) {
        return _prodBannerAdUnitIdAndroid;
      } else if (Platform.isIOS) {
        return _prodBannerAdUnitIdIOS;
      }
    }
    return _testBannerAdUnitId;
  }

  static bool get isUsingTestAds {
    // Android 또는 iOS에서 릴리즈 모드이면 false 반환 (테스트 광고 사용 안 함).
    return !(kReleaseMode && (Platform.isAndroid || Platform.isIOS));
  }

  static void logAdConfiguration() {
    if (shouldLogDetailed) {
      LoggerService.d('=== 광고 설정 상태 ===');
      LoggerService.d('테스트 모드: 활성');
      LoggerService.d('리워드 광고 ID: $rewardedAdUnitId');
      LoggerService.d('배너 광고 ID: $bannerAdUnitId');
      LoggerService.d('==================');
    }
  }

  // API Key Management - 이제 서버에서 관리하므로 제거됨
  // API 키는 Cloudflare Workers 서버에서만 관리됩니다.

  // Logging & Error Handling (as before)
  static bool get shouldLogDetailed => EnvironmentConfig.enableVerboseLogging;
  static String sanitizeErrorMessage(String error) {
    return error
        .replaceAll(RegExp(AppConstants.apiKeyHiddenPattern), 'API_KEY_HIDDEN')
        .replaceAll(RegExp(AppConstants.tokenHiddenPattern), 'TOKEN_HIDDEN')
        .replaceAll(RegExp(AppConstants.pathHiddenPattern), 'PATH_HIDDEN/');
  }

  // App Integrity & Security Checks (as before)
  static Future<bool> verifyAppIntegrity() =>
      AppAttestationService.verifyIntegrity();
  static bool detectDebugger() => kDebugMode || kProfileMode;

  /// flutter_jailbreak_detection 패키지를 활용한 루팅/탈옥 탐지
  static Future<bool> detectRootingOrJailbreak() async {
    if (kDebugMode) {
      LoggerService.w(
        'SECURITY WARNING: Jailbreak detection is disabled in debug mode.',
      );
      return false;
    }

    try {
      return await FlutterJailbreakDetection.jailbroken;
    } catch (e) {
      LoggerService.e('Jailbreak detection error: $e');
      return false;
    }
  }

  static Future<bool> detectEmulator() async {
    if (!_canUsePlatformChannels) {
      LoggerService.d(
        'Emulator detection skipped: Flutter binding is not initialized.',
      );
      return false;
    }

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return !androidInfo.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return !iosInfo.isPhysicalDevice;
      }
      return false;
    } on MissingPluginException catch (e) {
      LoggerService.w('Emulator detection unavailable: ${e.message ?? e}');
      return false;
    } catch (e) {
      LoggerService.e('Emulator detection error: $e');
      return false;
    }
  }

  static bool get _canUsePlatformChannels {
    try {
      ServicesBinding.instance.defaultBinaryMessenger;
      return true;
    } on FlutterError {
      return false;
    }
  }
}

class SecurityInitializer {
  SecurityInitializer._();

  static Future<void> initialize() async {
    // API 키는 이제 서버에서 관리되므로 초기화 로직 제거
    LoggerService.i('SecurityConfig initialized - API key managed on server');
  }

  static Future<SecurityCheckResult> performRuntimeSecurityCheck() async {
    final result = SecurityCheckResult();
    try {
      result.isRootedOrJailbroken =
          await SecurityConfig.detectRootingOrJailbreak();
      result.isDebuggerAttached = SecurityConfig.detectDebugger();
      result.isAppIntegrityValid = await SecurityConfig.verifyAppIntegrity();
      result.isEmulator = await SecurityConfig.detectEmulator();
      result.isSecure = _calculateOverallSecurityStatus(result);
    } catch (e) {
      result.error = SecurityConfig.sanitizeErrorMessage(e.toString());
      result.isSecure = false;
    }
    return result;
  }

  static bool _calculateOverallSecurityStatus(SecurityCheckResult result) {
    if (EnvironmentConfig.isDevelopment) {
      return !result.isRootedOrJailbroken && result.isAppIntegrityValid;
    }
    return !result.isRootedOrJailbroken &&
        !result.isDebuggerAttached &&
        result.isAppIntegrityValid &&
        !result.isEmulator;
  }

  static Future<void> handleSecurityThreat(
    BuildContext context,
    SecurityCheckResult result,
  ) async {
    if (result.isSecure || !context.mounted) return;

    String message = '';
    if (result.isRootedOrJailbroken) {
      message = '보안상의 이유로 루팅 또는 탈옥된 기기에서는 앱을 사용할 수 없습니다.';
    } else if (!result.isAppIntegrityValid) {
      message = '앱이 위변조되었습니다. 공식 스토어에서 다시 다운로드해주세요.';
    } else if (result.isDebuggerAttached && !EnvironmentConfig.isDevelopment) {
      message = '디버거가 연결되어 있어 앱을 종료합니다.';
    } else if (result.isEmulator && !EnvironmentConfig.isDevelopment) {
      message = '에뮬레이터 환경에서는 앱을 실행할 수 없습니다.';
    }

    if (message.isNotEmpty) {
      unawaited(
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => SecurityBlockScreen(message: message),
          ),
          (Route<dynamic> route) => false,
        ),
      );
    }
  }
}

class SecurityCheckResult {
  bool isRootedOrJailbroken = false;
  bool isDebuggerAttached = false;
  bool isAppIntegrityValid = true;
  bool isEmulator = false;
  bool isSecure = true;
  String? error;
}
