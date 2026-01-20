// lib/utils/network_utils.dart
import 'dart:io';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class NetworkUtils {
  static Future<bool> checkInternetConnectivity() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        return false; // No network interface
      }

      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true; // Internet is accessible
      }
      return false;
    } on TimeoutException catch (_) {
      return false; // Lookup timed out
    } on SocketException catch (_) {
      return false; // No internet access
    } catch (e) {
      debugPrint('Error checking internet connectivity: $e');
      return false;
    }
  }
}
