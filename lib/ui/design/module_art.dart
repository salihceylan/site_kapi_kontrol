// Modül vitrini görselleri (Panel'deki modül kartları).
//
// Sözleşme: vitrin (Panel) ve görsel çalışması paralel yürür. [ModuleArtKind] değerleri, [ModuleArt]
// kurucusu ve [moduleArtAccent] imzası DEĞİŞMEZ; görsel çalışması yalnız bu dosyanın boyamasını değiştirir.
// Görsel dekoratiftir (anlamsal ağaçta yok): anlamı kartın başlığı taşır. Boyut sabit dp'dir, yazı ölçeğinden
// etkilenmez. Bu ilk sürüm yer tutucudur: yumuşak tonlu kare + çizgi ikon.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Vitrin kartı görsel türü. Bir modül ya da Panel'den açılan bir sayfa için.
enum ModuleArtKind {
  /// Kapı / Geçiş Kontrol (SmartKeyPass): kapı açma, kapı durumu.
  door,

  /// Kartlı geçiş.
  accessCards,

  /// Kişiler ve daireler (CRM).
  people,

  /// Duyurular.
  announcements,

  /// Aidat ve Finans (yönetici).
  finance,

  /// Borcum (sakin).
  myDebt,

  /// Belgeler.
  documents,

  /// İş takibi: arıza, bakım, talep.
  workTracking,

  /// Rezervasyon ve konsiyerj.
  reservation,

  /// Anket ve oylama.
  survey,

  /// Ziyaretçi ve kargo.
  visitor,

  /// Firma ve sözleşme takibi.
  contracts,

  /// Karar defteri / kararlar.
  decisions,

  /// Site yönetimi.
  sites,

  /// Modüller (açma, talep).
  modules,

  /// Cihazlar.
  devices,

  /// Kullanıcı yönetimi.
  users,

  /// Raporlar.
  reports,

  /// Ayarlar / platform ayarları.
  settings,

  /// Yardım ve destek.
  help,

  /// Eşleşmeyen her şey.
  generic,
}

/// Türün vurgu rengi (kart üst çizgisi, durum noktası). Açık ve koyu temada okunur tonlar.
Color moduleArtAccent(ModuleArtKind kind) {
  switch (kind) {
    case ModuleArtKind.door:
    case ModuleArtKind.accessCards:
    case ModuleArtKind.devices:
      return const Color(0xFF2563EB);
    case ModuleArtKind.finance:
    case ModuleArtKind.myDebt:
    case ModuleArtKind.reports:
      return const Color(0xFF059669);
    case ModuleArtKind.announcements:
    case ModuleArtKind.survey:
      return const Color(0xFFD97706);
    case ModuleArtKind.workTracking:
    case ModuleArtKind.visitor:
      return const Color(0xFFE11D48);
    case ModuleArtKind.reservation:
    case ModuleArtKind.decisions:
    case ModuleArtKind.contracts:
      return const Color(0xFF7C3AED);
    case ModuleArtKind.people:
    case ModuleArtKind.documents:
    case ModuleArtKind.sites:
    case ModuleArtKind.modules:
    case ModuleArtKind.users:
    case ModuleArtKind.settings:
    case ModuleArtKind.help:
    case ModuleArtKind.generic:
      return const Color(0xFF0F766E);
  }
}

IconData _iconFor(ModuleArtKind kind) {
  switch (kind) {
    case ModuleArtKind.door:
      return Icons.door_front_door_outlined;
    case ModuleArtKind.accessCards:
      return Icons.badge_outlined;
    case ModuleArtKind.people:
      return Icons.people_outline_rounded;
    case ModuleArtKind.announcements:
      return Icons.campaign_outlined;
    case ModuleArtKind.finance:
      return Icons.account_balance_wallet_outlined;
    case ModuleArtKind.myDebt:
      return Icons.receipt_long_outlined;
    case ModuleArtKind.documents:
      return Icons.folder_open_outlined;
    case ModuleArtKind.workTracking:
      return Icons.build_outlined;
    case ModuleArtKind.reservation:
      return Icons.event_available_outlined;
    case ModuleArtKind.survey:
      return Icons.how_to_vote_outlined;
    case ModuleArtKind.visitor:
      return Icons.local_shipping_outlined;
    case ModuleArtKind.contracts:
      return Icons.handshake_outlined;
    case ModuleArtKind.decisions:
      return Icons.gavel_outlined;
    case ModuleArtKind.sites:
      return Icons.apartment_outlined;
    case ModuleArtKind.modules:
      return Icons.widgets_outlined;
    case ModuleArtKind.devices:
      return Icons.router_outlined;
    case ModuleArtKind.users:
      return Icons.manage_accounts_outlined;
    case ModuleArtKind.reports:
      return Icons.insights_outlined;
    case ModuleArtKind.settings:
      return Icons.settings_outlined;
    case ModuleArtKind.help:
      return Icons.help_outline_rounded;
    case ModuleArtKind.generic:
      return Icons.grid_view_rounded;
  }
}

/// Modül kartı görseli. [size] kenar uzunluğu (dp), en az 32.
class ModuleArt extends StatelessWidget {
  const ModuleArt({super.key, required this.kind, this.size = 64})
      : assert(size >= 32, 'ModuleArt en az 32 dp olmalı');

  final ModuleArtKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = moduleArtAccent(kind);
    final tint = Color.alphaBlend(accent.withValues(alpha: palette.isDark ? 0.22 : 0.10), palette.surface);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: Icon(_iconFor(kind), size: size * 0.5, color: accent),
        ),
      ),
    );
  }
}
