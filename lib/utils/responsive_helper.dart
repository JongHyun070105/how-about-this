import 'package:flutter/material.dart';
import '../config/ui_constants.dart';

/// 반응형 UI 헬퍼
class ResponsiveHelper {
  final BuildContext context;

  ResponsiveHelper(this.context);

  /// 화면 너비
  double get screenWidth => MediaQuery.of(context).size.width;

  /// 화면 높이
  double get screenHeight => MediaQuery.of(context).size.height;

  /// 태블릿 여부
  bool get isTablet => screenWidth >= UiConstants.tabletMinWidth;

  /// 폰트 크기 계산 (비율 기반)
  double fontSize({
    required double mobileRatio,
    required double tabletRatio,
    double min = UiConstants.minFontSize,
    double max = UiConstants.maxFontSize,
  }) {
    final ratio = isTablet ? tabletRatio : mobileRatio;
    return (screenWidth * ratio).clamp(min, max);
  }

  /// 앱바 폰트 크기
  double get appBarFontSize => fontSize(
    mobileRatio: UiConstants.appBarFontRatioMobile,
    tabletRatio: UiConstants.appBarFontRatioTablet,
  );

  /// 입력 폰트 크기
  double get inputFontSize => fontSize(
    mobileRatio: UiConstants.inputFontRatioMobile,
    tabletRatio: UiConstants.inputFontRatioTablet,
  );

  /// 수평 패딩
  double get horizontalPadding {
    final ratio = isTablet
        ? UiConstants.horizontalPaddingRatioTablet
        : UiConstants.horizontalPaddingRatioMobile;
    return (screenWidth * ratio).clamp(16.0, 48.0);
  }

  /// 수직 간격
  double get verticalSpacing {
    final ratio = isTablet
        ? UiConstants.verticalSpacingRatioTablet
        : UiConstants.verticalSpacingRatioMobile;
    return (screenHeight * ratio).clamp(12.0, 24.0);
  }

  /// 너비 비율 계산
  double widthRatio(double ratio) => screenWidth * ratio;

  /// 높이 비율 계산
  double heightRatio(double ratio) => screenHeight * ratio;

  /// 아이콘 크기 계산
  double iconSize({
    double mobileRatio = 0.05,
    double tabletRatio = 0.032,
    double min = UiConstants.iconSizeSmall,
    double max = UiConstants.iconSizeLarge,
  }) {
    final ratio = isTablet ? tabletRatio : mobileRatio;
    return (screenWidth * ratio).clamp(min, max);
  }
}

/// BuildContext 확장 메서드
extension ResponsiveExtension on BuildContext {
  ResponsiveHelper get responsive => ResponsiveHelper(this);

  bool get isTablet =>
      MediaQuery.of(this).size.width >= UiConstants.tabletMinWidth;

  double get screenWidth => MediaQuery.of(this).size.width;

  double get screenHeight => MediaQuery.of(this).size.height;
}
