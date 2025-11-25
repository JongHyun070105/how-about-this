import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// dotenv는 더 이상 사용하지 않음 (API 키가 서버로 이전됨)
import 'package:device_info_plus/device_info_plus.dart';

import 'package:flutter/material.dart';
import 'package:review_ai/widgets/common/app_dialogs.dart';
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
    // Return false (not using test ads) if in release mode on either Android or iOS.
    return !(kReleaseMode && (Platform.isAndroid || Platform.isIOS));
  }

  static void logAdConfiguration() {
    if (shouldLogDetailed) {
      debugPrint('=== 광고 설정 상태 ===');
      debugPrint('테스트 모드: 활성');
      debugPrint('리워드 광고 ID: $rewardedAdUnitId');
      debugPrint('배너 광고 ID: $bannerAdUnitId');
      debugPrint('==================');
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
  static Future<bool> verifyAppIntegrity() async => true; // Simplified for now
  static bool detectDebugger() => kDebugMode || kProfileMode;

  /// 직접 구현한 루팅/탈옥 탐지
  static Future<bool> detectRootingOrJailbreak() async {
    // 디버그 모드에서만 비활성화 (테스트 편의성)
    if (kDebugMode) {
      debugPrint(
        'SECURITY WARNING: Jailbreak detection is disabled in debug mode.',
      );
      return false;
    }

    // 프로덕션/릴리즈 모드에서는 활성화
    try {
      if (Platform.isAndroid) {
        return await _checkAndroidRoot();
      } else if (Platform.isIOS) {
        return await _checkIOSJailbreak();
      }
      return false;
    } catch (e) {
      debugPrint('Jailbreak detection error: $e');
      return false;
    }
  }

  /// Android 루팅 감지
  static Future<bool> _checkAndroidRoot() async {
    return false;
  }

  /// iOS 탈옥 감지
  static Future<bool> _checkIOSJailbreak() async {
    return false;
  }

  static Future<bool> detectEmulator() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;

        // 물리적 기기 여부 체크
        if (!androidInfo.isPhysicalDevice) {
          return true;
        }

        // 에뮬레이터 특성 체크
        final model = androidInfo.model.toLowerCase();
        final brand = androidInfo.brand.toLowerCase();
        final device = androidInfo.device.toLowerCase();
        final product = androidInfo.product.toLowerCase();
        final hardware = androidInfo.hardware.toLowerCase();

        const emulatorIndicators = [
          // 일반적인 에뮬레이터
          'sdk', 'emulator', 'simulator', 'genymotion', 'bluestacks',
          // Android Studio 에뮬레이터
          'android sdk built for x86', 'google_sdk', 'droid4x', 'andy',
          // 기타 에뮬레이터들
          'vbox86', 'ttvm', 'nox', 'ldplayer', 'memu',
        ];

        final deviceStrings = [model, brand, device, product, hardware];

        for (String deviceString in deviceStrings) {
          for (String indicator in emulatorIndicators) {
            if (deviceString.contains(indicator)) {
              debugPrint(
                'Emulator detected: $deviceString contains $indicator',
              );
              return true;
            }
          }
        }

        return false;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return !iosInfo.isPhysicalDevice;
      }
      return false;
    } catch (e) {
      debugPrint('Emulator detection error: $e');
      return false;
    }
  }
}

class SecurityInitializer {
  SecurityInitializer._();

  static Future<void> initialize() async {
    // API 키는 이제 서버에서 관리되므로 초기화 로직 제거
    debugPrint('SecurityConfig initialized - API key managed on server');
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
      showAppDialog(
        context,
        title: '보안 경고',
        message: message,
        isError: true,
        cancelButtonText: '앱 종료',
        onConfirm: () => SystemNavigator.pop(), // This will close the app
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
