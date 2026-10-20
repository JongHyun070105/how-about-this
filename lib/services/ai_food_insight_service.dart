import 'dart:convert';
import 'package:review_ai/core/utils/logger_service.dart';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:review_ai/config/api_config.dart';
import 'package:review_ai/presentation/providers/review_provider.dart';
import 'package:review_ai/services/auth_service.dart';
import 'package:review_ai/services/food_insight_service.dart';

/// Cloudflare Workers + Gemini API 기반 AI 식습관 인사이트 서비스
///
/// 서버에서 AI가 생성한 자연스러운 인사이트 메시지를 가져옵니다.
/// 실패 시 로컬 [FoodInsightService]로 자동 폴백합니다.
class AiFoodInsightService {
  static final AiFoodInsightService _instance =
      AiFoodInsightService._internal();
  factory AiFoodInsightService() => _instance;
  AiFoodInsightService._internal();

  http.Client? _innerClient;
  http.Client? _customClient;

  @visibleForTesting
  void setClientForTesting(http.Client? client) {
    _customClient = client;
  }

  http.Client get _client {
    if (_customClient != null) {
      return _customClient!;
    }
    _innerClient ??= http.Client();
    return _innerClient!;
  }

  // 상수 정의
  static const List<int> _cacheTimePoints = [8, 12, 19];
  static const Duration _httpTimeout = Duration(seconds: 10);

  /// 마지막 AI 인사이트 캐시 (앱 내 메모리 캐시)
  String? _cachedInsight;
  DateTime? _cachedAt;
  String? _cachedSummaryKey;

  /// AI 인사이트 가져오기
  ///
  /// 서버 호출 실패 시 로컬 템플릿 기반 메시지로 폴백합니다.
  /// [forceRefresh]가 true이면 캐시를 무시하고 새로 요청합니다.
  Future<AiInsightResult> getInsight(
    List<ReviewHistoryEntry> history, {
    bool forceRefresh = false,
  }) async {
    if (history.isEmpty) {
      return AiInsightResult(
        message: FoodInsightService.generateInsightMessage(history),
        isAi: false,
      );
    }

    final summary = FoodInsightService.generateSummary(history);
    // The local fallback message is random and does not affect the API input.
    final cacheSummary = Map<String, dynamic>.from(summary)
      ..remove('insightMessage');
    final summaryKey = jsonEncode(cacheSummary);

    // 캐시 만료 로직 (알림 시간대 8, 12, 19시 기준 및 자정 기준)
    if (!forceRefresh &&
        _cachedInsight != null &&
        _cachedAt != null &&
        _cachedSummaryKey == summaryKey) {
      if (!_isCacheExpiredByTimePoints(_cachedAt!)) {
        return AiInsightResult(message: _cachedInsight!, isAi: true);
      }
    }

    try {
      final insight = await _fetchAiInsight(summary);

      if (insight != null) {
        _cachedInsight = insight;
        _cachedAt = DateTime.now();
        _cachedSummaryKey = summaryKey;
        return AiInsightResult(message: insight, isAi: true);
      }
    } catch (e) {
      LoggerService.e('AI 인사이트 요청 실패, 로컬 폴백: $e');
    }

    // 폴백: 로컬 템플릿 기반 메시지
    return AiInsightResult(
      message: FoodInsightService.generateInsightMessage(history),
      isAi: false,
    );
  }

  /// 서버에서 AI 인사이트를 가져옴
  Future<String?> _fetchAiInsight(Map<String, dynamic> summary) async {
    final url = Uri.parse('${ApiConfig.proxyUrl}/api/food-insight');

    final accessToken = await AuthService.getValidAccessToken();

    // streak 데이터를 서버 형식에 맞게 변환
    final streak = summary['streak'] as Map<String, dynamic>?;

    final response = await _client
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            'categoryFrequency': summary['categoryFrequency'],
            'topFoods': summary['topFoods'],
            'totalReviews': summary['totalReviews'],
            'weeklyCount': summary['weeklyCount'],
            'streak': streak,
            'guidelines': {
              'tone': '정중한 존댓말(해요체)',
              'rules': [
                '**최우선 규칙**: 절대 반말을 사용하지 마세요. 무조건 정중하고 친근한 존댓말(~해요, ~이에요, ~했어요)만 사용해야 합니다.',
                '사용자를 "님" 또는 "사용자님"으로 부르거나 직접적인 호칭 없이 부드럽게 대화를 이어가세요.',
                '메시지 예시: "최근 한식을 자주 즐기셨네요! 건강한 식습관을 위해 오늘은 가벼운 샐러드는 어떠신가요? 🌱"',
                '비속어, 은어, 줄임말 절대 금지',
                '2~3문장 이내로 간결하고 따뜻하게 작성하세요.',
                '이모지는 문맥에 맞게 1~2개만 사용하세요.',
              ],
            },
          }),
        )
        .timeout(_httpTimeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final insight = data['insight'] as String?;

      if (insight != null && insight.isNotEmpty) {
        if (kDebugMode) {
          LoggerService.d('AI 인사이트 수신 (캐시: ${data['cached']}): $insight');
        }
        return insight;
      }
    }

    LoggerService.e('AI 인사이트 응답 실패: ${response.statusCode}');
    return null;
  }

  /// 알림 시간대(8, 12, 19시)를 기준으로 캐시 만료 여부 확인
  bool _isCacheExpiredByTimePoints(DateTime cachedAt) {
    final now = DateTime.now();

    // 날짜가 바뀐 경우(자정 이후) 무조건 캐시 만료
    if (cachedAt.year != now.year ||
        cachedAt.month != now.month ||
        cachedAt.day != now.day) {
      return true;
    }

    for (final hour in _cacheTimePoints) {
      final point = DateTime(now.year, now.month, now.day, hour);
      // 캐시된 시점이 특정 시간 포인트 이전이고, 현재가 그 포인트를 지났다면 만료
      if (cachedAt.isBefore(point) && now.isAfter(point)) {
        return true;
      }
    }
    return false;
  }

  /// 클라이언트 자원 해제
  void dispose() {
    _innerClient?.close();
    _innerClient = null;
  }
}

/// AI 인사이트 결과
class AiInsightResult {
  /// 인사이트 메시지
  final String message;

  /// AI가 생성한 메시지인지, 로컬 템플릿인지 여부
  final bool isAi;

  const AiInsightResult({required this.message, required this.isAi});
}
