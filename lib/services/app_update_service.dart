import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

class AppUpdateService {
  static const String _updateUrl =
      'https://gist.github.com/JongHyun070105/ba8200acae9b3375efe284ce43b0e519/raw/467c41ced067c0ccd2ec32a7e0a27aa40c4ff1ae/latest_version.json';

  /// Check if a new version of the app is available.
  /// Returns the latest version string if an update is available, otherwise null.
  Future<String?> isUpdateAvailable() async {
    try {
      // 1. Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // 2. Fetch latest version from the server (with timeout)
      final response = await http
          .get(Uri.parse(_updateUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final latestVersion = jsonResponse['latest_version'] as String?;

        if (latestVersion == null) {
          return null; // Could not parse latest version
        }

        // 3. Compare versions
        if (_isVersionGreater(latestVersion, currentVersion)) {
          return latestVersion;
        }
      } else {
        // Failed to fetch update info
        debugPrint('Failed to fetch update info: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error checking for update: $e');
    }
    return null;
  }

  /// Compares two version strings (e.g., "1.0.2" > "1.0.1").
  /// Returns true if version1 is greater than version2.
  bool _isVersionGreater(String version1, String version2) {
    final v1 = version1.split('.').map(int.parse).toList();
    final v2 = version2.split('.').map(int.parse).toList();

    final len = v1.length > v2.length ? v1.length : v2.length;

    for (int i = 0; i < len; i++) {
      final num1 = i < v1.length ? v1[i] : 0;
      final num2 = i < v2.length ? v2[i] : 0;

      if (num1 > num2) return true;
      if (num1 < num2) return false;
    }

    return false; // Versions are equal
  }
}
