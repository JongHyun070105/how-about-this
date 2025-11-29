import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:review_ai/services/api_proxy_service.dart';
import 'package:review_ai/config/api_config.dart';

class ImageLabelingService {
  final ApiProxyService _apiProxyService;

  ImageLabelingService()
    : _apiProxyService = ApiProxyService(http.Client(), ApiConfig.proxyUrl);

  Future<List<String>> getLabels(File imageFile) async {
    try {
      final foodName = await _apiProxyService.analyzeFoodImage(imageFile);
      if (foodName == 'NOT_FOOD' || foodName == '음식 아님') {
        return [];
      }
      return [foodName];
    } catch (e) {
      debugPrint('Vision AI Error: $e');
      return [];
    }
  }

  void dispose() {
    // No resources to dispose for HTTP client in this simple service
  }
}
