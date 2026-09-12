import 'dart:async';
import 'package:flutter/material.dart';
import 'package:review_ai/data/models/food_recommendation.dart';
import 'package:review_ai/presentation/screens/restaurant_search_screen.dart';
import 'package:review_ai/services/user_preference_service.dart';

/// 음식 추천 다이얼로그 — 좋아요/다른걸로/근처음식점 버튼
class RecommendationDialogButtons extends StatelessWidget {
  final FoodRecommendation recommended;
  final String category;

  const RecommendationDialogButtons({
    super.key,
    required this.recommended,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _dialogButton(
                context: context,
                icon: Icons.thumb_up,
                label: '좋아요!',
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.green.shade700
                    : Colors.green.shade400,
                sw: sw,
                sh: sh,
                onPressed: () => _onLikedAndSearch(context),
              ),
            ),
            SizedBox(width: sw * 0.02),
            Expanded(
              child: _dialogButton(
                context: context,
                icon: Icons.thumb_down,
                label: '다른 걸로',
                color: Theme.of(context).disabledColor,
                sw: sw,
                sh: sh,
                onPressed: () async {
                  await UserPreferenceService.recordFoodSelection(
                    foodName: recommended.name,
                    category: category,
                    liked: false,
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pop(true);
                },
              ),
            ),
          ],
        ),
        SizedBox(height: sh * 0.015),
      ],
    );
  }

  Future<void> _onLikedAndSearch(BuildContext context) async {
    await UserPreferenceService.recordFoodSelection(
      foodName: recommended.name,
      category: category,
      liked: true,
    );
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    navigator.pop('search');
    unawaited(
      navigator.push(
        MaterialPageRoute(
          builder: (_) => RestaurantSearchScreen(
            foodName: recommended.name,
            category: category,
          ),
        ),
      ),
    );
  }

  Widget _dialogButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    Color? foreground,
    required double sw,
    required double sh,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: sw * 0.04),
      label: Text(label, style: const TextStyle(fontFamily: 'Do Hyeon')),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: foreground ?? Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: sw * 0.02,
          vertical: sh * 0.015,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(sw * 0.025),
        ),
      ),
    );
  }
}

/// 룰렛 텍스트 디스플레이 위젯
class RouletteDisplay extends StatelessWidget {
  final Color color;
  final String displayText;
  final bool isSpinning;
  final Animation<double> scaleAnimation;

  const RouletteDisplay({
    super.key,
    required this.color,
    required this.displayText,
    required this.isSpinning,
    required this.scaleAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;
    final textColor = HSLColor.fromColor(color).withLightness(0.25).toColor();

    return Container(
      width: double.infinity,
      height: sh * 0.1875,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withAlpha((255 * 0.5).round())],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha((255 * 0.3).round()),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: AnimatedBuilder(
          animation: scaleAnimation,
          builder: (context, _) => Transform.scale(
            scale: isSpinning ? 1.0 : scaleAnimation.value,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 1500),
              child: Transform.scale(
                scale: isSpinning ? 1.0 : scaleAnimation.value,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    displayText,
                    style: TextStyle(
                      fontFamily: 'Do Hyeon',
                      fontSize: isSpinning
                          ? sw * 0.06
                          : (displayText.length > 15 ? sw * 0.065 : sw * 0.08),
                      fontWeight: FontWeight.bold,
                      color: isSpinning
                          ? Theme.of(context).disabledColor
                          : textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 추천 이유 텍스트
class RecommendationReason extends StatelessWidget {
  final String reason;

  const RecommendationReason({super.key, required this.reason});

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;

    return SizedBox(
      height: sw * 0.15,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: sw * 0.02),
          child: Text(
            reason,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Do Hyeon',
              fontSize: sw * 0.04,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ),
    );
  }
}
