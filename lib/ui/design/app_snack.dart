// FAZ 5 / A1b-(iii): başarı / hata / uyarı / bilgi SnackBar'ı.
//
// ~40 elle yazılmış `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` çağrısının yerine
// geçer. Mesaj, süre ve davranış AYNIDIR (varsayılan 4 sn, floating, kuyruğa girer); yalnız görünüm
// tasarım sistemine bağlanır. Sade stil (İP-1C, karar G6 + G7): her tür TEK koyu yüzeydedir (tema rengi: açıkta
// kritik uyarı rengi #0F172A, koyuda #1E293B + ince kenar); tür, simgesi ve simgenin rengiyle ayrılır (zemin
// boyanmaz). Beyaz metin >= 4,5:1, simgeler >= 4,5:1; `AppRadius.md` köşe.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// [AppSnack] türü. Renk tek başına anlam taşımaz: her türün simgesi de farklıdır.
enum AppSnackKind {
  /// Nötr bilgi: beyaz simge.
  info,

  /// Başarı: `AppTone.success` açık ink'li simge (#6EE7B7).
  success,

  /// Uyarı: `AppTone.warning` açık ink'li simge (#FCD34D).
  warning,

  /// Hata: `AppTone.danger` açık ink'li simge (#FDA4AF).
  error,
}

/// Tek satırlık SnackBar gösterici.
abstract final class AppSnack {
  /// Varsayılan görünme süresi (mevcut `SnackBar` varsayılanıyla aynı).
  static const Duration defaultDuration = Duration(seconds: 4);

  /// [message]'ı en yakın [ScaffoldMessenger]'da gösterir; messenger yoksa sessizce hiçbir şey yapmaz.
  ///
  /// - [kind]: simge ve simge rengi; dolgu her türde tema rengidir.
  /// - [duration]: verilmezse [defaultDuration].
  /// - [action]: etiket rengi belirtilmemişse temanın eylem rengini alır (koyu yüzeyde okunur bağlantı mavisi).
  /// - [replace]: false (varsayılan) iken mevcut kuyruklama davranışı değişmez (mesaj sıraya girer);
  ///   true iken ekrandaki SnackBar HEMEN kaldırılır, sıradakiler atılır ve bu mesaj hemen gösterilir.
  /// - [persist]: null (varsayılan) iken Flutter'ın kuralı geçerlidir: [action] varsa SnackBar süre dolsa da
  ///   KALIR (kullanıcı dokunana dek) ve sıradaki mesajları engeller. Süresi dolunca kapanması gereken
  ///   eylemli SnackBar için `false` verin.
  /// - [semanticsLabel]: ekran okuyucunun metin yerine okuyacağı etiket (örn. tutarın "bin iki yüz elli lira"
  ///   okunuşu); verilmezse görsel metin okunur.
  /// - [maxLines]: çok uzun metni sınırlar (varsayılan 4); ekran okuyucu her zaman TAM metni okur.
  ///   Uzun bir cümleyi (örn. 140 karakter) büyük yazıda kısaltmak istemeyen çağıran artırabilir.
  ///
  /// Hareket azaltma: SnackBar'ın yerleşik animasyonu kullanılır (ekran okuyucu açıkken çerçeve kendi
  /// içinde anında geçer). `snackBarAnimationStyle` bilinçli KULLANILMAZ: süre değişince
  /// `ScaffoldMessenger` ortak denetleyiciyi yeniden yaratır (görünen SnackBar'ın animasyonunu keser).
  ///
  /// Dikkat: `context`'i `await` sonrasında kullanıyorsanız önce `mounted` kontrolü yapın.
  static void show(
    BuildContext context,
    String message, {
    AppSnackKind kind = AppSnackKind.info,
    Duration? duration,
    SnackBarAction? action,
    bool replace = false,
    bool? persist,
    int maxLines = 4,
    String? semanticsLabel,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final snackBar = _build(
      context,
      message,
      kind: kind,
      duration: duration,
      action: action,
      persist: persist,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
    );
    if (replace) {
      messenger.clearSnackBars();
      messenger.removeCurrentSnackBar();
    }
    messenger.showSnackBar(snackBar);
  }

  static SnackBar _build(
    BuildContext context,
    String message, {
    required AppSnackKind kind,
    required Duration? duration,
    required SnackBarAction? action,
    required bool? persist,
    required int maxLines,
    required String? semanticsLabel,
  }) {
    // Simge rengi: koyu yüzeyde tonun açık ink'i (>= 4,5:1); bilgi beyaz. Dolgu her türde tema rengidir.
    final (Color iconColor, IconData icon) = switch (kind) {
      AppSnackKind.success => (AppTone.success.inkDark, Icons.check_circle_rounded),
      AppSnackKind.warning => (AppTone.warning.inkDark, Icons.warning_amber_rounded),
      AppSnackKind.error => (AppTone.danger.inkDark, Icons.error_rounded),
      AppSnackKind.info => (Colors.white, Icons.info_rounded),
    };
    final p = context.palette;
    // Koyu temada tema rengi sayfa zeminine yakın: ince kenar çizgisi ayırır (tema da öyle).
    final side = p.isDark ? BorderSide(color: p.border) : BorderSide.none;
    return SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: duration ?? defaultDuration,
      persist: persist,
      action: action,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: side,
      ),
      content: Row(
        children: <Widget>[
          // Simge doğrudan çizilir (sade stil: rozet yok); anlamsal ağaçta yok, anlam metindedir.
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xs),
              child: Icon(icon, color: iconColor, size: 20),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              message,
              semanticsLabel: semanticsLabel,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
