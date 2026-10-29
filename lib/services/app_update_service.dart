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

  /// SemVer 우선순위에 따라 두 버전을 비교합니다.
  /// version1이 version2보다 높으면 true를 반환합니다.
  bool isVersionGreater(String version1, String version2) {
    final versionPattern = RegExp(
      r'^[vV]?(\d+(?:\.\d+)*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
    );
    final first = versionPattern.firstMatch(version1.trim());
    final second = versionPattern.firstMatch(version2.trim());
    if (first == null || second == null) return false;

    final firstCore = first
        .group(1)!
        .split('.')
        .map((part) => BigInt.parse(part))
        .toList();
    final secondCore = second
        .group(1)!
        .split('.')
        .map((part) => BigInt.parse(part))
        .toList();

    final coreLength = firstCore.length > secondCore.length
        ? firstCore.length
        : secondCore.length;
    for (var i = 0; i < coreLength; i++) {
      final firstPart = i < firstCore.length ? firstCore[i] : BigInt.zero;
      final secondPart = i < secondCore.length ? secondCore[i] : BigInt.zero;
      if (firstPart != secondPart) return firstPart > secondPart;
    }

    final firstPreRelease = first.group(2)?.split('.');
    final secondPreRelease = second.group(2)?.split('.');
    if (firstPreRelease == null) return secondPreRelease != null;
    if (secondPreRelease == null) return false;

    final sharedLength = firstPreRelease.length < secondPreRelease.length
        ? firstPreRelease.length
        : secondPreRelease.length;
    final numericIdentifier = RegExp(r'^\d+$');
    for (var i = 0; i < sharedLength; i++) {
      final firstIdentifier = firstPreRelease[i];
      final secondIdentifier = secondPreRelease[i];
      final firstIsNumeric = numericIdentifier.hasMatch(firstIdentifier);
      final secondIsNumeric = numericIdentifier.hasMatch(secondIdentifier);

      if (firstIsNumeric && secondIsNumeric) {
        final comparison = BigInt.parse(
          firstIdentifier,
        ).compareTo(BigInt.parse(secondIdentifier));
        if (comparison != 0) return comparison > 0;
      } else if (firstIsNumeric != secondIsNumeric) {
        return !firstIsNumeric;
      } else {
        final comparison = firstIdentifier.compareTo(secondIdentifier);
        if (comparison != 0) return comparison > 0;
      }
    }

    return firstPreRelease.length > secondPreRelease.length;
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
