import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Ekran okuyucuya kısa bir duyuru gönderir (nazik, mevcut konuşmayı kesmez). Odağı taşımayan durum
/// değişikliklerinde (başarı görünümüne geçiş, hız sınırı süresinin dolması, iptal sonrası kart değişimi)
/// kullanılır; canlı bölge (`liveRegion`) yeni eklenen düğümlerde güvenilir değildir. Hata yutulur
/// (duyuru yardımcı bir özelliktir; asla işlemi bozmaz).
void announcePolite(BuildContext context, String message) {
  if (!context.mounted || message.trim().isEmpty) return;
  try {
    final view = View.maybeOf(context);
    if (view == null) return;
    SemanticsService.sendAnnouncement(view, message, Directionality.of(context));
  } catch (_) {
    // Duyuru gönderilemedi: işlem etkilenmez.
  }
}
