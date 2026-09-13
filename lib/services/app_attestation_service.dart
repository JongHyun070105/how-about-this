import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:review_ai/core/utils/logger_service.dart';

/// Firebase App Check를 통해 앱/기기 무결성 증명을 관리합니다.
class AppAttestationService {
  AppAttestationService._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    await FirebaseAppCheck.instance.activate(
      providerAndroid: kReleaseMode
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
      providerApple: kReleaseMode
          ? const AppleAppAttestWithDeviceCheckFallbackProvider()
          : const AppleDebugProvider(),
    );
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
    _initialized = true;
  }

  static Future<String?> getToken() async {
    if (!_initialized) return null;
    try {
      return await FirebaseAppCheck.instance.getToken();
    } catch (error, stack) {
      LoggerService.e('App attestation token unavailable', error, stack);
      return null;
    }
  }

  static Future<bool> verifyIntegrity() async {
    if (kDebugMode) return true;
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
