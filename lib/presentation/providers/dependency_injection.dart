import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../data/datasources/gemini_remote_data_source.dart';
import '../../data/datasources/recommendation_remote_data_source.dart';
import '../../data/repositories/review_repository_impl.dart';
import '../../data/repositories/recommendation_repository_impl.dart';
import '../../domain/repositories/review_repository.dart';
import '../../domain/repositories/recommendation_repository.dart';
import '../../domain/usecases/generate_review_usecase.dart';
import '../../domain/usecases/get_recommendation_usecase.dart';
import '../../services/api_proxy_service.dart';
import '../../config/api_config.dart';

// Data Sources
final httpClientProvider = Provider((ref) => http.Client());

final apiProxyServiceProvider = Provider((ref) {
  // 기존 ApiProxyService를 재사용하거나, 설정을 여기서 주입
  // ApiProxyService가 이미 존재하므로 그것을 활용
  // 하지만 ApiProxyService는 Service Layer에 있음.
  // 점진적 리팩토링을 위해 기존 방식을 유지하되, 여기서 인스턴스화
  return ApiProxyService(ref.read(httpClientProvider), ApiConfig.proxyUrl);
});

final geminiRemoteDataSourceProvider = Provider<GeminiRemoteDataSource>((ref) {
  return GeminiRemoteDataSourceImpl(ref.read(apiProxyServiceProvider));
});

final recommendationRemoteDataSourceProvider =
    Provider<RecommendationRemoteDataSource>((ref) {
      return RecommendationRemoteDataSourceImpl(
        ref.read(apiProxyServiceProvider),
      );
    });

// Repositories
final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepositoryImpl(ref.read(geminiRemoteDataSourceProvider));
});

final recommendationRepositoryProvider = Provider<RecommendationRepository>((
  ref,
) {
  return RecommendationRepositoryImpl(
    ref.read(recommendationRemoteDataSourceProvider),
  );
});

// Use Cases
final generateReviewUseCaseProvider = Provider<GenerateReviewUseCase>((ref) {
  return GenerateReviewUseCase(ref.read(reviewRepositoryProvider));
});

final getRecommendationUseCaseProvider = Provider<GetRecommendationUseCase>((
  ref,
) {
  return GetRecommendationUseCase(ref.read(recommendationRepositoryProvider));
});
