import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_ai/utils/responsive_helper.dart';
import 'package:review_ai/config/ui_constants.dart';

void main() {
  group('ResponsiveHelper Tests', () {
    testWidgets('태블릿 여부를 정확히 판단한다', (tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final responsive = context.responsive;
              // Assert - 태블릿 여부는 화면 크기에 따라 결정됨
              expect(responsive.isTablet, isA<bool>());
              if (responsive.screenWidth >= UiConstants.tabletMinWidth) {
                expect(responsive.isTablet, true);
              } else {
                expect(responsive.isTablet, false);
              }
              return Container();
            },
          ),
        ),
      );
    });

    testWidgets('폰트 크기 계산이 범위 내에 있다', (tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final responsive = context.responsive;

              // Act
              final fontSize = responsive.fontSize(
                mobileRatio: 0.05,
                tabletRatio: 0.03,
                min: 12.0,
                max: 28.0,
              );

              // Assert
              expect(fontSize, greaterThanOrEqualTo(12.0));
              expect(fontSize, lessThanOrEqualTo(28.0));
              return Container();
            },
          ),
        ),
      );
    });

    testWidgets('아이콘 크기 계산이 정상 작동한다', (tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final responsive = context.responsive;

              // Act
              final iconSize = responsive.iconSize();

              // Assert
              expect(iconSize, greaterThanOrEqualTo(UiConstants.iconSizeSmall));
              expect(iconSize, lessThanOrEqualTo(UiConstants.iconSizeLarge));
              return Container();
            },
          ),
        ),
      );
    });
  });

  group('ResponsiveExtension Tests', () {
    testWidgets('BuildContext 확장이 정상 작동한다', (tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              // Act & Assert
              expect(context.screenWidth, greaterThan(0));
              expect(context.screenHeight, greaterThan(0));
              expect(context.isTablet, isA<bool>());
              return Container();
            },
          ),
        ),
      );
    });
  });
}
