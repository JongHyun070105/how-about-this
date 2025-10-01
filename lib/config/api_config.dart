/// API 관련 설정 상수
class ApiConfig {
  // Cloudflare Workers API 프록시 서버 URL
  static const String proxyUrl =
      'https://reviewai-api-proxy.how-about-this-api.workers.dev';

  // API 타임아웃 설정
  static const Duration timeout = Duration(seconds: 30);

  // 허용된 엔드포인트 목록
  static const List<String> allowedEndpoints = [
    'generateContent',
    'generateReviews',
    'validateImage',
    'buildPersonalizedRecommendationPrompt',
    'buildGenericRecommendationPrompt',
  ];
}
