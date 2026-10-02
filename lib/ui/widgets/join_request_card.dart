// FAZ 5 / A2-G4: "Katılım Başvurularım" liste kartı.
//
// Bireysel ana görünüm ile "Daireye Katıl & Cihaz Ekle" ekranı aynı kart kabuğunu paylaşır; iki ekranın
// ayrıntı satırları (blok/daire/not/gerekçe) birbirinden farklıdır ve birebir korunur: ayrıntılar
// çağıranın [details] listesidir.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Başvuru durumu: (etiket, ton).
typedef JoinRequestStatus = ({String label, AppTone tone});

/// Bir katılım başvurusu kartı: site adı + durum rozeti + ayrıntı satırları.
///
/// Durum rozeti site adının yanında (sığarsa) ya da altında durur (`Wrap`): ad kırpılmaz. Renk tek
/// başına anlam taşımaz (rozet metni de vardır). Üst öğe sınırlı genişlikte olmalıdır.
class JoinRequestCard extends StatelessWidget {
  const JoinRequestCard({
    super.key,
    required this.title,
    required this.status,
    this.details = const <Widget>[],
  });

  /// Durum: Onaylandı (success) / Reddedildi (danger) / Onay Bekliyor (warning).
  static JoinRequestStatus statusOf(JoinRequestRecord request) {
    if (request.isApproved) {
      return (label: 'Onaylandı', tone: AppTone.success);
    }
    if (request.isRejected) {
      return (label: 'Reddedildi', tone: AppTone.danger);
    }
    return (label: 'Onay Bekliyor', tone: AppTone.warning);
  }

  final String title;
  final JoinRequestStatus status;

  /// Başlığın altındaki ayrıntı satırları (her biri kendi metnini taşır).
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ExcludeSemantics(
              child: Icon(
                Icons.apartment_rounded,
                size: 20,
                color: AppTone.primary.ink(p),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          // Ayrıntılar başlıkla aynı hizada (ikonun sağında) akar.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title, style: th.titleMedium),
                    StatusChip(label: status.label, tone: status.tone),
                  ],
                ),
                for (final detail in details) ...[
                  const SizedBox(height: AppSpace.sm),
                  detail,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
