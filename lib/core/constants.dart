import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color background = Color(0xFFf8fafc);
  static const Color primaryText = Color(0xFF0f172a);
  static const Color secondaryText = Color(0xFF64748b);
  
  static const Color brandTeal = Color(0xFF0f766e);
  static const Color brandTealDark = Color(0xFF115e59);
  
  static const Color border = Color(0xFFe2e8f0);
  
  static const Color onlineBadgeBg = Color(0xFFdcfce7);
  static const Color onlineBadgeText = Color(0xFF15803d);
  static const Color onlineCardBg = Color(0xFFecfdf5);
  static const Color onlineCardBorder = Color(0xFFa7f3d0);
  static const Color onlineIconBg = Color(0xFFd1fae5);
  static const Color onlineIconText = Color(0xFF047857);
  
  static const Color offlineBadgeBg = Color(0xFFfee2e2);
  static const Color offlineBadgeText = Color(0xFFb91c1c);
  static const Color offlineCardBg = Color(0xFFfff1f2);
  static const Color offlineCardBorder = Color(0xFFfecdd3);
  static const Color offlineIconBg = Color(0xFFffe4e6);
  static const Color offlineIconText = Color(0xFFbe123c);
  
  static const Color checkingBadgeBg = Color(0xFFf1f5f9);
  
  static const Color syncCountBg = Color(0xFFfff7ed);
  static const Color syncCountText = Color(0xFFc2410c);
  static const Color syncPendingText = Color(0xFFb45309);
  
  static const Color cardBg = Color(0xFFffffff);
  
  static const Color actionIconBg = Color(0xFFf0fdfa);
}

class AppStyles {
  static ThemeData get theme {
    return ThemeData(
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.brandTeal,
      textTheme: GoogleFonts.interTextTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.primaryText),
        titleTextStyle: TextStyle(
          color: AppColors.primaryText,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
