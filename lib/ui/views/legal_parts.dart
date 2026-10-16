import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// AppBar başlığının en büyük yazı ölçeği: Material AppBar başlık yazısını en çok 1,34x'e kadar büyütür.
const double kAppBarTitleMaxScale = 1.34;

/// Sarabilen AppBar başlığının satır aralığı çarpanı (yazı tipinden bağımsız, belirli yükseklik).
const double kWrappedTitleLineHeight = 1.3;

/// Başlığı sarabilen AppBar'ın başlık stili: tema stili + belirli satır aralığı. Satır aralığı sabitlendiği
/// için [wrappedTitleToolbarHeight] hesabı her yazı tipinde (ve testte) birebir tutar.
TextStyle? wrappedTitleStyle(BuildContext context) {
  final theme = Theme.of(context);
  final base = theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge;
  return base?.copyWith(height: kWrappedTitleLineHeight);
}

/// Başlığı en çok [lines] satıra sarabilen AppBar için araç çubuğu yüksekliği ([wrappedTitleStyle] ile birlikte
/// kullanılır).
///
/// 56 dp'lik varsayılan çubuk büyük yazıda iki satırlık başlığı kırpar (başlık 18 sp x 1,34 x 1,3 satır
/// aralığı = ~31 dp/satır; iki satır ~63 dp). Yükseklik başlığın GERÇEK satır yüksekliğinden ([lines] satır +
/// dikey pay) hesaplanır ve normal yazıda 56 dp'nin altına inmez. Başlık [lines] satırdan sonra elips alır;
/// belgenin tam adı gövdede ayrıca yazılıdır.
double wrappedTitleToolbarHeight(BuildContext context, {int lines = 2}) {
  final fontSize = wrappedTitleStyle(context)?.fontSize ?? 18;
  final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: kAppBarTitleMaxScale);
  final lineHeight = scaler.scale(fontSize) * kWrappedTitleLineHeight;
  final needed = lines * lineHeight + AppSpace.sm;
  return needed > kToolbarHeight ? needed : kToolbarHeight;
}

/// Sunucu tarihini (`2026-10-16` ya da ISO) `16.10.2026` biçimine çevirir; çözülemezse null.
String? formatLegalDate(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw.trim());
  if (match == null) return null;
  return '${match.group(3)}.${match.group(2)}.${match.group(1)}';
}

/// Yükleme hatası bildirimi + "Yeniden dene" düğmesi. Hata "boş" gibi gösterilmez; düğme en az 48 dp,
/// yüklenirken devre dışıdır (çift dokunma ikinci istek göndermez).
class LegalRetryNotice extends StatelessWidget {
  const LegalRetryNotice({
    super.key,
    required this.message,
    required this.onRetry,
    this.busy = false,
    this.tone = AppTone.danger,
  });

  final String message;
  final VoidCallback? onRetry;

  /// true: yeniden deneme sürüyor (düğme pasif, etiket "Deneniyor...").
  final bool busy;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InlineNotice(message: message, tone: tone),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: busy ? null : onRetry,
            icon: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: p.textSecondary),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(busy ? 'Deneniyor...' : 'Yeniden dene'),
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 48),
              foregroundColor: tone.ink(p),
            ),
          ),
        ),
      ],
    );
  }
}
