import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:review_ai/models/exceptions.dart';
import 'package:review_ai/services/user_preference_service.dart';
import 'package:review_ai/services/auth_service.dart';
import 'package:review_ai/config/api_config.dart';
import '../utils/error_handler.dart';

/// Cloudflare Workers API 프록시 서버를 통한 Gemini API 호출 서비스
class ApiProxyService {
  final http.Client _client;
  final String _proxyUrl;
  final Future<String?> Function()? _tokenProvider;

  ApiProxyService(
    this._client,
    this._proxyUrl, {
    Future<String?> Function()? tokenProvider,
  }) : _tokenProvider = tokenProvider;

  /// 프록시 서버를 통한 Gemini API 호출 (JWT 인증 사용)
  Future<Map<String, dynamic>> _callGeminiApi(
    String endpoint,
    Map<String, dynamic> requestBody,
  ) async {
    final url = Uri.parse('$_proxyUrl/api/gemini-proxy');

    try {
      // JWT 토큰 가져오기 (주입된 provider가 있으면 사용, 없으면 기본 AuthService 사용)
      final accessToken = _tokenProvider != null
          ? await _tokenProvider()
          : await AuthService.getValidAccessToken();

      final response = await _client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({
              'endpoint': endpoint,
              'requestBody': requestBody,
            }),
          )
          .timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        if (kDebugMode) {
          debugPrint(
            'Proxy API Response received (length: ${responseBody.length})',
          );
        }
        return jsonDecode(responseBody);
      } else {
        // 에러 응답 처리 - JSON이 아닐 수도 있음
        final responseBody = utf8.decode(response.bodyBytes);
        if (kDebugMode) {
          debugPrint(
            'API Error Response (${response.statusCode}): $responseBody',
          );
        }

        // JSON 파싱 시도
        try {
          final errorData = jsonDecode(responseBody);
          throw GeminiApiException(
            errorData['details'] ?? errorData['error'] ?? 'API 호출 실패',
            statusCode: response.statusCode,
          );
        } catch (e) {
          // JSON 파싱 실패 시 로그만 남기고 사용자에게는 일반 메시지
          debugPrint(
            'API Error Response (non-JSON): ${responseBody.length > 100 ? responseBody.substring(0, 100) : responseBody}',
          );
          throw GeminiApiException(
            'API 서버 응답 오류가 발생했습니다.',
            statusCode: response.statusCode,
          );
        }
      }
    } on TimeoutException {
      throw NetworkException('요청 시간이 초과되었습니다.');
    } on SocketException {
      throw NetworkException('인터넷 연결을 확인해주세요.');
    } catch (e) {
      debugPrint('ApiProxyService Error: $e'); // 디버그 로그 추가
      if (e is ApiException) rethrow;
      throw ApiException(ErrorHandler.sanitizeMessage(e));
    }
  }

  /// 콘텐츠 생성
  Future<Map<String, dynamic>> generateContent(String prompt) async {
    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.0, // 완전 결정적 출력, 창의성 0
        'topK': 10, // 토큰 후보 최소화
        'topP': 0.6, // 확률 분포 최소화
        'maxOutputTokens': 2048,
      },
    };
    return await _callGeminiApi('generateContent', requestBody);
  }

  /// 리뷰 생성
  Future<List<String>> generateReviews({
    required String foodName,
    required double deliveryRating,
    required double tasteRating,
    required double portionRating,
    required double priceRating,
    required String reviewStyle,
    File? foodImage,
  }) async {
    final prompt = _buildReviewPrompt(
      foodName: foodName,
      deliveryRating: deliveryRating,
      tasteRating: tasteRating,
      portionRating: portionRating,
      priceRating: priceRating,
      reviewStyle: reviewStyle,
      foodImage: foodImage,
    );

    try {
      Uint8List? imageBytes = foodImage != null
          ? await foodImage.readAsBytes()
          : null;
      final parts = await _buildParts(prompt, imageBytes);

      final requestBody = {
        'contents': [
          {'parts': parts},
        ],
        'generationConfig': {
          'temperature': 0.3,
          'topK': 40,
          'topP': 0.8,
          'maxOutputTokens': 512,
        },
      };

      final data = await _callGeminiApi('generateContent', requestBody);

      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw ParsingException('API 응답에 후보가 없습니다.');
      }

      final content =
          candidates[0]['content']?['parts']?[0]?['text'] as String?;
      if (content == null) {
        throw ParsingException('리뷰 텍스트를 찾을 수 없습니다.');
      }

      try {
        // Clean the response to ensure it's valid JSON
        var cleanedContent = content.trim();

        // Remove markdown code blocks if present
        if (cleanedContent.startsWith('```json')) {
          cleanedContent = cleanedContent
              .replaceAll('```json', '')
              .replaceAll('```', '');
        } else if (cleanedContent.startsWith('```')) {
          cleanedContent = cleanedContent.replaceAll('```', '');
        }

        cleanedContent = cleanedContent.trim();

        final decoded = json.decode(cleanedContent) as List<dynamic>;
        final reviews = decoded.map((e) => e.toString()).toList();

        if (reviews.isEmpty) {
          throw ParsingException('유효한 리뷰가 생성되지 않았습니다.');
        }

        return reviews;
      } on FormatException {
        throw ParsingException('API 응답 형식이 올바르지 않습니다.');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ParsingException('리뷰 생성 중 오류가 발생했습니다.');
    }
  }

  /// 이미지 검증
  Future<bool> validateImage(File foodImage) async {
    const prompt =
        'Analyze the attached image. Is this a picture of prepared food suitable for a food review? Do not consider raw ingredients like a single raw onion or a piece of raw meat as prepared food. Respond with only a JSON object in the format {"is_food": boolean}.';

    try {
      Uint8List imageBytes = await foodImage.readAsBytes();
      final parts = await _buildParts(prompt, imageBytes);

      final requestBody = {
        'contents': [
          {'parts': parts},
        ],
        'generationConfig': {'temperature': 0.0, 'maxOutputTokens': 10},
      };

      final data = await _callGeminiApi('generateContent', requestBody);

      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw ImageValidationException('모델이 이미지를 분석할 수 없습니다.');
      }

      final content =
          candidates[0]['content']?['parts']?[0]?['text'] as String?;
      if (content == null) {
        throw ImageValidationException('모델의 응답을 파싱할 수 없습니다.');
      }

      try {
        // Clean the response to ensure it's valid JSON
        var cleanedContent = content.trim();

        // Remove markdown code blocks if present
        if (cleanedContent.startsWith('```json')) {
          cleanedContent = cleanedContent
              .replaceAll('```json', '')
              .replaceAll('```', '');
        } else if (cleanedContent.startsWith('```')) {
          cleanedContent = cleanedContent.replaceAll('```', '');
        }

        cleanedContent = cleanedContent.trim();

        final decoded = json.decode(cleanedContent) as Map<String, dynamic>;
        final isFood = decoded['is_food'] as bool?;

        if (isFood == true) {
          return true;
        } else {
          throw ImageValidationException('이 사진은 음식 사진이 아니거나 리뷰에 적합하지 않습니다.');
        }
      } on FormatException {
        throw ImageValidationException('이미지 분석 결과를 처리하는 데 실패했습니다.');
      } catch (e) {
        // Catch other potential errors during parsing, like type errors
        throw ImageValidationException('이미지 검증 중 오류가 발생했습니다.');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ImageValidationException('이미지 검증 중 오류가 발생했습니다.');
    }
  }

  /// 음식 이미지 분석 (Vision AI)
  Future<String> analyzeFoodImage(File foodImage) async {
    const prompt =
        'Analyze this image. Is it food? If NO, return "NOT_FOOD". If YES, return its name in Korean. Return ONLY the name or "NOT_FOOD". Do not add any punctuation or extra words.';

    try {
      Uint8List imageBytes = await foodImage.readAsBytes();
      final parts = await _buildParts(prompt, imageBytes);

      final requestBody = {
        'contents': [
          {'parts': parts},
        ],
        'generationConfig': {'temperature': 0.0, 'maxOutputTokens': 20},
      };

      final data = await _callGeminiApi('generateContent', requestBody);

      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw ParsingException('모델이 이미지를 분석할 수 없습니다.');
      }

      final content =
          candidates[0]['content']?['parts']?[0]?['text'] as String?;
      if (content == null) {
        throw ParsingException('모델의 응답을 파싱할 수 없습니다.');
      }

      return content.trim();
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('Vision AI Error: $e');
      throw ParsingException('이미지 분석 중 오류가 발생했습니다.');
    }
  }

  /// 개인화된 추천 프롬프트 생성
  Future<String> buildPersonalizedRecommendationPrompt({
    required String category,
    required List<String> recentFoods,
  }) async {
    final analysis = await UserPreferenceService.analyzeUserPreferences();
    final dislikedFoods = await UserPreferenceService.getDislikedFoods();

    final basePrompt = '''
당신은 음식을 무엇을 먹을지 고민하는 사용자를 위한 개인화된 음식 추천 시스템입니다.

사용자 취향 분석:
''';

    String preferenceInfo = '';

    if (analysis.preferredFoods.isNotEmpty) {
      preferenceInfo +=
          '''
- 자주 좋아요를 누른 음식들: ${analysis.preferredFoods.join(', ')}
''';
      preferenceInfo += '''- 이런 음식들과 비슷한 맛이나 스타일의 음식을 우선 추천해주세요.
''';
    }

    if (dislikedFoods.isNotEmpty) {
      preferenceInfo +=
          '''
- 절대 추천하지 말아야 할 음식들: ${dislikedFoods.join(', ')}
''';
      preferenceInfo += '''- 위 음식들과 비슷한 음식도 피해주세요.
''';
    }

    if (analysis.preferredCategories.isNotEmpty && category == '상관없음') {
      preferenceInfo +=
          '''
- 선호하는 카테고리: ${analysis.preferredCategories.join(', ')}
''';
      preferenceInfo += '''- 가능하면 선호 카테고리에서 더 많이 추천해주세요.
''';
    }

    final recentFoodsText = recentFoods.isEmpty
        ? '''최근에 먹은 음식이 없습니다.'''
        : '''최근에 먹은 음식들: ${recentFoods.join(', ')} (이것들은 제외해주세요)''';

    final isAny = category == '상관없음';
    String categoryRule;

    if (isAny) {
      categoryRule =
          '카테고리 제약 없이 사용자 취향에 맞게 다양하게 추천하세요.\n'
          '**주의사항**: 완성된 식사 메뉴만 추천하세요. 사이드만 있는 것(튀김만, 계란말이만) 금지.';
    } else if (category == '한식') {
      categoryRule =
          '요청된 카테고리는 "한식"입니다. **메인 요리만** 추천하세요.\n'
          '**반드시 포함**: 찌개류(김치찌개, 된장찌개, 순두부찌개), 탕류(갈비탕, 삼계탕, 육개장), 구이류(불고기, 제육볶음, 삼겹살구이, 갈비구이), 밥류(비빔밥, 덮밥류), 면류(냉면, 칼국수, 국수), 전골류(부대찌개), 정식류(백반, 한정식), 찜류(갈비찜, 아구찜)\n'
          '**절대 금지**: 사이드/반찬(김치, 깍두기, 나물, 젓갈, 장아찌, 계란말이), 중식, 일식, 양식, 분식, 음료/디저트';
    } else if (category == '중식') {
      categoryRule =
          '요청된 카테고리는 "중식"입니다. **메인 요리만** 추천하세요.\n'
          '**허용 메인 요리 (면/밥 위주)**: 짜장면, 짬뽕, 볶음밥, 마라탕, 마라샹궈, 마파두부밥, 우육면, 삼선짜장, 삼선짬뽕, 해물짬뽕, 쟁반짜장, 유니짜장, 백짬뽕, 간짜장, 훠궈, 양장피, 유산슬, 팔보채, 고추잡채, 사천짜장, 쟁반볶음밥, 해물볶음밥, 새우볶음밥, 마파두부, 깐풍볶음밥\n'
          '**절대 금지 (사이드/안주)**: 탕수육, 깐풍기, 꿔바로우, 라조기, 깐쇼새우, 유린기, 칠리새우, 멘보샤, 만두류(군만두, 찐만두, 물만두, 왕만두), 딤섬, 정도(반찬)\n'
          '**절대 금지 (창작)**: 깐풍오리, 마늘볶음밥, 깐쇼치킨, 깐풍(고추), 존재하지 않는 모든 메뉴\n'
          '**괄호 절대 금지**: 음식명에 괄호 사용 절대 불가 (예: 깐풍기(고추) X, 짬뽕(해물) X)';
    } else if (category == '일식') {
      categoryRule =
          '요청된 카테고리는 "일식"입니다. **메인 요리만** 추천하세요.\n'
          '**메인 요리**: 라멘(돈코츠라멘, 미소라멘, 쇼유라멘), 우동, 소바, 돈카츠, 규동, 오야코동, 카츠동, 텐동, 가라아게동, 초밥, 회덮밥, 장어덮밥, 오코노미야키, 야키소바, 타코야키\n'
          '**절대 금지**: 한식, 중식, 양식, 사시미만 있는 것(사시미는 안주이므로 금지)';
    } else if (category == '양식') {
      categoryRule =
          '요청된 카테고리는 "양식"입니다. **메인 요리만** 추천하세요.\n'
          '**메인 요리**: 파스타(까르보나라, 알리오올리오, 로제파스타, 크림파스타, 토마토파스타), 피자(마르게리타, 페퍼로니, 하와이안, 콤비네이션), 스테이크, 함박스테이크, 리조또, 라자냐, 오믈렛, 샌드위치, 햄버거스테이크\n'
          '**절대 금지**: 한식, 중식, 일식, 감바스만 있는 것(사이드 요리)';
    } else if (category == '분식') {
      categoryRule =
          '요청된 카테고리는 "분식"입니다. 오직 분식점 메뉴만 추천하세요.\n'
          '**반드시 포함**: 떡볶이, 순대, 튀김(오징어튀김, 야채튀김), 김밥(참치김밥, 치즈김밥, 김치김밥), 라볶이, 쫄면, 어묵(오뎅), 순대국, 떡만두국\n'
          '**절대 금지**: 한식(김치찌개, 갈비탕, 비빔밥), 중식(짜장면, 짬뽕), 일식(스시, 라멘), 사이드만 있는 것(계란말이만)';
    } else if (category == '아시안') {
      categoryRule =
          '요청된 카테고리는 "아시안"입니다. **한국에서 흔한 메뉴만** 추천하세요.\n'
          '**허용 메뉴**: 쌀국수(베트남), 팟타이, 똠얌꿍, 쏨땀, 카오팟, 팟카파오, 그린커리, 레드커리, 옐로우커리, 팟퐁커리, 분짜, 반미, 월남쌈, 나시고랭, 미고랭, 인도커리, 난, 치킨티카마살라, 탄두리치킨, 비리야니, 락사, 렌당, 바쿠테\n'
          '**절대 금지**: 한식, 중식, 일식, 양식, 존재하지 않는 긴 태국어 조합("팟카파오무쌉까이느아탈레무까이느아" 같은 것 X)';
    } else if (category == '패스트푸드') {
      categoryRule =
          '요청된 카테고리는 "패스트푸드"입니다. 오직 패스트푸드 메뉴만 추천하세요. (예: "햄버거", "프라이드치킨", "핫도그", "타코")';
    } else if (category == '편의점') {
      categoryRule =
          '요청된 카테고리는 "편의점"입니다. 편의점에서 판매하는 **구체적인 간편식/즉석식품**을 추천하세요.\n'
          '**반드시 포함**: 라면류(신라면, 짜파게티, 진라면), 삼각김밥류(참치삼각김밥, 김치삼각김밥), 도시락, 샌드위치, 햄버거, 컵라면\n'
          '**절대 금지**: 과자/스낵류(초코파이, 오예스, 새우깡), 음료(우유, 주스), 길거리음식(소떡소떡), 추상적 단어(과자, 음료)';
    } else if (category == '카페') {
      categoryRule =
          '요청된 카테고리는 "카페"입니다. 카페에서 판매하는 구체적인 음료 메뉴명만 추천하세요. (예: "아메리카노", "카페라떼", "카페모카", "카푸치노", "프라푸치노") **"커피", "라떼" 같은 추상적인 단어는 사용하지 마세요.**';
    } else {
      categoryRule =
          '반드시 모든 항목이 정확히 "$category" 카테고리여야 합니다. 다른 카테고리는 절대 포함하지 마세요.';
    }

    final examples = '''
예시(각 카테고리는 완전히 독립적임):
- 한식 ONLY: 김치찌개, 된장찌개, 비빔밥, 불고기, 제육볶음, 삼겹살구이, 갈비찜, 갈비탕, 냉면, 삼계탕, 순두부찌개, 육개장, 설렁탕, 감자탕, 보쌈, 족발
- 중식 ONLY: 짜장면, 짬뽕, 마라탕, 마라샹궈, 마파두부, 깐풍기, 볶음밥, 딤섬, 훠궈, 우육면, 탕수육, 양장피
- 일식 ONLY: 스시, 사시미, 라멘, 우동, 돈카츠, 규동, 오코노미야키, 텐동, 야키토리, 초밥
- 양식 ONLY: 까르보나라, 로제파스타, 알리오올리오, 마르게리타피자, 스테이크, 리조또, 라자냐, 감바스
- 분식 ONLY: 떡볶이, 순대, 튀김, 참치김밥, 치즈김밥, 라볶이, 쫄면, 어묵, 순대국, 떡만두국
- 아시안 ONLY: 쌀국수, 팟타이, 똠얌꿍, 반미, 카오팟, 분짜, 나시고랭, 미고랭, 인도카레
- 패스트푸드 ONLY: 햄버거, 프라이드치킨, 핫도그, 타코, 치킨너겟
- 편의점 ONLY: 신라면, 짜파게티, 참치삼각김밥, 도시락, 샌드위치, 컵라면
- 카페 ONLY: 아메리카노, 카페라떼, 카페모카, 카푸치노, 에스프레소, 바닐라라떼, 녹차라떼
''';

    return '''
$basePrompt
$preferenceInfo

$recentFoodsText

🚨 **핵심 규칙** (반드시 준수):
1. **메인 요리만**: 사이드/안주/반찬 절대 금지 (중식: 탕수육, 깐풍기, 만두, 딤섬 X)
2. **실존 음식만**: 창작 절대 금지 (깐풍오리 X, 깐쇼치킨 X)
3. **괄호 절대 금지**: 음식명에 괄호 절대 불가 (짜장면 O, 짬뽕(해물) X)
4. **카테고리 준수**: $categoryRule
5. **50개 생성**: 1~50번 빠짐없이
6. **번호 형식**: "1. 짜장면", "2. 짬뽕" ... "50. 마라탕"
7. **한국 식당 메뉴**: 실제 주문 가능한 메뉴만
- 출력은 오직 순수 JSON 배열만. 설명/문장은 금지. 마크다운 금지.
- JSON 형식: [{"name":"1. 메뉴명"}, {"name":"2. 메뉴명"}, ..., {"name":"50. 메뉴명"}]

$examples

**중요: 1번부터 50번까지 총 50개를 모두 생성하세요. 중간에 멈추지 마세요!**

이제 정확히 50개의 음식(1번~50번)을 번호와 함께 JSON 배열로만 출력하세요:
''';
  }

  /// 일반 추천 프롬프트 생성 (현재 사용 안 함 - 개인화 추천 사용)
  /*
  String buildGenericRecommendationPrompt({required String category}) {
    final isAny = category == '상관없음';
    String categoryRule;

    if (isAny) {
      categoryRule = '다양한 카테고리에서 인기 있는 음식들을 추천해주세요.';
    } else if (category == '아시안') {
      categoryRule =
          '요청된 카테고리는 "아시안"입니다. "아시안" 카테고리는 동남아시아(베트남, 태국, 인도네시아 등)와 남아시아(인도, 파키스탄 등) 음식을 포함합니다. **절대로 한식, 중식, 일식 메뉴를 포함해서는 안 됩니다.**';
    } else if (category == '편의점') {
      categoryRule =
          '요청된 카테고리는 "편의점"입니다. 편의점에서 판매하는 구체적인 제품명을 추천해주세요. (예: "신라면", "짜파게티", "삼각김밥", "도시락", "샌드위치") **"우유", "과자" 같은 추상적인 단어는 사용하지 마세요.**';
    } else if (category == '카페') {
      categoryRule =
          '요청된 카테고리는 "카페"입니다. 카페에서 판매하는 구체적인 메뉴명을 추천해주세요. (예: "아메리카노", "카페라떼", "카페모카", "카푸치노", "프라푸치노") **"커피", "라떼" 같은 추상적인 단어는 사용하지 마세요.**';
    } else {
      categoryRule =
          '반드시 모든 항목이 정확히 "$category" 카테고리여야 합니다. 다른 카테고리는 절대 포함하지 마세요.';
    }

    final examples = '''
예시(출력에 포함하지 마세요):
- 한식: 김치찌개, 된장찌개, 비빔밥, 불고기, 제육볶음, 닭갈비, 갈비탕, 냉면
- 중식: 짜장면, 짬뽕, 탕수육, 마라탕, 마라샹궈, 꿔바로우, 마파두부, 깐풍기, 볶음밥, 딤섬, 훠궈, 우육면
- 일식: 스시, 사시미, 라멘, 우동, 돈카츠, 규동, 오코노미야키, 텐동, 야키토리
- 양식: 파스타, 피자, 스테이크, 리조또, 라자냐, 감바스 알 아히요
- 분식: 떡볶이, 순대, 오뎅, 김밥, 라볶이, 쫄면
- 아시안: 쌀국수, 팟타이, 똠얌꿍, 반미, 카오팟, 분짜, 나시고랭, 미고랭, 커리
- 패스트푸드: 햄버거, 프라이드치킨, 감자튀김, 핫도그, 나초, 타코
- 편의점: 신라면, 짜파게티, 삼각김밥, 도시락, 샌드위치, 컵라면, 과자, 음료, 아이스크림, 김밥, 샐러드, 떡볶이, 라면, 햄버거, 샐러드, 주먹밥, 김치찌개, 제육볶음, 불고기, 치킨
- 카페: 아메리카노, 카페라떼, 카페모카, 카푸치노, 프라푸치노, 바닐라라떼, 아이스티, 아포가토, 케이크, 쿠키, 에스프레소, 마키아토, 모카, 아이스커피, 핫초코, 스무디, 주스, 차
''';

    return '''
당신은 특정 카테고리의 음식 메뉴를 추천하는 시스템입니다.

요구사항:
- $categoryRule
- 사용자 개인 취향은 고려하지 말고, 해당 카테고리에서 가장 대표적이고 인기 있는 메뉴들을 추천해주세요.
- 한국에서 흔히 접할 수 있는 메뉴명만 사용하세요.
- 매우 다양한 종류의 음식으로 구성해주세요.
- 개수: 15-20개.
- 출력은 오직 순수 JSON 배열만. 설명/문장은 금지. 마크다운 금지.
- JSON 형식: [{ "name":"메뉴명"}, { "name":"메뉴명"}, ...]

$examples
이제 결과를 JSON 배열로만 출력하세요.
''';
  }
  */

  String _getRatingText(double rating) {
    if (rating >= 4.5) return '매우좋음';
    if (rating >= 4.0) return '좋음';
    if (rating >= 3.5) return '보통';
    if (rating >= 3.0) return '아쉬움';
    if (rating >= 2.5) return '별로';
    return '나쁨';
  }

  Future<List<Map<String, dynamic>>> _buildParts(
    String prompt,
    Uint8List? imageBytes,
  ) async {
    List<Map<String, dynamic>> parts = [
      {'text': prompt},
    ];

    if (imageBytes != null) {
      if (imageBytes.length > 4 * 1024 * 1024) {
        throw ImageValidationException('이미지 크기가 너무 큽니다 (최대 4MB).');
      }
      final base64Image = base64Encode(imageBytes);
      parts.add({
        'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image},
      });
    }
    return parts;
  }

  String _buildReviewPrompt({
    required String foodName,
    required double deliveryRating,
    required double tasteRating,
    required double portionRating,
    required double priceRating,
    required String reviewStyle,
    File? foodImage,
  }) {
    String foodNameDescription = foodName;
    if (foodName.contains('아시아 음식')) {
      foodNameDescription = '$foodName (예: 똠양꿍, 팟타이, 베트남 쌀국수 등 동남아시아 요리 느낌으로)';
    }
    return '''
당신은 음식 리뷰 작성 전문가입니다.

아래 정보와 이미지를 바탕으로 음식 리뷰 3개를 작성하세요:

**음식 정보:**
- 사용자 입력 음식명: $foodNameDescription
- 배달: ${_getRatingText(deliveryRating)}
- 맛: ${_getRatingText(tasteRating)}
- 양: ${_getRatingText(portionRating)}
- 가격: ${_getRatingText(priceRating)}
- 리뷰 스타일: $reviewStyle

${foodImage != null ? '''
**이미지 기준 우선**: 이미지의 실제 음식과 입력된 음식명이 다르면 이미지를 우선하여 리뷰하세요.
''' : ''}

**리뷰 작성 규칙:**
1. 각 리뷰는 자연스럽고 구체적으로 작성
2. 별점이나 숫자 직접 언급 금지
3. 정확히 3개만 생성

**출력 형식:**
오직 순수 JSON 배열만. 설명/문장은 금지. 마크다운 금지.
["리뷰1", "리뷰2", "리뷰3"]''';
  }
}
