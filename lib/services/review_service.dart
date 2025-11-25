import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review_ai/main.dart';
import 'package:review_ai/providers/review_provider.dart';

import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

// Provider for the new ReviewService
final reviewServiceProvider = Provider((ref) => ReviewService(ref));

class ReviewService {
  final Ref _ref;

  ReviewService(this._ref);

  /// 이미지를 최적화하여 API 호출 속도 향상
  Future<File?> _optimizeImage(File? imageFile) async {
    if (imageFile == null || !imageFile.existsSync()) return null;

    try {
      debugPrint('이미지 최적화 시작: ${imageFile.path}');

      // 이미지가 너무 클 경우 리사이징
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        debugPrint('이미지 디코딩 실패');
        return imageFile;
      }

      debugPrint('원본 이미지 크기: ${image.width}x${image.height}');

      // 최대 크기 제한 (가로/세로 각각 800px)
      img.Image resized = image;
      if (image.width > 800 || image.height > 800) {
        resized = img.copyResize(
          image,
          width: image.width > image.height ? 800 : null,
          height: image.height > image.width ? 800 : null,
        );

        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
          '${tempDir.path}/optimized_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await tempFile.writeAsBytes(img.encodeJpg(resized, quality: 85));

        debugPrint(
          '이미지 최적화 완료: ${image.width}x${image.height} -> ${resized.width}x${resized.height}',
        );
        return tempFile;
      }

      debugPrint('이미지 최적화 불필요 (크기 적절함)');
      return imageFile;
    } catch (e) {
      debugPrint('이미지 최적화 실패: $e');
      return imageFile; // 최적화 실패시 원본 반환
    }
  }

  /// 생성 단계별 진행상황 표시를 위한 콜백
  Future<List<String>> generateReviewsFromState({
    Function(String)? onProgress,
  }) async {
    try {
      onProgress?.call('리뷰 생성 준비 중...');
      debugPrint('리뷰 생성 시작');

      final apiProxyService = _ref.read(geminiServiceProvider);
      final reviewState = _ref.read(reviewProvider);

      // 입력 검증
      if (reviewState.foodName.trim().isEmpty) {
        throw Exception('음식명을 입력해주세요');
      }

      if (reviewState.deliveryRating == 0 ||
          reviewState.tasteRating == 0 ||
          reviewState.portionRating == 0 ||
          reviewState.priceRating == 0) {
        throw Exception('모든 별점을 입력해주세요');
      }

      if (reviewState.selectedReviewStyle.isEmpty) {
        throw Exception('리뷰 스타일을 선택해주세요');
      }

      // 이미지 최적화 (시간이 오래 걸리는 부분)
      File? optimizedImage;
      if (reviewState.image != null) {
        onProgress?.call('이미지 처리 중...');
        optimizedImage = await _optimizeImage(reviewState.image);
      }

      onProgress?.call('AI 분석 중... (최대 45초 소요)');
      debugPrint('Gemini API 호출 시작');

      // 타임아웃 설정된 API 호출
      const timeoutDuration = Duration(seconds: 45);
      final timeoutFuture = Future.delayed(timeoutDuration, () {
        throw TimeoutException(
          '처리 시간이 너무 오래 걸립니다.\n• 다른 이미지를 선택해보세요\n• 음식 전체가 보이는 사진을 사용해보세요\n• 잠시 후 다시 시도해주세요',
          timeoutDuration,
        );
      });

      final reviews = await Future.any([
        apiProxyService.generateReviews(
          foodName: reviewState.foodName,
          deliveryRating: reviewState.deliveryRating,
          tasteRating: reviewState.tasteRating,
          portionRating: reviewState.portionRating,
          priceRating: reviewState.priceRating,
          reviewStyle: reviewState.selectedReviewStyle,
          foodImage: optimizedImage,
        ),
        timeoutFuture,
      ]);

      if (optimizedImage != null && optimizedImage != reviewState.image) {
        try {
          await optimizedImage.delete();
          debugPrint('임시 최적화 이미지 파일 삭제 완료');
        } catch (e) {
          debugPrint('임시 파일 삭제 실패: $e');
        }
      }

      debugPrint('리뷰 생성 완료: ${reviews.length}개');
      onProgress?.call('리뷰 생성 완료!');
      return reviews;
    } catch (e) {
      debugPrint('리뷰 생성 오류: $e');
      rethrow;
    }
  }

  /// Handles post-generation tasks like incrementing usage counts.
  Future<void> handleSuccessfulGeneration() async {
    final usageTrackingService = _ref.read(usageTrackingServiceProvider);
    await usageTrackingService.incrementReviewCount();

    // Get the current review state
    final reviewState = _ref.read(reviewProvider);

    // Create a ReviewHistoryEntry
    final newEntry = ReviewHistoryEntry(
      foodName: reviewState.foodName,
      restaurantName: reviewState.restaurantName,
      imagePath: reviewState.image?.path,
      deliveryRating: reviewState.deliveryRating,
      tasteRating: reviewState.tasteRating,
      portionRating: reviewState.portionRating,
      priceRating: reviewState.priceRating,
      reviewStyle: reviewState.selectedReviewStyle,
      emphasis: reviewState.emphasis,
      category: reviewState.category,
      generatedReviews: reviewState.generatedReviews,
    );

    // Add to history
    await _ref.read(reviewHistoryProvider.notifier).addReview(newEntry);

    // Reset the review state after successful generation and saving
    _ref.read(reviewProvider.notifier).reset();
  }
}
