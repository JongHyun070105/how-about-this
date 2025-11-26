import 'package:review_ai/widgets/common/app_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review_ai/providers/review_provider.dart';

class EditReviewDialog extends ConsumerStatefulWidget {
  final int index;
  final String currentReview;

  const EditReviewDialog({
    super.key,
    required this.index,
    required this.currentReview,
  });

  @override
  ConsumerState<EditReviewDialog> createState() => _EditReviewDialogState();
}

class _EditReviewDialogState extends ConsumerState<EditReviewDialog> {
  late final TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.currentReview);
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        '리뷰 수정',
        style: TextStyle(fontFamily: 'Do Hyeon', fontWeight: FontWeight.bold),
      ),
      content: Padding(
        padding: const EdgeInsets.only(top: 12.0),
        child: TextField(
          controller: _editController,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            hintText: '리뷰 내용을 수정해주세요',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).primaryColor,
                width: 2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            filled: true,
            fillColor: Colors.grey.shade100,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          style: const TextStyle(fontFamily: 'Do Hyeon', fontSize: 16),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text(
            '취소',
            style: TextStyle(fontFamily: 'SCDream', color: Colors.red),
          ),
        ),
        TextButton(
          onPressed: () {
            final newReview = _editController.text;
            if (newReview.isNotEmpty) {
              final reviewState = ref.read(reviewProvider);
              final updatedReviews = List<String>.from(
                reviewState.generatedReviews,
              );
              updatedReviews[widget.index] = newReview;
              ref
                  .read(reviewProvider.notifier)
                  .setGeneratedReviews(updatedReviews);
              Navigator.of(context).pop();
            } else {
              showAppDialog(
                context,
                title: '알림',
                message: '리뷰 내용은 비워둘 수 없습니다.',
              );
            }
          },
          child: Text(
            '저장',
            style: TextStyle(
              fontFamily: 'SCDream',
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
      ],
    );
  }
}
