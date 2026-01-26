import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/models/exceptions.dart';

void main() {
  group('ApiException', () {
    test('should create ApiException with message', () {
      final exception = ApiException('Something went wrong');

      expect(exception.message, 'Something went wrong');
      expect(exception.statusCode, isNull);
    });

    test('should create ApiException with message and status code', () {
      final exception = ApiException('Server error', statusCode: 500);

      expect(exception.message, 'Server error');
      expect(exception.statusCode, 500);
    });

    test('toString should return formatted string', () {
      final exception = ApiException('Not found', statusCode: 404);

      expect(exception.toString(), contains('ApiException'));
      expect(exception.toString(), contains('Not found'));
      expect(exception.toString(), contains('404'));
    });

    test('toString should handle null status code', () {
      final exception = ApiException('Error');

      expect(exception.toString(), contains('N/A'));
    });
  });

  group('NetworkException', () {
    test('should create NetworkException with message', () {
      final exception = NetworkException('Connection timeout');

      expect(exception.message, contains('네트워크 오류'));
      expect(exception.message, contains('Connection timeout'));
    });
  });

  group('GeminiApiException', () {
    test('should create GeminiApiException with message', () {
      final exception = GeminiApiException('Rate limit exceeded');

      expect(exception.message, contains('Gemini API 오류'));
      expect(exception.message, contains('Rate limit exceeded'));
    });

    test('should create GeminiApiException with status code', () {
      final exception = GeminiApiException('Forbidden', statusCode: 403);

      expect(exception.statusCode, 403);
    });
  });

  group('ParsingException', () {
    test('should create ParsingException with message', () {
      final exception = ParsingException('Invalid JSON');

      expect(exception.message, contains('데이터 파싱 오류'));
      expect(exception.message, contains('Invalid JSON'));
    });
  });

  group('ImageValidationException', () {
    test('should create ImageValidationException with message', () {
      final exception = ImageValidationException('Not a food image');

      expect(exception.message, 'Not a food image');
    });
  });
}
