import 'dart:io';
import 'package:review_ai/services/user_preference_service.dart';

/// AI 프롬프트 생성 전담 클래스
///
/// 음식 추천 프롬프트와 리뷰 생성 프롬프트를 구성합니다.
/// [ApiProxyService]에서 분리하여 단일 책임 원칙을 준수합니다.
class PromptBuilder {
  /// 별점을 텍스트로 변환
  static String getRatingText(double rating) {
    if (rating >= 4.5) return '매우좋음';
    if (rating >= 4.0) return '좋음';
    if (rating >= 3.5) return '보통';
    if (rating >= 3.0) return '아쉬움';
    if (rating >= 2.5) return '별로';
    return '나쁨';
  }

  /// 개인화된 추천 프롬프트 생성
  static Future<String> buildPersonalizedRecommendationPrompt({
    required String category,
    required List<String> recentFoods,
  }) async {
    final analysis = await UserPreferenceService.analyzeUserPreferences();
    final dislikedFoods = analysis.dislikedFoods;

    const basePrompt = '''
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

    final categoryRule = _getCategoryRule(category);

    final examples = _getCategoryExamples(category);

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

  /// 카테고리별 규칙 반환
  static String _getCategoryRule(String category) {
    final isAny = category == '상관없음';

    if (isAny) {
      return '카테고리 제약 없이 사용자 취향에 맞게 다양하게 추천하세요.\n'
          '**주의사항**: 완성된 식사 메뉴만 추천하세요. 사이드만 있는 것(튀김만, 계란말이만) 금지.';
    } else if (category == '한식') {
      return '요청된 카테고리는 "한식"입니다. **메인 요리만** 추천하세요.\n'
          '**반드시 포함**: 찌개류(김치찌개, 된장찌개, 순두부찌개), 탕류(갈비탕, 삼계탕, 육개장), 구이류(불고기, 제육볶음, 삼겹살구이, 갈비구이), 밥류(비빔밥, 덮밥류), 면류(냉면, 칼국수, 국수), 전골류(부대찌개), 정식류(백반, 한정식), 찜류(갈비찜, 아구찜)\n'
          '**절대 금지**: 사이드/반찬(김치, 깍두기, 나물, 젓갈, 장아찌, 계란말이), 중식, 일식, 양식, 분식, 음료/디저트';
    } else if (category == '중식') {
      return '요청된 카테고리는 "중식"입니다. **메인 요리만** 추천하세요.\n'
          '**허용 메인 요리 (면/밥 위주)**: 짜장면, 짬뽕, 볶음밥, 마라탕, 마라샹궈, 마파두부밥, 우육면, 삼선짜장, 삼선짬뽕, 해물짬뽕, 쟁반짜장, 유니짜장, 백짬뽕, 간짜장, 훠궈, 양장피, 유산슬, 팔보채, 고추잡채, 사천짜장, 쟁반볶음밥, 해물볶음밥, 새우볶음밥, 마파두부, 깐풍볶음밥\n'
          '**절대 금지 (사이드/안주)**: 탕수육, 깐풍기, 꿔바로우, 라조기, 깐쇼새우, 유린기, 칠리새우, 멘보샤, 만두류(군만두, 찐만두, 물만두, 왕만두), 딤섬, 정도(반찬)\n'
          '**절대 금지 (창작)**: 깐풍오리, 마늘볶음밥, 깐쇼치킨, 깐풍(고추), 존재하지 않는 모든 메뉴\n'
          '**괄호 절대 금지**: 음식명에 괄호 사용 절대 불가 (예: 깐풍기(고추) X, 짬뽕(해물) X)';
    } else if (category == '일식') {
      return '요청된 카테고리는 "일식"입니다. **메인 요리만** 추천하세요.\n'
          '**메인 요리**: 라멘(돈코츠라멘, 미소라멘, 쇼유라멘), 우동, 소바, 돈카츠, 규동, 오야코동, 카츠동, 텐동, 가라아게동, 초밥, 회덮밥, 장어덮밥, 오코노미야키, 야키소바, 타코야키\n'
          '**절대 금지**: 한식, 중식, 양식, 사시미만 있는 것(사시미는 안주이므로 금지)';
    } else if (category == '양식') {
      return '요청된 카테고리는 "양식"입니다. **메인 요리만** 추천하세요.\n'
          '**메인 요리**: 파스타(까르보나라, 알리오올리오, 로제파스타, 크림파스타, 토마토파스타), 피자(마르게리타, 페퍼로니, 하와이안, 콤비네이션), 스테이크, 함박스테이크, 리조또, 라자냐, 오믈렛, 샌드위치, 햄버거스테이크\n'
          '**절대 금지**: 한식, 중식, 일식, 감바스만 있는 것(사이드 요리)';
    } else if (category == '분식') {
      return '요청된 카테고리는 "분식"입니다. 오직 분식점 메뉴만 추천하세요.\n'
          '**반드시 포함**: 떡볶이, 순대, 튀김(오징어튀김, 야채튀김), 김밥(참치김밥, 치즈김밥, 김치김밥), 라볶이, 쫄면, 어묵(오뎅), 순대국, 떡만두국\n'
          '**절대 금지**: 한식(김치찌개, 갈비탕, 비빔밥), 중식(짜장면, 짬뽕), 일식(스시, 라멘), 사이드만 있는 것(계란말이만)';
    } else if (category == '아시안') {
      return '요청된 카테고리는 "아시안"입니다. **한국에서 흔한 메뉴만** 추천하세요.\n'
          '**허용 메뉴**: 쌀국수(베트남), 팟타이, 똠얌꿍, 쏨땀, 카오팟, 팟카파오, 그린커리, 레드커리, 옐로우커리, 팟퐁커리, 분짜, 반미, 월남쌈, 나시고랭, 미고랭, 인도커리, 난, 치킨티카마살라, 탄두리치킨, 비리야니, 락사, 렌당, 바쿠테\n'
          '**절대 금지**: 한식, 중식, 일식, 양식, 존재하지 않는 긴 태국어 조합("팟카파오무쌉까이느아탈레무까이느아" 같은 것 X)';
    } else if (category == '패스트푸드') {
      return '요청된 카테고리는 "패스트푸드"입니다. 오직 패스트푸드 메뉴만 추천하세요. (예: "햄버거", "프라이드치킨", "핫도그", "타코")';
    } else if (category == '편의점') {
      return '요청된 카테고리는 "편의점"입니다. 편의점에서 판매하는 **구체적인 간편식/즉석식품**을 추천하세요.\n'
          '**반드시 포함**: 라면류(신라면, 짜파게티, 진라면), 삼각김밥류(참치삼각김밥, 김치삼각김밥), 도시락, 샌드위치, 햄버거, 컵라면\n'
          '**절대 금지**: 과자/스낵류(초코파이, 오예스, 새우깡), 음료(우유, 주스), 길거리음식(소떡소떡), 추상적 단어(과자, 음료)';
    } else if (category == '카페') {
      return '요청된 카테고리는 "카페"입니다. 카페에서 판매하는 구체적인 음료 메뉴명만 추천하세요. (예: "아메리카노", "카페라떼", "카페모카", "카푸치노", "프라푸치노") **"커피", "라떼" 같은 추상적인 단어는 사용하지 마세요.**';
    } else {
      return '반드시 모든 항목이 정확히 "$category" 카테고리여야 합니다. 다른 카테고리는 절대 포함하지 마세요.';
    }
  }

  /// 리뷰 생성 프롬프트 구성
  static String buildReviewPrompt({
    required String foodName,
    required double deliveryRating,
    required double tasteRating,
    required double portionRating,
    required double priceRating,
    required String reviewStyle,
    File? foodImage,
  }) {
    // 줄바꿈 및 제어 문자 제거, 최대 100자 제한 (프롬프트 인젝션 및 오염 방어)
    final sanitizedFoodName = foodName
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .trim();
    final truncatedFoodName = sanitizedFoodName.length > 100
        ? sanitizedFoodName.substring(0, 100)
        : sanitizedFoodName;

    String foodNameDescription = truncatedFoodName;
    if (truncatedFoodName.contains('아시아 음식')) {
      foodNameDescription =
          '$truncatedFoodName (예: 똠양꿍, 팟타이, 베트남 쌀국수 등 동남아시아 요리 느낌으로)';
    }
    return '''
당신은 음식 리뷰 작성 전문가입니다.

아래 정보와 이미지를 바탕으로 음식 리뷰 3개를 작성하세요:

**음식 정보:**
- 사용자 입력 음식명: $foodNameDescription
- 배달: ${getRatingText(deliveryRating)}
- 맛: ${getRatingText(tasteRating)}
- 양: ${getRatingText(portionRating)}
- 가격: ${getRatingText(priceRating)}
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

  /// 카테고리별 예시 음식 반환
  static String _getCategoryExamples(String category) {
    String examplesText = '';
    if (category == '한식') {
      examplesText =
          '한식 예시: 김치찌개, 된장찌개, 비빔밥, 불고기, 제육볶음, 삼겹살구이, 갈비찜, 갈비탕, 냉면, 삼계탕, 순두부찌개, 육개장, 설렁탕, 감자탕, 보쌈, 족발';
    } else if (category == '중식') {
      examplesText =
          '중식 예시: 짜장면, 짬뽕, 마라탕, 마라샹궈, 마파두부, 깐풍기, 볶음밥, 딤섬, 훠궈, 우육면, 탕수육, 양장피';
    } else if (category == '일식') {
      examplesText = '일식 예시: 스시, 사시미, 라멘, 우동, 돈카츠, 규동, 오코노미야키, 텐동, 야키토리, 초밥';
    } else if (category == '양식') {
      examplesText =
          '양식 예시: 까르보나라, 로제파스타, 알리오올리오, 마르게리타피자, 스테이크, 리조또, 라자냐, 감바스';
    } else if (category == '분식') {
      examplesText = '분식 예시: 떡볶이, 순대, 튀김, 참치김밥, 치즈김밥, 라볶이, 쫄면, 어묵';
    } else if (category == '아시안') {
      examplesText = '아시안 예시: 쌀국수, 팟타이, 똠얌꿍, 반미, 카오팟, 분짜, 나시고랭, 미고랭, 인도카레';
    } else if (category == '패스트푸드') {
      examplesText = '패스트푸드 예시: 햄버거, 프라이드치킨, 핫도그, 타코, 치킨너겟';
    } else if (category == '편의점') {
      examplesText = '편의점 예시: 신라면, 짜파게티, 참치삼각김밥, 도시락, 샌드위치, 컵라면';
    } else if (category == '카페') {
      examplesText = '카페 예시: 아메리카노, 카페라떼, 카페모카, 카푸치노, 에스프레소, 바닐라라떼, 녹차라떼';
    } else {
      return ''; // 상관없음 등은 예시 생략 (광범위하므로)
    }

    return '\n추천 예시 (반드시 이 카테고리 내에서만 선택):\n- $examplesText\n';
  }
}
