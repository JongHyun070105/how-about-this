/// API 호출 관련 기본 예외 클래스
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      'ApiException: $message (Status Code: ${statusCode ?? 'N/A'})';
}

/// 네트워크 연결 실패 시 발생하는 예외
class NetworkException extends ApiException {
  NetworkException(String message) : super('네트워크 오류: $message');
}

/// Gemini API에서 200이 아닌 응답을 받았을 때 발생하는 예외
class GeminiApiException extends ApiException {
  GeminiApiException(String message, {int? statusCode})
    : super('Gemini API 오류: $message', statusCode: statusCode);
}

/// API 응답 파싱 실패 시 발생하는 예외
class ParsingException extends ApiException {
  ParsingException(String message) : super('데이터 파싱 오류: $message');
}

/// 이미지 유효성 검사 실패 시 발생하는 예외
class ImageValidationException extends ApiException {
  ImageValidationException(super.message);
}
