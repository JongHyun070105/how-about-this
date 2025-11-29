import 'package:review_ai/models/exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review_ai/main.dart';
import 'package:review_ai/providers/review_provider.dart';
import 'package:review_ai/services/ad_service.dart';
import 'package:review_ai/services/review_service.dart';
import 'package:review_ai/widgets/common/app_dialogs.dart';

class ReviewViewModel extends StateNotifier<bool> {
  final Ref _ref;
  bool _rewardEarned = false;

  ReviewViewModel(this._ref) : super(false);

  Future<void> generateReviews(BuildContext context) async {
    if (state) return; // 이미 진행 중이면 리턴

    state = true;
    _rewardEarned = false; // 초기화

    if (!_validateInputs(context)) {
      state = false;
      return;
    }

    final usageTrackingService = _ref.read(usageTrackingServiceProvider);
    final reached = await usageTrackingService.hasReachedReviewLimit();
    if (reached) {
      state = false;
      if (!context.mounted) return;
      showAppDialog(context, title: '알림', message: '리뷰 생성은 하루 5회까지만 가능합니다.');
      return;
    }

    // 로딩 상태 설정
    _ref.read(reviewProvider.notifier).setLoading(true);

    try {
      final imageFile = _ref.read(reviewProvider).image;
      if (imageFile != null) {
        // 이미지 검증 진행 (다이얼로그 없이)
        await _ref.read(geminiServiceProvider).validateImage(imageFile);
      }

      if (!context.mounted) return;
      await _handleAdFlow(context);
    } catch (e) {
      if (!context.mounted) return;
      _handleGenerationError(context, e);
    } finally {
      _ref.read(reviewProvider.notifier).setLoading(false);
      state = false;
    }
  }

  Future<void> _handleAdFlow(BuildContext context) async {
    final adService = _ref.read(adServiceProvider.notifier);

    final adShown = await adService.showAdWithRetry(
      onUserEarnedReward: () {
        debugPrint('보상 획득 콜백 실행됨');
        _rewardEarned = true;
      },
      onAdFailedToLoad: (message) {
        // 광고 로딩 실패 메시지는 로그로만 처리
        debugPrint('광고 로딩 실패: $message');
      },
    );

    // 광고 표시 완료 후 리뷰 생성
    if (!context.mounted) return;

    if (adShown && _rewardEarned) {
      debugPrint('광고 시청 완료 - 리뷰 생성 시작');
      await _generateReviewsAfterAd(context);
    } else {
      debugPrint('광고 실패 또는 보상 미획득 - 리뷰 생성 중단');
      if (!context.mounted) return;

      showAppDialog(
        context,
        title: '광고 시청 필요',
        message: '리뷰를 생성하려면 광고를 시청해야 합니다.\n네트워크 상태를 확인하고 다시 시도해주세요.',
        confirmButtonText: '다시 시도',
        onConfirm: () {
          // 다시 시도 (재귀 호출이 아닌 새로운 호출)
          generateReviews(context);
        },
        cancelButtonText: '취소',
      );
    }
  }

  Future<void> _generateReviewsAfterAd(BuildContext context) async {
    if (!context.mounted) return;

    try {
      debugPrint('리뷰 생성 시작');
      final reviewService = _ref.read(reviewServiceProvider);

      final rawReviews = await reviewService.generateReviewsFromState(
        onProgress: (progress) {
          // 진행상황은 로그로만 처리
          debugPrint('리뷰 생성 진행: $progress');
        },
      );

      // 줄바꿈 기준으로 분리하여 여러 리뷰로 나누기
      final reviews = rawReviews
          .expand((r) => r.split(RegExp(r'\n\s*\n')))
          .toList();

      debugPrint('생성된 리뷰 개수: ${reviews.length}');

      _ref.read(reviewProvider.notifier).setGeneratedReviews(reviews);

      if (_isSuccessfulGeneration(reviews)) {
        // 히스토리 저장을 제거하고, 사용량 추적만 업데이트
        await _updateUsageTracking();
        debugPrint('리뷰 생성 성공 - 화면 전환 준비');
        // 화면 전환은 UI에서 listen을 통해 처리됨
      } else {
        if (!context.mounted) return;
        showAppDialog(
          context,
          title: '알림',
          message: '리뷰 생성에 실패했습니다. 다시 시도해주세요.',
        );
      }
    } catch (e) {
      debugPrint('리뷰 생성 중 오류: $e');
      if (context.mounted) {
        _handleGenerationError(context, e);
      }
    }
  }

  Future<void> _updateUsageTracking() async {
    try {
      final usageTrackingService = _ref.read(usageTrackingServiceProvider);
      await usageTrackingService.incrementReviewCount();
      debugPrint('사용량 추적 업데이트 완료');
    } catch (e) {
      debugPrint('사용량 추적 업데이트 오류: $e');
    }
  }

  bool _validateInputs(BuildContext context) {
    final reviewState = _ref.read(reviewProvider);

    if (reviewState.foodName.isEmpty ||
        reviewState.deliveryRating == 0 ||
        reviewState.tasteRating == 0 ||
        reviewState.portionRating == 0 ||
        reviewState.priceRating == 0) {
      if (context.mounted) {
        showAppDialog(
          context,
          title: '입력 오류',
          message: '모든 입력을 완료해주세요.',
          isError: true,
        );
      }
      return false;
    }
    return true;
  }

  bool _isSuccessfulGeneration(List<String> reviews) {
    return reviews.isNotEmpty && !reviews.first.contains('오류');
  }

  void _handleGenerationError(BuildContext context, dynamic error) {
    if (!context.mounted) return;

    final errorString = error.toString().toLowerCase();
    debugPrint("리뷰 생성 오류 상세: $error");

    String userMessage;
    if (error is NetworkException ||
        errorString.contains('socketexception') ||
        errorString.contains('timeoutexception') ||
        errorString.contains('handshakeexception')) {
      userMessage = '네트워크 연결이 불안정합니다. 인터넷 상태를 확인 후 다시 시도해주세요.';
    } else if (errorString.contains('부적절한 이미지') ||
        errorString.contains('리뷰에 적합하지 않습니다')) {
      userMessage = '음식 사진이 아니거나 식별하기 어렵습니다. 다른 사진으로 시도해주세요.';
    } else if (errorString.contains('api 응답에 후보가 없습니다') ||
        errorString.contains('유효한 리뷰가 생성되지 않았습니다')) {
      userMessage = '리뷰를 생성하지 못했습니다. 입력 내용을 조금 바꾸거나 다른 스타일을 선택해보세요.';
    } else if (errorString.contains('이미지 크기가 너무 큽니다')) {
      userMessage = '이미지 파일이 너무 큽니다. 4MB 이하의 사진을 사용해주세요.';
    } else {
      // 그 외의 모든 오류는 사용자에게 상세 정보를 노출하지 않음
      userMessage = '알 수 없는 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
    }

    showAppDialog(context, title: '오류', message: userMessage, isError: true);
  }

  @override
  void dispose() {
    _rewardEarned = false;
    super.dispose();
  }
}

final reviewViewModelProvider = StateNotifierProvider<ReviewViewModel, bool>((
  ref,
) {
  return ReviewViewModel(ref);
});
