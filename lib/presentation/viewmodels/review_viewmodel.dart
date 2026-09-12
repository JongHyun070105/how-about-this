import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review_ai/domain/usecases/generate_review_usecase.dart';
import 'package:review_ai/presentation/providers/review_state.dart';
import 'package:review_ai/services/ad_service.dart';
import 'package:review_ai/core/exceptions.dart';
import 'package:review_ai/presentation/providers/review_provider.dart';
import 'package:review_ai/presentation/providers/dependency_injection.dart';
import 'package:review_ai/presentation/widgets/common/app_dialogs.dart';
import 'package:review_ai/presentation/providers/app_providers.dart';
import 'package:review_ai/core/utils/logger_service.dart';

class ReviewViewModel extends StateNotifier<ReviewState> {
  final Ref _ref;
  final GenerateReviewUseCase _generateReviewUseCase;
  bool _rewardEarned = false;

  ReviewViewModel(this._ref, this._generateReviewUseCase)
    : super(const ReviewState.initial());

  /// 리뷰 생성의 전체 흐름을 제어하는 진입점.
  /// 작동 순서: 1. 입력 검증 -> 2. 하루 생성 제한 확인 -> 3. 이미지 적합성 검증 -> 4. 리워드 광고 시청 -> 5. AI 리뷰 생성
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
      final limit = _ref.read(remoteConfigServiceProvider).maxDailyAiReviews;
      showAppDialog(
        context,
        title: '알림',
        message: '리뷰 생성은 하루 $limit회까지만 가능합니다.',
      );
      return;
    }

    try {
      final imageFile = _ref.read(reviewProvider).image;
      if (imageFile != null) {
        // 이미지 검증 진행
        final isValid = await validateImage(imageFile);
        final currentFoodName = _ref.read(reviewProvider).foodName.trim();
        final hasValidFoodName =
            currentFoodName.isNotEmpty && currentFoodName != 'NOT_FOOD';

        if (!isValid && !hasValidFoodName) {
          if (!context.mounted) return;
          showAppDialog(
            context,
            title: '부적절한 이미지',
            message: '음식 사진이 아니거나 식별하기 어렵습니다.\n정확한 음식 사진으로 다시 시도해주세요.',
            isError: true,
          );
          return; // 검증 실패 시 중단 (광고 시청 X)
        }
      }

      if (!context.mounted) return;

      // 광고 시청 중에 백그라운드에서 AI 리뷰를 미리 병렬 생성(Prefetch)
      // 사용자가 광고를 보는 동안 생성이 완료되므로, 광고 종료 즉시 대기 시간 없이 결과창으로 이동합니다.
      final reviewState = _ref.read(reviewProvider);
      final reviewFuture = _generateReviewUseCase(
        foodName: reviewState.foodName,
        deliveryRating: reviewState.deliveryRating,
        tasteRating: reviewState.tasteRating,
        portionRating: reviewState.portionRating,
        priceRating: reviewState.priceRating,
        reviewStyle: reviewState.selectedReviewStyle,
        foodImage: reviewState.image,
      );

      await _handleAdFlow(context, reviewFuture);
    } catch (e) {
      if (!context.mounted) return;
      _handleGenerationError(context, e);
    } finally {
      _ref.read(reviewProvider.notifier).setLoading(false);
    }
  }

  /// 사용자에게 리워드 광고를 노출하고 시청 완료(보상 획득) 여부를 확인합니다.
  /// 병렬로 실행 중인 [reviewFuture]를 결합하여 광고 시청 후 즉시 결과를 제공합니다.
  Future<void> _handleAdFlow(
    BuildContext context,
    Future<List<String>> reviewFuture,
  ) async {
    final adServiceNotifier = _ref.read(adServiceProvider.notifier);

    final adShown = await adServiceNotifier.showAdWithRetry(
      onUserEarnedReward: () {
        LoggerService.d('보상 획득 콜백 실행됨');
        _rewardEarned = true;
      },
      onAdFailedToLoad: (message) {
        LoggerService.e('광고 로딩 실패: $message');
      },
    );

    if (!context.mounted) return;

    if (adShown && _rewardEarned) {
      LoggerService.i('광고 시청 완료 - 프리페치된 리뷰 결과 결합');
      await _consumePrefetchedReviews(context, reviewFuture);
    } else {
      LoggerService.e('광고 실패 또는 보상 미획득 - 리뷰 생성 중단');
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

  Future<void> _consumePrefetchedReviews(
    BuildContext context,
    Future<List<String>> reviewFuture,
  ) async {
    if (!context.mounted) return;

    try {
      // 사용자가 광고를 보는 동안 백그라운드 생성이 이미 완료되어 0초 만에 반환됩니다.
      final reviews = await reviewFuture;
      LoggerService.d('생성된 리뷰 개수: ${reviews.length}');

      if (!context.mounted) return;
      _ref.read(reviewProvider.notifier).setGeneratedReviews(reviews);

      if (_isSuccessfulGeneration(reviews)) {
        await _updateUsageTracking();
        LoggerService.i('리뷰 생성 성공 - 화면 전환 준비');
      } else {
        showAppDialog(
          context,
          title: '알림',
          message: '리뷰 생성에 실패했습니다. 다시 시도해주세요.',
        );
      }
    } catch (e) {
      LoggerService.e('프리페치 리뷰 처리 중 오류: $e');
      if (context.mounted) {
        _handleGenerationError(context, e);
      }
    }
  }

  /// 도메인 로직(UseCase)을 통해 이미지의 유효성을 1차 검증합니다.
  /// 사진이 흔들리거나 음식이 아닌 경우 불필요한 API 토큰 낭비를 막고 사용자에게 재촬영을 암시합니다.
  Future<bool> validateImage(File image) async {
    try {
      return await _generateReviewUseCase.repository.validateImage(image);
    } catch (e) {
      LoggerService.e('Image validation error: $e');
      return false;
    }
  }

  Future<void> _updateUsageTracking() async {
    try {
      final usageTrackingService = _ref.read(usageTrackingServiceProvider);
      await usageTrackingService.incrementReviewCount();
      LoggerService.i('사용량 추적 업데이트 완료');

      // AI 리뷰 생성이 성공했을 때 인앱 리뷰 요청 로직 트리거
      await _ref.read(appReviewServiceProvider).onReviewGenerated();
    } catch (e) {
      LoggerService.e('사용량 추적 업데이트 오류: $e');
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
    LoggerService.e('리뷰 생성 오류 상세: $error');

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
