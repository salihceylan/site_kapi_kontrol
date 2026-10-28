// P2-26: AppBar'daki belirgin "Yenile" eylemi. Yuvarlak, çerçeveli düz yüzey (soluk yüzey + 1 px kenar) olduğundan öteki
// çıplak simge düğmelerinden (tema, ayarlar) ayrışır; yenileme sürerken küçük bir ilerleme göstergesine dönüşür ve ikinci
// dokunuşu almaz. "Çıkış Yap" artık AppBar'da değildir (menünün dibinde, onaylı): yanlışlıkla çıkış olmaz.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/last_updated.dart';
import 'package:site_kapi_kontrol/ui/helpers/refresh_status.dart';

/// Dokunma hedefi >= 44 dp (öteki AppBar eylemleriyle aynı). Araç ipucu ve ekran okuyucu adı "Yenile"dir; yenileme
/// sürerken düğme pasiftir ve okuyucuya "Yenileniyor" denir, en son başarılı yenileme varsa "Son güncelleme 14:32" ipucu
/// eklenir. Ekran okuyucu tek düğüm okur (ad + durum + ipucu); simge ve ilerleme göstergesi dışlanır.
class RefreshActionButton extends StatelessWidget {
  const RefreshActionButton({super.key, required this.status, required this.onPressed});

  final RefreshStatus status;

  /// Yenilemeyi başlatır (çağıran [RefreshStatus.run] içinden geçirir).
  final VoidCallback onPressed;

  /// Düğmenin araç ipucu ve ekran okuyucu adı.
  static const String label = 'Yenile';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListenableBuilder(
      listenable: status,
      builder: (context, _) {
        final refreshing = status.refreshing;
        final last = status.lastRefreshedAt;
        final icon = refreshing
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: p.text),
              )
            : const Icon(Icons.refresh_rounded, size: 22);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          child: Semantics(
            container: true,
            button: true,
            enabled: !refreshing,
            label: label,
            value: refreshing ? 'Yenileniyor' : null,
            hint: refreshing || last == null ? null : formatLastUpdated(last),
            onTap: refreshing ? null : onPressed,
            excludeSemantics: true,
            child: IconButton(
              visualDensity: VisualDensity.standard,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: EdgeInsets.zero,
              tooltip: label,
              style: IconButton.styleFrom(
                backgroundColor: p.surfaceMuted,
                foregroundColor: p.text,
                disabledBackgroundColor: p.surfaceMuted,
                disabledForegroundColor: p.textSecondary,
                shape: CircleBorder(side: BorderSide(color: p.border)),
              ),
              icon: icon,
              onPressed: refreshing ? null : onPressed,
            ),
          ),
        );
      },
    );
  }
}
