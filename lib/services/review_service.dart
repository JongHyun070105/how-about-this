import 'dart:async';
import 'dart:io';
import 'package:review_ai/core/utils/logger_service.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:review_ai/presentation/providers/app_providers.dart';
import 'package:review_ai/presentation/providers/review_provider.dart';

import 'api_proxy_service.dart';
import 'image_optimization_service.dart';

// 새로운 ReviewService의 Provider
final reviewServiceProvider = Provider((ref) => ReviewService(ref));

class ReviewService {
  final Ref _ref;

  // 임시 경로 캐시
  static String? _cachedTempDirPath;

  ReviewService(this._ref);

  /// 이미지를 최적화하여 API 호출 속도 향상
  Future<File?> _optimizeImage(File? imageFile) async {
    if (imageFile == null || !await imageFile.exists()) return null;

    try {
      LoggerService.d('이미지 최적화 시작: ${imageFile.path}');

      // 파일 읽기는 메인 isolate에서, 무거운 디코드/리사이즈/인코드는 background isolate에서 처리
      final bytes = await imageFile.readAsBytes();
      final optimizedBytes = await optimizeUploadedImageBytes(bytes);

      if (optimizedBytes == null) {
        LoggerService.e('이미지 최적화 불필요 (크기 적절함 또는 디코딩 실패)');
        return imageFile;
      }

      if (_cachedTempDirPath == null) {
        final tempDir = await getTemporaryDirectory();
        _cachedTempDirPath = tempDir.path;
      }
      final tempFile = File(
        '$_cachedTempDirPath/optimized_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(optimizedBytes, flush: true);

      LoggerService.i('이미지 최적화 완료: ${imageFile.path} -> ${tempFile.path}');
      return tempFile;
    } catch (e) {
      LoggerService.e('이미지 최적화 실패: $e');
      return imageFile; // 최적화 실패시 원본 반환
    }
  }

  /// 생성 단계별 진행상황 표시를 위한 콜백
  Future<List<String>> generateReviewsFromState({
    Function(String)? onProgress,
  }) async {
    File? optimizedImage;
    try {
      onProgress?.call('리뷰 생성 준비 중...');
      LoggerService.d('리뷰 생성 시작');

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
      if (reviewState.image != null) {
        onProgress?.call('이미지 처리 중...');
        optimizedImage = await _optimizeImage(reviewState.image);
      }

      onProgress?.call('AI 분석 중... (최대 45초 소요)');
      LoggerService.d('Gemini API 호출 시작');

      // 타임아웃 설정된 API 호출 (.timeout() 사용으로 미완료 Future 방지)
      const timeoutDuration = Duration(seconds: 45);
      final reviews = await apiProxyService
          .generateReviews(
            foodName: reviewState.foodName,
            deliveryRating: reviewState.deliveryRating,
            tasteRating: reviewState.tasteRating,
            portionRating: reviewState.portionRating,
            priceRating: reviewState.priceRating,
            reviewStyle: reviewState.selectedReviewStyle,
            foodImage: optimizedImage,
          )
          .timeout(
            timeoutDuration,
            onTimeout: () => throw TimeoutException(
              '처리 시간이 너무 오래 걸립니다.\n• 다른 이미지를 선택해보세요\n• 음식 전체가 보이는 사진을 사용해보세요\n• 잠시 후 다시 시도해주세요',
              timeoutDuration,
            ),
          );

      LoggerService.i('리뷰 생성 완료: ${reviews.length}개');
      onProgress?.call('리뷰 생성 완료!');
      return reviews;
    } catch (e) {
      LoggerService.e('리뷰 생성 오류: $e');
      rethrow;
    } finally {
      final reviewState = _ref.read(reviewProvider);
      if (optimizedImage != null && optimizedImage != reviewState.image) {
        try {
          ApiProxyService.evictImage(optimizedImage.path);
          if (await optimizedImage.exists()) {
            await optimizedImage.delete();
            LoggerService.i('임시 최적화 이미지 파일 삭제 완료');
          }
        } catch (e) {
          LoggerService.e('임시 파일 삭제 실패: $e');
        }
      }
    }
  }

  /// 사용량 카운트 증가 등 생성 후 작업을 처리합니다.
  Future<void> handleSuccessfulGeneration() async {
    final usageTrackingService = _ref.read(usageTrackingServiceProvider);
    await usageTrackingService.incrementReviewCount();

    // 현재 리뷰 상태 가져오기
    final reviewState = _ref.read(reviewProvider);

    // ReviewHistoryEntry 생성
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

    // 히스토리에 추가
    await _ref.read(reviewHistoryProvider.notifier).addReview(newEntry);

    // 생성 및 저장 성공 후 리뷰 상태 초기화
    _ref.read(reviewProvider.notifier).reset();
  }
}
