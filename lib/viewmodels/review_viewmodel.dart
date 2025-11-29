import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/usecases/generate_review_usecase.dart';
import '../models/review_state.dart';
import '../services/ad_service.dart';
import '../models/exceptions.dart'; // NetworkException
import '../providers/review_provider.dart';
import '../presentation/providers/dependency_injection.dart';
import '../widgets/common/app_dialogs.dart';
import '../main.dart'; // usageTrackingServiceProvider

class ReviewViewModel extends StateNotifier<ReviewState> {
  final Ref _ref;
  final GenerateReviewUseCase _generateReviewUseCase;
  bool _rewardEarned = false;

  ReviewViewModel(this._ref, this._generateReviewUseCase)
    : super(const ReviewState.initial());

  Future<void> generateReviews(BuildContext context) async {
    if (state.isLoading) return; // 이미 진행 중이면 리턴

    // 로딩 상태 설정 (ReviewNotifier를 통해)
    _ref.read(reviewProvider.notifier).setLoading(true);
    _rewardEarned = false; // 초기화

    if (!_validateInputs(context)) {
      _ref.read(reviewProvider.notifier).setLoading(false);
      return;
    }

    final usageTrackingService = _ref.read(usageTrackingServiceProvider);
    final reached = await usageTrackingService.hasReachedReviewLimit();
    if (reached) {
      _ref.read(reviewProvider.notifier).setLoading(false);
      if (!context.mounted) return;
      showAppDialog(context, title: '알림', message: '리뷰 생성은 하루 5회까지만 가능합니다.');
      return;
    }

    try {
      final imageFile = _ref.read(reviewProvider).image;
      if (imageFile != null) {
        // 이미지 검증 진행
        await validateImage(imageFile);
      }

      if (!context.mounted) return;
      await _handleAdFlow(context);
    } catch (e) {
      if (!context.mounted) return;
      _handleGenerationError(context, e);
    } finally {
      _ref.read(reviewProvider.notifier).setLoading(false);
    }
  }

  Future<void> _handleAdFlow(BuildContext context) async {
    // AdService는 StateNotifier가 아니므로 직접 호출하거나 notifier를 통해 호출
    // 여기서는 주입받은 _adService 사용 (하지만 AdService는 StateNotifier일 수 있음)
    // 기존 코드: final adService = _ref.read(adServiceProvider.notifier);
    // AdService가 StateNotifier라면 notifier를 가져와야 함.
    // _adService가 AdService 타입이라면 메소드 직접 호출 가능 여부 확인 필요.
    // 기존 코드에서 adServiceProvider.notifier를 읽었으므로 AdService는 StateNotifier임.
    // 따라서 주입받을 때 AdService(Notifier)를 받아야 함.

    // 편의상 _ref를 사용하여 가져옴 (주입된 _adService가 Notifier인지 확인 어려우므로)
    final adServiceNotifier = _ref.read(adServiceProvider.notifier);

    final adShown = await adServiceNotifier.showAdWithRetry(
      onUserEarnedReward: () {
        debugPrint('보상 획득 콜백 실행됨');
        _rewardEarned = true;
      },
      onAdFailedToLoad: (message) {
        debugPrint('광고 로딩 실패: $message');
      },
    );

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

      // ReviewProvider에서 상태 가져오기
      final reviewState = _ref.read(reviewProvider);

      final reviews = await _generateReviewUseCase(
        foodName: reviewState.foodName,
        deliveryRating: reviewState.deliveryRating,
        tasteRating: reviewState.tasteRating,
        portionRating: reviewState.portionRating,
        priceRating: reviewState.priceRating,
        reviewStyle: reviewState.selectedReviewStyle,
        foodImage: reviewState.image,
      );

      debugPrint('생성된 리뷰 개수: ${reviews.length}');

      _ref.read(reviewProvider.notifier).setGeneratedReviews(reviews);

      if (_isSuccessfulGeneration(reviews)) {
        await _updateUsageTracking();
        debugPrint('리뷰 생성 성공 - 화면 전환 준비');
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

  Future<bool> validateImage(File image) async {
    try {
      // Repository를 통해 검증 (UseCase에 위임 메서드가 없으므로 Repository 직접 접근)
      // Clean Architecture 원칙상 UseCase를 통해야 하지만, 편의상 Repository 접근 허용
      // 또는 GenerateReviewUseCase에 validateImage 추가 필요 (이미 추가함?)
      // GenerateReviewUseCase 정의를 보면 repository만 가지고 있고 validateImage 메서드는 없음 (call만 있음)
      // 아까 GenerateReviewUseCase 파일 생성 시 call만 만들었음.
      // 따라서 repository에 직접 접근해야 함.
      return await _generateReviewUseCase.repository.validateImage(image);
    } catch (e) {
      debugPrint('Image validation error: $e');
      return false;
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

final reviewViewModelProvider =
    StateNotifierProvider<ReviewViewModel, ReviewState>((ref) {
      final generateReviewUseCase = ref.watch(generateReviewUseCaseProvider);

      return ReviewViewModel(ref, generateReviewUseCase);
    });
