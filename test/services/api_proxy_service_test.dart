import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:review_ai/services/api_proxy_service.dart';
import 'package:review_ai/core/exceptions.dart';

void main() {
  group('ApiProxyService', () {
    group('generateContent', () {
      test('성공적인 200 응답 시 JSON 데이터 반환', () async {
        final responseData = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'test response'},
                ],
              },
            },
          ],
        };

        final mockClient = http_testing.MockClient((request) async {
          expect(request.url.path, contains('/api/gemini-proxy'));
          expect(request.headers['Authorization'], startsWith('Bearer '));
          return http.Response(
            jsonEncode(responseData),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final service = ApiProxyService(
          mockClient,
          'https://test-proxy.example.com',
          tokenProvider: () async => 'test-token-123',
        );

        final result = await service.generateContent('test prompt');
        expect(result, isA<Map<String, dynamic>>());
        expect(result['candidates'], isNotNull);
        expect(result['candidates'], isList);
      });

      test('500 에러 시 GeminiApiException 발생', () async {
        final mockClient = http_testing.MockClient((request) async {
          return http.Response(
            'Internal Server Error',
            500,
            headers: {'content-type': 'text/plain'},
          );
        });

        final service = ApiProxyService(
          mockClient,
          'https://test-proxy.example.com',
          tokenProvider: () async => 'test-token-123',
        );

        expect(
          () => service.generateContent('test'),
          throwsA(isA<ApiException>()),
        );
      });

      test('429 Rate limit 에러 시 서버에서 반환한 JSON 에러 메시지를 보존하여 전달한다', () async {
        final mockClient = http_testing.MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': 'Too many requests',
              'message': 'Rate limit exceeded. Please try again later.',
            }),
            429,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = ApiProxyService(
          mockClient,
          'https://test-proxy.example.com',
          tokenProvider: () async => 'test-token-123',
        );

        expect(
          () => service.generateContent('test'),
          throwsA(
            isA<GeminiApiException>().having(
              (e) => e.message,
              'message',
              contains('Rate limit exceeded'),
            ),
          ),
        );
      });

      test('evictImage 호출 시 예외 없이 이미지 캐시를 해제한다', () {
        ApiProxyService.clearImageCache();
        ApiProxyService.evictImage('/tmp/test_image.jpg');
      });

      test('Authorization 헤더에 Bearer 토큰 포함', () async {
        String? capturedAuth;

        final mockClient = http_testing.MockClient((request) async {
          capturedAuth = request.headers['Authorization'];
          return http.Response(
            jsonEncode({'candidates': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = ApiProxyService(
          mockClient,
          'https://test-proxy.example.com',
          tokenProvider: () async => 'my-secret-token',
        );

        try {
          await service.generateContent('test');
        } catch (_) {}

        expect(capturedAuth, 'Bearer my-secret-token');
      });

      test('요청 본문에 endpoint와 requestBody 포함', () async {
        Map<String, dynamic>? capturedBody;

        final mockClient = http_testing.MockClient((request) async {
          capturedBody = jsonDecode(request.body);
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'ok'},
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final service = ApiProxyService(
          mockClient,
          'https://test-proxy.example.com',
          tokenProvider: () async => 'test-token',
        );

        await service.generateContent('my prompt');

        expect(capturedBody, isNotNull);
        expect(capturedBody!['endpoint'], 'generateContent');
        expect(capturedBody!['requestBody'], isA<Map>());
      });
    });

    group('generateReviews', () {
      test('빈 candidates 시 ParsingException 발생', () async {
        final mockClient = http_testing.MockClient((request) async {
          return http.Response(
            jsonEncode({'candidates': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = ApiProxyService(
          mockClient,
          'https://test-proxy.example.com',
          tokenProvider: () async => 'test-token-123',
        );

        expect(
          () => service.generateReviews(
            foodName: 'food',
            deliveryRating: 4.5,
            tasteRating: 4.0,
            portionRating: 3.5,
            priceRating: 3.0,
            reviewStyle: 'serious',
          ),
          throwsA(isA<ParsingException>()),
        );
      });

      test('유효한 JSON 배열 응답에서 리뷰 목록 반환', () async {
        final mockClient = http_testing.MockClient((request) async {
          final responseJson = jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '["Review 1", "Review 2", "Review 3"]'},
                  ],
                },
              },
            ],
          });
          return http.Response.bytes(
            utf8.encode(responseJson),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final service = ApiProxyService(
          mockClient,
          'https://test-proxy.example.com',
          tokenProvider: () async => 'test-token-123',
        );

        final reviews = await service.generateReviews(
          foodName: 'food',
          deliveryRating: 4.5,
          tasteRating: 4.0,
          portionRating: 3.5,
          priceRating: 3.0,
          reviewStyle: 'serious',
        );

        expect(reviews, isA<List<String>>());
        expect(reviews.length, 3);
      });

      test('json 코드블록 래핑 응답도 정상 파싱', () async {
        final mockClient = http_testing.MockClient((request) async {
          final responseJson = jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '```json\n["R1", "R2", "R3"]\n```'},
                  ],
                },
              },
            ],
          });
          return http.Response.bytes(
            utf8.encode(responseJson),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final service = ApiProxyService(
          mockClient,
          'https://test-proxy.example.com',
          tokenProvider: () async => 'test-token-123',
        );

        final reviews = await service.generateReviews(
          foodName: 'food',
          deliveryRating: 4.0,
          tasteRating: 4.0,
          portionRating: 4.0,
          priceRating: 4.0,
          reviewStyle: 'humorous',
        );

        expect(reviews.length, 3);
      });

      test('객체 래핑 응답도 정상 파싱', () async {
        final mockClient = http_testing.MockClient((request) async {
          final responseJson = jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '{"reviews": ["R1", "R2", "R3"]}'},
                  ],
                },
              },
            ],
          });
          return http.Response.bytes(
            utf8.encode(responseJson),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final service = ApiProxyService(
          mockClient,
          'https://test-proxy.example.com',
          tokenProvider: () async => 'test-token-123',
        );

        final reviews = await service.generateReviews(
          foodName: 'food',
          deliveryRating: 4.0,
          tasteRating: 4.0,
          portionRating: 4.0,
          priceRating: 4.0,
          reviewStyle: 'humorous',
        );

        expect(reviews, ['R1', 'R2', 'R3']);
      });
    });

    group('프록시 URL 검증', () {
      test('올바른 프록시 URL로 요청', () async {
        Uri? capturedUrl;

        final mockClient = http_testing.MockClient((request) async {
          capturedUrl = request.url;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'ok'},
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final service = ApiProxyService(
          mockClient,
          'https://my-proxy.workers.dev',
          tokenProvider: () async => 'token',
        );

        await service.generateContent('test');

        expect(
          capturedUrl.toString(),
          'https://my-proxy.workers.dev/api/gemini-proxy',
        );
      });
    });
  });
}
