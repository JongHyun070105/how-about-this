/// UI 관련 상수
class UiConstants {
  // 반응형 임계값
  static const double tabletMinWidth = 768.0;

  // 폰트 크기 비율
  static const double appBarFontRatioMobile = 0.05;
  static const double appBarFontRatioTablet = 0.032;
  static const double inputFontRatioMobile = 0.04;
  static const double inputFontRatioTablet = 0.024;

  // 최소/최대 폰트 크기
  static const double minFontSize = 12.0;
  static const double maxFontSize = 28.0;

  // 패딩/마진 비율
  static const double horizontalPaddingRatioMobile = 0.04;
  static const double horizontalPaddingRatioTablet = 0.06;
  static const double verticalSpacingRatioMobile = 0.02;
  static const double verticalSpacingRatioTablet = 0.025;

  // 아이콘 크기
  static const double iconSizeSmall = 16.0;
  static const double iconSizeMedium = 20.0;
  static const double iconSizeLarge = 24.0;

  // 애니메이션 지속 시간
  static const Duration shortAnimation = Duration(milliseconds: 300);
  static const Duration mediumAnimation = Duration(milliseconds: 500);
  static const Duration longAnimation = Duration(milliseconds: 800);

  // 스낵바 지속 시간
  static const Duration snackBarShort = Duration(seconds: 2);
  static const Duration snackBarMedium = Duration(seconds: 3);
  static const Duration snackBarLong = Duration(seconds: 4);

  // 이미지 제한
  static const int maxImageSizeMB = 10;
  static const int imageQuality = 90;
  static const double maxImageDimension = 1200.0;
}
