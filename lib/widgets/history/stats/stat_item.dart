import 'package:flutter/material.dart';

/// 통계 항목 위젯
class StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  const StatItem({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 768;
    final iconSize = (screenWidth * (isTablet ? 0.032 : 0.05)).clamp(
      18.0,
      32.0,
    );
    final labelFontSize = (screenWidth * (isTablet ? 0.018 : 0.032)).clamp(
      12.0,
      18.0,
    );
    final valueFontSize = (screenWidth * (isTablet ? 0.024 : 0.042)).clamp(
      16.0,
      24.0,
    );

    return Container(
      padding: EdgeInsets.all(screenWidth * 0.03),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(screenWidth * 0.02),
            decoration: BoxDecoration(
              color: (iconColor ?? Theme.of(context).primaryColor).withAlpha(
                (255 * 0.1).round(),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: iconColor ?? Theme.of(context).primaryColor,
            ),
          ),
          SizedBox(width: screenWidth * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'SCDream',
                    fontSize: labelFontSize,
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(height: screenWidth * 0.005),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Do Hyeon',
                    fontSize: valueFontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
