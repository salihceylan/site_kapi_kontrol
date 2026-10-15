import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Geçiş Kontrol (`door_control`) modülü kullanıcının bağlı olduğu TÜM sitelerde kapalıyken Panel'de
/// kapı kartları yerine gösterilen bilgi kartı.
///
/// [onOpenModules] verilirse (site yöneticisi, süper kullanıcı) "Modüller Ekranını Aç" düğmesi
/// gösterilir; sakin ve diğer rollerde yalnız bilgi vardır (modülü site yöneticisi açar).
///
/// [compact] true ise kapı dışı bölümleri olan ekranların (bireysel ana ekran) en üstünde durmak
/// üzere tek satırlık kısa bir bilgi kutusu çizilir.
class DoorControlDisabledCard extends StatelessWidget {
  const DoorControlDisabledCard({
    super.key,
    this.onOpenModules,
    this.compact = false,
  });

  final VoidCallback? onOpenModules;
  final bool compact;

  /// Başlık (sözleşmedeki metin).
  static const String title = 'Geçiş Kontrol modülü kapalı';

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const InlineNotice(
        tone: AppTone.warning,
        icon: Icons.lock_outline_rounded,
        message:
            'Geçiş Kontrol modülü kapalı: telefondan kapı açma, QR ve misafir geçişi şu an kapalı.',
      );
    }
    final canManage = onOpenModules != null;
    return EmptyCard(
      icon: Icons.lock_outline_rounded,
      tone: AppTone.warning,
      title: title,
      message: canManage
          ? 'Telefondan kapı açma, QR ve misafir geçişi bu sitede şu an kapalı. '
                'Modüller ekranından yeniden açabilirsiniz.'
          : 'Telefondan kapı açma, QR ve misafir geçişi şu an kapalı. '
                'Site yöneticisi Modüller ekranından açabilir.',
      child: canManage
          ? PrimaryActionButton(
              label: 'Modüller Ekranını Aç',
              icon: Icons.extension_rounded,
              variant: AppButtonVariant.tonal,
              tone: AppTone.warning,
              onPressed: onOpenModules,
            )
          : null,
    );
  }
}
