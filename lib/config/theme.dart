import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light() {
    return _buildLightTheme();
  }

  static ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      primaryColor: Colors.black,
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        secondary: Colors.blue,
        surface: Colors.white,
        error: Colors.red,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.black,
        onError: Colors.white,
      ),
      textTheme: _buildTextTheme(),
      appBarTheme: _buildAppBarTheme(),
      elevatedButtonTheme: _buildElevatedButtonTheme(),
      inputDecorationTheme: _buildInputDecorationTheme(),
      chipTheme: _buildChipTheme(),
      cardTheme: _buildCardTheme(),
      snackBarTheme: _buildSnackBarTheme(),
      dialogTheme: _buildDialogTheme(),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _buildTextTheme() {
    const fontFamily = 'SCDream';
    const textColor = Colors.black;
    return const TextTheme(
      displayLarge: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w300,
      ),
      displayMedium: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w400,
      ),
      displaySmall: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w500,
      ),
      headlineLarge: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w500,
      ),
      headlineMedium: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w500,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w500,
      ),
      titleLarge: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w500,
      ),
      titleMedium: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w500,
      ),
      titleSmall: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w400,
      ),
      bodyLarge: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w300,
      ),
      labelLarge: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w400,
      ),
      labelSmall: TextStyle(
        fontFamily: fontFamily,
        color: textColor,
        fontWeight: FontWeight.w300,
      ),
    );
  }

  static AppBarTheme _buildAppBarTheme() {
    return const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'SCDream',
        color: Colors.black,
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  static ElevatedButtonThemeData _buildElevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey,
        disabledForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          fontFamily: 'SCDream',
        ),
        elevation: 2,
        shadowColor: Colors.black26,
      ),
    );
  }

  static InputDecorationTheme _buildInputDecorationTheme() {
    return InputDecorationTheme(
      labelStyle: const TextStyle(
        color: Colors.black54,
        fontFamily: 'SCDream',
        fontWeight: FontWeight.w400,
      ),
      hintStyle: const TextStyle(
        color: Colors.black38,
        fontFamily: 'SCDream',
        fontWeight: FontWeight.w300,
      ),
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.red),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.red, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  static ChipThemeData _buildChipTheme() {
    return ChipThemeData(
      backgroundColor: const Color(0xFFF5F5F5),
      selectedColor: Colors.black,
      disabledColor: Colors.grey.shade300,
      labelStyle: const TextStyle(
        color: Colors.black,
        fontFamily: 'SCDream',
        fontWeight: FontWeight.w400,
      ),
      secondaryLabelStyle: const TextStyle(
        color: Colors.white,
        fontFamily: 'SCDream',
        fontWeight: FontWeight.w400,
      ),
      checkmarkColor: Colors.white,
      deleteIconColor: Colors.black54,
      brightness: Brightness.light,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
    );
  }

  static CardThemeData _buildCardTheme() {
    return CardThemeData(
      color: Colors.white,
      shadowColor: Colors.black12,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFF0F0F0)),
      ),
    );
  }

  static SnackBarThemeData _buildSnackBarTheme() {
    return SnackBarThemeData(
      backgroundColor: Colors.black87,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontFamily: 'SCDream',
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      actionTextColor: Colors.blue.shade300,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  static DialogThemeData _buildDialogTheme() {
    return DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: const TextStyle(
        color: Colors.black,
        fontFamily: 'SCDream',
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      contentTextStyle: const TextStyle(
        color: Colors.black87,
        fontFamily: 'SCDream',
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}
