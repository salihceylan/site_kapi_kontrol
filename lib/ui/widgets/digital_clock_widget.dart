import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/user_session.dart';
import '../../styles/app_colors.dart';
import '../../styles/role_theme.dart';

class DigitalClockWidget extends StatefulWidget {
  const DigitalClockWidget({
    super.key,
    required this.session,
    this.showUserInfo = true,
  });

  final UserSession session;
  final bool showUserInfo;

  @override
  State<DigitalClockWidget> createState() => _DigitalClockWidgetState();
}

class _DigitalClockWidgetState extends State<DigitalClockWidget> {
  late DateTime _currentTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTurkishDate(DateTime dt) {
    const days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar'
    ];
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık'
    ];

    final dayName = days[dt.weekday - 1];
    final monthName = months[dt.month - 1];
    return '${dt.day} $monthName ${dt.year}, $dayName';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roleColor = widget.session.role.accentColor;
    final timeStr = _formatTime(_currentTime);
    final dateStr = _formatTurkishDate(_currentTime);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E293B).withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: roleColor.withValues(alpha: isDark ? 0.35 : 0.3),
              width: 1.3,
            ),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: roleColor.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                    const BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ]
                : [
                    const BoxShadow(
                      color: Color(0x0F0F172A),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                    BoxShadow(
                      color: roleColor.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Üst Satır: Dijital Saat & Canlı Zaman Dilimi Rozeti
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Dijital Saat (Expanded + FittedBox ile taşmaya karşı tam koruma)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF38BDF8).withValues(alpha: 0.15)
                                    : AppColors.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.access_time_filled_rounded,
                                color: isDark ? const Color(0xFF38BDF8) : AppColors.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                fontFamily: 'monospace',
                                color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                                shadows: isDark
                                    ? const [
                                        Shadow(
                                          color: Color(0x8038BDF8),
                                          blurRadius: 12,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Canlı Saat Bölgesi Rozeti (FittedBox ile taşmaya karşı korumalı)
                  Flexible(
                    flex: 0,
                    fit: FlexFit.loose,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0284C7).withValues(alpha: 0.2)
                              : const Color(0xFF0284C7).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF38BDF8).withValues(alpha: 0.4)
                                : const Color(0xFF0284C7).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🇹🇷 ', style: TextStyle(fontSize: 11)),
                            Text(
                              'TSİ (UTC+3)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Tarih Satırı (Türkçe)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 13,
                    color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          dateStr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              if (widget.showUserInfo) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(
                    color: isDark ? const Color(0x1FFFFFFF) : const Color(0x150F172A),
                    height: 1,
                  ),
                ),
                // Kullanıcı Bilgisi ve Rolü (Taşma Korumalı)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: roleColor.withValues(alpha: isDark ? 0.15 : 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              color: roleColor,
                              size: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.session.fullName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 0,
                      fit: FlexFit.loose,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: isDark ? 0.15 : 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: roleColor.withValues(alpha: isDark ? 0.4 : 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield_outlined, color: roleColor, size: 13),
                              const SizedBox(width: 4),
                              Text(
                                widget.session.role.label,
                                style: TextStyle(
                                  color: roleColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
