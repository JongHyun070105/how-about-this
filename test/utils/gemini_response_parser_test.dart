import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/utils/gemini_response_parser.dart';
import 'package:review_ai/data/models/food_recommendation.dart';

void main() {
  group('GeminiResponseParser', () {
    test('파싱 오류 로그에는 원문 응답이 포함되지 않는다', () {
      const secretPayload = 'private-user-prompt';
      final message = GeminiResponseParser.safeParseErrorMessage(
        const FormatException('bad JSON', secretPayload),
      );

      expect(message, contains('FormatException'));
      expect(message, isNot(contains(secretPayload)));
    });

    group('extractText', () {
      test('정상적인 응답에서 텍스트를 추출한다', () {
        final response = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Hello World'},
                ],
              },
            },
          ],
        };

        expect(GeminiResponseParser.extractText(response), 'Hello World');
      });

      test('candidates가 없으면 null을 반환한다', () {
        final response = <String, dynamic>{};
        expect(GeminiResponseParser.extractText(response), isNull);
      });

      test('candidates가 빈 리스트이면 null을 반환한다', () {
        final response = {'candidates': []};
        expect(GeminiResponseParser.extractText(response), isNull);
      });

      test('text가 없으면 null을 반환한다', () {
        final response = {
          'candidates': [
            {
              'content': {
                'parts': [{}],
              },
            },
          ],
        };
        expect(GeminiResponseParser.extractText(response), isNull);
      });
    });

    group('cleanMarkdownJson', () {
      test('```json 코드 블록을 제거한다', () {
        const input = '```json\n[{"name": "치킨"}]\n```';
        final result = GeminiResponseParser.cleanMarkdownJson(input);
        expect(result, '[{"name": "치킨"}]');
      });

      test('``` 코드 블록을 제거한다', () {
        const input = '```\n[{"name": "피자"}]\n```';
        final result = GeminiResponseParser.cleanMarkdownJson(input);
        expect(result, '[{"name": "피자"}]');
      });

      test('대문자 JSON 언어 태그 코드 블록을 제거한다', () {
        const input = '```JSON\n[{"name": "초밥"}]\n```';
        final result = GeminiResponseParser.cleanMarkdownJson(input);
        expect(result, '[{"name": "초밥"}]');
      });

      test('공백이 포함된 json 언어 태그 코드 블록을 제거한다', () {
        const input = '``` json\n[{"name": "쌀국수"}]\n```';
        final result = GeminiResponseParser.cleanMarkdownJson(input);
        expect(result, '[{"name": "쌀국수"}]');
      });

      test('코드 블록이 없으면 그대로 반환한다', () {
        const input = '[{"name": "김밥"}]';
        final result = GeminiResponseParser.cleanMarkdownJson(input);
        expect(result, '[{"name": "김밥"}]');
      });

      test('앞뒤 공백을 제거한다', () {
        const input = '  [{"name": "라면"}]  ';
        final result = GeminiResponseParser.cleanMarkdownJson(input);
        expect(result, '[{"name": "라면"}]');
      });

      test('설명 문장이 앞뒤에 있어도 JSON 배열만 추출한다', () {
        const input = '''
추천 메뉴는 아래와 같습니다.
[{"name": "칼국수"}]
맛있게 드세요!
''';

        final result = GeminiResponseParser.cleanMarkdownJson(input);

        expect(result, '[{"name": "칼국수"}]');
      });
    });

    group('parseRecommendations', () {
      test('정상 응답을 FoodRecommendation 리스트로 파싱한다', () {
        final response = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text':
                        '[{"name": "김치찌개", "imageUrl": ""}, {"name": "된장찌개", "imageUrl": ""}]',
                  },
                ],
              },
            },
          ],
        };

        final result = GeminiResponseParser.parseRecommendations(response);
        expect(result.length, 2);
        expect(result[0].name, '김치찌개');
        expect(result[1].name, '된장찌개');
      });

      test('숫자 접두사가 있는 이름을 정리한다', () {
        final response = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text':
                        '[{"name": "1. 삼겹살", "imageUrl": ""}, {"name": "2. 냉면", "imageUrl": ""}]',
                  },
                ],
              },
            },
          ],
        };

        final result = GeminiResponseParser.parseRecommendations(response);
        expect(result[0].name, '삼겹살');
        expect(result[1].name, '냉면');
      });

      test('마크다운 코드 블록으로 감싼 응답을 파싱한다', () {
        final response = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': '```json\n[{"name": "우동", "imageUrl": ""}]\n```'},
                ],
              },
            },
          ],
        };

        final result = GeminiResponseParser.parseRecommendations(response);
        expect(result.length, 1);
        expect(result[0].name, '우동');
      });

      test('대문자 JSON 코드 블록으로 감싼 응답을 파싱한다', () {
        final response = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': '```JSON\n[{"name": "초밥", "imageUrl": ""}]\n```'},
                ],
              },
            },
          ],
        };

        final result = GeminiResponseParser.parseRecommendations(response);
        expect(result.length, 1);
        expect(result[0].name, '초밥');
      });

      test('설명 문장으로 감싼 추천 응답을 파싱한다', () {
        final response = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': '''
아래 추천 메뉴를 확인해 주세요.
[{"name": "칼국수", "imageUrl": ""}]
추천 이유: 비 오는 날에 잘 어울립니다.
''',
                  },
                ],
              },
            },
          ],
        };

        final result = GeminiResponseParser.parseRecommendations(response);

        expect(result.length, 1);
        expect(result[0].name, '칼국수');
      });

      test('recommendations 키로 감싼 JSON 객체 응답을 파싱한다', () {
        final response = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text':
                        '{"recommendations": [{"name": "쌀국수", "imageUrl": ""}]}',
                  },
                ],
              },
            },
          ],
        };

        final result = GeminiResponseParser.parseRecommendations(response);

        expect(result.length, 1);
        expect(result[0].name, '쌀국수');
      });

      test('설명용 JSON 객체보다 실제 JSON 배열을 우선 파싱한다', () {
        final response = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': '''
아래는 예시 설명입니다.
{"example": "ignore me"}
실제 추천 응답:
[
  {"name": "비빔밥", "imageUrl": ""}
]
''',
                  },
                ],
              },
            },
          ],
        };

        final result = GeminiResponseParser.parseRecommendations(response);

        expect(result.length, 1);
        expect(result[0].name, '비빔밥');
      });

      test('객체와 배열의 trailing comma가 있어도 추천 응답을 파싱한다', () {
        final response = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': '''
[
  {"name": "참치,김밥", "imageUrl": "",},
]
''',
                  },
                ],
              },
            },
          ],
        };

        final result = GeminiResponseParser.parseRecommendations(response);

        expect(result.length, 1);
        expect(result[0].name, '참치,김밥');
      });

      test('텍스트가 없는 응답은 예외를 던진다', () {
        final response = {
          'candidates': [
            {
              'content': {
                'parts': [{}],
              },
            },
          ],
        };

        expect(
          () => GeminiResponseParser.parseRecommendations(response),
          throwsException,
        );
      });
    });

    group('extractListFromWrappedJson', () {
      test('일반 List를 그대로 반환한다', () {
        final input = ['a', 'b', 'c'];
        final result = GeminiResponseParser.extractListFromWrappedJson(input);
        expect(result, ['a', 'b', 'c']);
      });

      test('recommendations 키를 가진 Map에서 List를 추출한다', () {
        final input = {
          'recommendations': ['x', 'y'],
        };
        final result = GeminiResponseParser.extractListFromWrappedJson(input);
        expect(result, ['x', 'y']);
      });

      test('reviews 키를 가진 Map에서 List를 추출한다', () {
        final input = {
          'reviews': ['r1', 'r2'],
        };
        final result = GeminiResponseParser.extractListFromWrappedJson(input);
        expect(result, ['r1', 'r2']);
      });

      test('유효한 키가 없거나 List가 아니면 FormatException을 던진다', () {
        final input = {'invalid': 'value'};
        expect(
          () => GeminiResponseParser.extractListFromWrappedJson(input),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });

  group('FoodRecommendation', () {
    test('fromJson으로 생성된다', () {
      final json = {'name': '비빔밥', 'imageUrl': 'https://example.com/img.jpg'};
      final food = FoodRecommendation.fromJson(json);
      expect(food.name, '비빔밥');
      expect(food.imageUrl, 'https://example.com/img.jpg');
    });

    test('toJson으로 직렬화된다', () {
      const food = FoodRecommendation(
        name: '갈비탕',
        imageUrl: 'https://example.com/galbitang.jpg',
      );
      final json = food.toJson();
      expect(json['name'], '갈비탕');
      expect(json['imageUrl'], 'https://example.com/galbitang.jpg');
    });
  });
}
