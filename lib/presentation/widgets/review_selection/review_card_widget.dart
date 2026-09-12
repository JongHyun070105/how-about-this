import 'package:flutter/material.dart';
import 'package:review_ai/utils/responsive.dart';

/// 리뷰 선택 화면 - 개선된 레이아웃의 리뷰 카드 위젯
class ReviewCardWidget extends StatelessWidget {
  final String review;
  final bool isSelected;
  final Responsive responsive;
  final TextTheme textTheme;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const ReviewCardWidget({
    super.key,
    required this.review,
    required this.isSelected,
    required this.responsive,
    required this.textTheme,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const activeColor = Color(0xFF2563EB);

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark ? const Color(0xFF1E2638) : const Color(0xFFF6FAFF))
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(responsive.isTablet ? 16.0 : 12.0),
        border: Border.all(
          color: isSelected
              ? activeColor
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
          width: isSelected ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? activeColor.withAlpha((0.15 * 255).round())
                : Colors.black.withAlpha((0.05 * 255).round()),
            blurRadius: isSelected ? 12.0 : 4.0,
            offset: Offset(0, isSelected ? 4.0 : 2.0),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(context, isDark, activeColor),
          _buildContentArea(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, Color activeColor) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.horizontalPadding() * 0.6,
        vertical: responsive.verticalSpacing() * 0.45,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark ? const Color(0xFF23304A) : const Color(0xFFEBF3FE))
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(responsive.isTablet ? 16.0 : 12.0),
          topRight: Radius.circular(responsive.isTablet ? 16.0 : 12.0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'AI 생성 리뷰',
            style: textTheme.bodySmall?.copyWith(
              color: isSelected ? activeColor : Colors.grey.shade600,
              fontFamily: 'Do Hyeon',
              fontSize: responsive.captionFontSize(),
              fontWeight: FontWeight.w600,
            ),
          ),
          _buildEditButton(context),
        ],
      ),
    );
  }

  Widget _buildEditButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(responsive.isTablet ? 8.0 : 6.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha((0.2 * 255).round()),
            blurRadius: 2.0,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(responsive.isTablet ? 8.0 : 6.0),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(responsive.isTablet ? 8.0 : 6.0),
          child: Padding(
            padding: EdgeInsets.all(responsive.isTablet ? 8.0 : 6.0),
            child: Icon(
              Icons.edit,
              size: responsive.iconSize() * 0.7,
              color: Theme.of(context).iconTheme.color ?? Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentArea(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(responsive.isTablet ? 16.0 : 12.0),
            bottomRight: Radius.circular(responsive.isTablet ? 16.0 : 12.0),
          ),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(responsive.horizontalPadding() * 0.6),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Text(
                review,
                style: textTheme.bodyMedium?.copyWith(
                  fontFamily: 'Do Hyeon',
                  fontSize: responsive.bodyFontSize(),
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                  height: 1.5,
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
