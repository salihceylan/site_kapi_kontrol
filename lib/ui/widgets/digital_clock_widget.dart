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
    final roleColor = widget.session.role.accentColor;
    final timeStr = _formatTime(_currentTime);
    final dateStr = _formatTurkishDate(_currentTime);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: roleColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: roleColor.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          const BoxShadow(
            color: Color(0x40000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst Satır: Dijital Saat & Canlı Zaman Dilimi Rozeti
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Dijital Saat (Geniş Monospace Tipografi)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Icon(
                    Icons.access_time_filled_rounded,
                    color: Color(0xFF38BDF8),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                      fontFamily: 'monospace',
                      color: Color(0xFFF8FAFC),
                      shadows: [
                        Shadow(
                          color: Color(0x8038BDF8),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Canlı Saat Bölgesi Rozeti
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🇹🇷 ', style: TextStyle(fontSize: 12)),
                    Text(
                      'TSİ (UTC+3)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF38BDF8),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Tarih Satırı (Türkçe)
          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 15,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFCBD5E1),
                ),
              ),
            ],
          ),

          if (widget.showUserInfo) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(color: Color(0x20FFFFFF), height: 1),
            ),
            // Kullanıcı Bilgisi ve Rolü
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.session.fullName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF8FAFC),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: roleColor.withValues(alpha: 0.15),
                  side: BorderSide(color: roleColor.withValues(alpha: 0.45)),
                  avatar: Icon(Icons.verified_user_outlined, color: roleColor, size: 16),
                  label: Text(
                    widget.session.role.label,
                    style: TextStyle(
                      color: roleColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
