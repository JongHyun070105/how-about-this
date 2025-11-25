import 'dart:io';
import 'package:dio/dio.dart';
import '../services/kakao_api_service.dart';

class ErrorHandler {
  static String sanitizeMessage(dynamic error) {
    if (error is DioException) {
      return _handleDioError(error);
    } else if (error is SocketException) {
      return '인터넷 연결을 확인해주세요.';
    } else if (error is KakaoApiException) {
      return error.message;
    } else {
      return '알 수 없는 오류가 발생했습니다.\n잠시 후 다시 시도해주세요.';
    }
  }

  static String _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '서버 응답 시간이 초과되었습니다.\n인터넷 연결을 확인하거나 잠시 후 다시 시도해주세요.';
      case DioExceptionType.connectionError:
        return '서버와 연결할 수 없습니다.\n인터넷 연결을 확인해주세요.';
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        if (statusCode == 401) {
          return '인증에 실패했습니다. 앱을 다시 시작해주세요.';
        } else if (statusCode == 403) {
          return '접근 권한이 없습니다.';
        } else if (statusCode == 429) {
          return '요청이 너무 많습니다. 잠시 후 다시 시도해주세요.';
        } else if (statusCode != null && statusCode >= 500) {
          return '서버에 문제가 발생했습니다.\n잠시 후 다시 시도해주세요.';
        }
        return '서버 오류가 발생했습니다. ($statusCode)';
      case DioExceptionType.cancel:
        return '요청이 취소되었습니다.';
      default:
        return '네트워크 오류가 발생했습니다.\n잠시 후 다시 시도해주세요.';
    }
  }
}
