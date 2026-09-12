import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:review_ai/core/utils/logger_service.dart';

class AppUpdateService {
  static const String _updateUrl =
      'https://gist.githubusercontent.com/JongHyun070105/ba8200acae9b3375efe284ce43b0e519/raw/latest_version.json';
  static const Duration _httpTimeout = Duration(seconds: 5);

  final http.Client _client;

  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  static String? _mockCurrentVersion;
  static bool? _mockIsAndroid;

  @visibleForTesting
  static void setMockCurrentVersion(String? version) {
    _mockCurrentVersion = version;
  }

  @visibleForTesting
  static void setMockIsAndroid(bool? isAndroid) {
    _mockIsAndroid = isAndroid;
  }

  @visibleForTesting
  static Future<AppUpdateInfo> Function()? mockCheckForUpdate;

  @visibleForTesting
  static Future<AppUpdateResult> Function()? mockStartFlexibleUpdate;

  @visibleForTesting
  static Future<void> Function()? mockCompleteFlexibleUpdate;

  /// 새 버전의 앱이 사용 가능한지 확인합니다.
  /// 업데이트가 사용 가능하면 최신 버전 문자열을 반환하고, 그렇지 않으면 null을 반환합니다.
  Future<String?> isUpdateAvailable() async {
    try {
      // 1. 현재 앱 버전 가져오기
      final String currentVersion;
      if (_mockCurrentVersion != null) {
        currentVersion = _mockCurrentVersion!;
      } else {
        final packageInfo = await PackageInfo.fromPlatform();
        currentVersion = packageInfo.version;
      }

      // 2. 서버에서 최신 버전 가져오기 (타임아웃 설정됨)
      final response = await _client
          .get(Uri.parse(_updateUrl))
          .timeout(_httpTimeout);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final latestVersion = jsonResponse['latest_version'] as String?;

        if (latestVersion == null) {
          return null; // 최신 버전을 파싱할 수 없음
        }

        // 3. Compare versions
        if (isVersionGreater(latestVersion, currentVersion)) {
          return latestVersion;
        }
      } else {
        // 업데이트 정보 가져오기 실패
        LoggerService.e('Failed to fetch update info: ${response.statusCode}');
      }
    } catch (e, stack) {
      LoggerService.e('Error checking for update: $e', e, stack);
    }
    return null;
  }

  /// 두 버전 문자열을 비교합니다 (예: "1.0.2-beta" > "1.0.1").
  /// version1이 version2보다 크면 true를 반환합니다.
  bool isVersionGreater(String version1, String version2) {
    int safeParsePart(String part) {
      final cleanDigits = part.replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(cleanDigits) ?? 0;
    }

    final v1 = version1
        .replaceAll('+', '.')
        .replaceAll('-', '.')
        .split('.')
        .map(safeParsePart)
        .toList();
    final v2 = version2
        .replaceAll('+', '.')
        .replaceAll('-', '.')
        .split('.')
        .map(safeParsePart)
        .toList();

    final len = v1.length > v2.length ? v1.length : v2.length;

    for (int i = 0; i < len; i++) {
      final part1 = i < v1.length ? v1[i] : 0;
      final part2 = i < v2.length ? v2[i] : 0;

      if (part1 > part2) return true;
      if (part1 < part2) return false;
    }

    return false; // 버전이 동일함
  }

  /// Android 플랫폼에서 인앱 업데이트를 확인하고, 가능하다면 다운로드를 시작(Flexible)합니다.
  Future<void> checkForInAppUpdate() async {
    final isAndroid = _mockIsAndroid ?? Platform.isAndroid;
    if (!isAndroid) return; // iOS는 미지원

    try {
      final updateInfo = mockCheckForUpdate != null
          ? await mockCheckForUpdate!()
          : await InAppUpdate.checkForUpdate();

      // 업데이트가 가능할 때 Flexible 다운로드 시작
      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        LoggerService.d(
          'AppUpdateService: Update available. Starting flexible update.',
        );
        if (mockStartFlexibleUpdate != null) {
          await mockStartFlexibleUpdate!();
        } else {
          await InAppUpdate.startFlexibleUpdate();
        }

        // 다운로드 완료 시 설치 유도
        if (mockCompleteFlexibleUpdate != null) {
          await mockCompleteFlexibleUpdate!();
        } else {
          await InAppUpdate.completeFlexibleUpdate();
        }
      } else {
        LoggerService.d('AppUpdateService: No in-app update available.');
      }
    } catch (e, stack) {
      LoggerService.e(
        'AppUpdateService: Error checking for in-app update: $e',
        e,
        stack,
      );
    }
  }
}
