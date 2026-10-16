// FAZ 5 / A1b-(iii): başarı / hata / uyarı / bilgi SnackBar'ı.
//
// ~40 elle yazılmış `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` çağrısının yerine
// geçer. Mesaj, süre ve davranış AYNIDIR (varsayılan 4 sn, floating, kuyruğa girer); yalnız görünüm
// tasarım sistemine bağlanır: simge + tonlu dolgu (beyaz metin >= 4,5:1), `AppRadius.md` köşe.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// [AppSnack] türü. Renk tek başına anlam taşımaz: her türün simgesi de farklıdır.
enum AppSnackKind {
  /// Nötr bilgi: tema SnackBar rengi (mevcut davranış).
  info,

  /// Başarı: `AppTone.success` koyu ucu. Eski `AppColors.emerald|success` yerine.
  success,

  /// Uyarı: `AppTone.warning` koyu ucu. Eski `AppColors.amber` yerine.
  warning,

  /// Hata: `AppTone.danger` koyu ucu. Eski `AppColors.rose|error` / `Color(0xFFDC2626)` yerine.
  error,
}

/// Tek satırlık SnackBar gösterici.
abstract final class AppSnack {
  /// Varsayılan görünme süresi (mevcut `SnackBar` varsayılanıyla aynı).
  static const Duration defaultDuration = Duration(seconds: 4);

  /// [message]'ı en yakın [ScaffoldMessenger]'da gösterir; messenger yoksa sessizce hiçbir şey yapmaz.
  ///
  /// - [kind]: simge ve tonlu dolgu. [AppSnackKind.info] tema rengini kullanır.
  /// - [duration]: verilmezse [defaultDuration].
  /// - [action]: verilirse etiket rengi (belirtilmemişse) tonlu dolguda okunur beyaz olur.
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
    final (Color? background, IconData icon) = switch (kind) {
      AppSnackKind.success => (AppTone.success.b, Icons.check_circle_rounded),
      AppSnackKind.warning => (AppTone.warning.b, Icons.warning_amber_rounded),
      AppSnackKind.error => (AppTone.danger.b, Icons.error_rounded),
      AppSnackKind.info => (null, Icons.info_rounded),
    };
    final p = context.palette;
    // Koyu temada tema rengi (info) sayfa zeminine yakın: ince kenar çizgisi ayırır (tema da öyle).
    final side = kind == AppSnackKind.info && p.isDark
        ? BorderSide(color: p.border)
        : BorderSide.none;
    return SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: background,
      duration: duration ?? defaultDuration,
      persist: persist,
      action: action == null || background == null
          ? action
          : _readableAction(action),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: side,
      ),
      content: Row(
        children: <Widget>[
          // İkon yarı saydam "cam" daire rozet içinde (premium dokunuş; anlamsal ağaçta yok).
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xs),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
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

  /// Tonlu (koyu) dolguda varsayılan eylem rengi okunmayabilir: rengi belirtilmemiş eylem beyaz olur.
  static SnackBarAction _readableAction(SnackBarAction action) {
    if (action.textColor != null) return action;
    return SnackBarAction(
      key: action.key,
      label: action.label,
      onPressed: action.onPressed,
      textColor: Colors.white,
      disabledTextColor: action.disabledTextColor,
      backgroundColor: action.backgroundColor,
      disabledBackgroundColor: action.disabledBackgroundColor,
    );
  }
}
