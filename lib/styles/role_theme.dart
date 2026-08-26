import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

extension UserRoleTheme on UserRole {
  Color get accentColor {
    switch (this) {
      case UserRole.superUser:
        return AppColors.primary;
      case UserRole.siteManager:
        return const Color(0xFF00695C);
      case UserRole.apartmentOwner:
        return const Color(0xFF6A1B9A);
    }
  }

  Color get lightAccentColor {
    switch (this) {
      case UserRole.superUser:
        return AppColors.primaryLight;
      case UserRole.siteManager:
        return const Color(0xFF26A69A);
      case UserRole.apartmentOwner:
        return const Color(0xFF8E24AA);
    }
  }

  Color get surfaceColor {
    switch (this) {
      case UserRole.superUser:
        return const Color(0xFFE7F4FF);
      case UserRole.siteManager:
        return const Color(0xFFE3F5F1);
      case UserRole.apartmentOwner:
        return const Color(0xFFF4E8FA);
    }
  }
}
