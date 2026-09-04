import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';

extension UserRoleTheme on UserRole {
  Color get accentColor {
    switch (this) {
      case UserRole.superUser:
        return const Color(0xFF3B82F6); // Electric Sapphire
      case UserRole.siteManager:
        return const Color(0xFF10B981); // Emerald Neon
      case UserRole.apartmentOwner:
        return const Color(0xFFA855F7); // Amethyst Purple
    }
  }

  Color get lightAccentColor {
    switch (this) {
      case UserRole.superUser:
        return const Color(0xFF60A5FA);
      case UserRole.siteManager:
        return const Color(0xFF34D399);
      case UserRole.apartmentOwner:
        return const Color(0xFFC084FC);
    }
  }

  Color get surfaceColor {
    switch (this) {
      case UserRole.superUser:
        return const Color(0xFF172554); // Deep Navy Slate
      case UserRole.siteManager:
        return const Color(0xFF064E3B); // Deep Emerald Slate
      case UserRole.apartmentOwner:
        return const Color(0xFF3B0764); // Deep Purple Slate
    }
  }

  LinearGradient get gradient {
    return LinearGradient(
      colors: [accentColor, lightAccentColor],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}
