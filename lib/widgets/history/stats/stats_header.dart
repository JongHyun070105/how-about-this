import 'package:flutter/material.dart';

/// 통계 다이얼로그 헤더 위젯
class StatsHeader extends StatelessWidget {
  final int currentPage;
  final int maxPages;
  final VoidCallback onClose;

  const StatsHeader({
    super.key,
    required this.currentPage,
    required this.maxPages,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 768;
    final headerFontSize = (screenWidth * (isTablet ? 0.028 : 0.045)).clamp(
      14.0,
      24.0,
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha((255 * 0.1).round()),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            currentPage == 0 ? '📊 사용 통계' : '📈 카테고리별 분석',
            style: TextStyle(
              fontFamily: 'Do Hyeon',
              fontSize: headerFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          Row(
            children: [
              ...List.generate(
                maxPages,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: currentPage == index
                        ? Theme.of(context).primaryColor
                        : Colors.grey[300],
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
