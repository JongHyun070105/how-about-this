import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:review_ai/services/ai_food_insight_service.dart';
import 'package:review_ai/services/food_insight_service.dart';
import 'package:review_ai/presentation/providers/review_provider.dart';
import 'package:review_ai/presentation/widgets/history/food_insight_card_components.dart';

/// 식습관 인사이트 카드 위젯
///
/// 사용자의 식습관 요약 정보를 모노톤 UI로 표시합니다.
/// AI 인사이트를 비동기로 불러와 자연스러운 메시지를 표시합니다.
class FoodInsightCard extends StatefulWidget {
  final List<ReviewHistoryEntry> history;

  const FoodInsightCard({super.key, required this.history});

  @override
  State<FoodInsightCard> createState() => _FoodInsightCardState();
}

class _FoodInsightCardState extends State<FoodInsightCard> {
  AiInsightResult? _aiInsight;
  bool _isLoadingAi = true;

  @override
  void initState() {
    super.initState();
    _loadAiInsight();
  }

  @override
  void didUpdateWidget(covariant FoodInsightCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newSummary = _summaryKey(widget.history);
    final oldSummary = _summaryKey(oldWidget.history);
    if (newSummary != oldSummary) {
      _loadAiInsight();
    }
  }

  String _summaryKey(List<ReviewHistoryEntry> history) {
    final summary = FoodInsightService.generateSummary(history);
    summary.remove('insightMessage');
    return jsonEncode(summary);
  }

  Future<void> _loadAiInsight() async {
    if (widget.history.isEmpty) return;

    setState(() => _isLoadingAi = true);

    try {
      final result = await AiFoodInsightService().getInsight(widget.history);
      if (mounted) {
        setState(() {
          _aiInsight = result;
          _isLoadingAi = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _aiInsight = AiInsightResult(
            message: FoodInsightService.generateInsightMessage(widget.history),
            isAi: false,
          );
          _isLoadingAi = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.history.isEmpty) {
      return const EmptyInsightCard();
    }

    final summary = FoodInsightService.generateSummary(widget.history);
    final categoryFrequency = summary['categoryFrequency'] as Map<String, int>;
    final topFoods = summary['topFoods'] as List<Map<String, dynamic>>;
    final totalReviews = summary['totalReviews'] as int;
    final weeklyCount = summary['weeklyCount'] as int;

    // 로컬 폴백 메시지 (AI 로딩 전 또는 실패 시 사용)
    final String insightMessage = _isLoadingAi
        ? '식습관을 분석하고 있어요...'
        : (_aiInsight?.message ??
              (summary['insightMessage'] as String?) ??
              '식기록을 분석 중입니다.');
    final bool isAi = _aiInsight?.isAi ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InsightHeader(isAi: isAi && !_isLoadingAi),
          const SizedBox(height: 10),
          InsightMessage(message: insightMessage, isLoading: _isLoadingAi),
          const SizedBox(height: 10),
          StatBadgeRow(
            totalReviews: totalReviews,
            weeklyCount: weeklyCount,
            categoryFrequency: categoryFrequency,
          ),
          if (topFoods.isNotEmpty && topFoods.first['count'] as int >= 2) ...[
            const SizedBox(height: 10),
            FrequentFoodChips(topFoods: topFoods),
          ],
        ],
      ),
    );
  }
}
