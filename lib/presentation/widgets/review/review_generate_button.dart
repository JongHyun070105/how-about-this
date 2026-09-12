import 'package:flutter/material.dart';
import 'package:review_ai/presentation/widgets/common/primary_action_button.dart';

/// 리뷰 생성 버튼 위젯
class ReviewGenerateButton extends StatelessWidget {
  final bool isValid;
  final bool isLoading;
  final VoidCallback? onPressed;

  const ReviewGenerateButton({
    super.key,
    required this.isValid,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        gradient: isValid
            ? LinearGradient(
                colors: [Colors.blue[600]!, Colors.blue[700]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isValid ? null : Theme.of(context).disabledColor,
      ),
      child: Semantics(
        label: '입력한 정보를 바탕으로 AI 리뷰 생성하기',
        button: true,
        child: PrimaryActionButton(
          text: '리뷰 생성하기',
          isEnabled: isValid && !isLoading,
          onPressed: onPressed,
          isLoading: false,
        ),
      ),
    );
  }
}
