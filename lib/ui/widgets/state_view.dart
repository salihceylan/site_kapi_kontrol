// P2-21: boş / hata / bağlı değil üçlüsü, liste ve bölüm durumlarının TEK ortak bileşeni.
//
// Üç durum, üç ayrı görünüm (anlam rengin yanında ikon + metindedir):
// - boş: nötr ikon rozeti + başlık (+ mesaj, + eylem): "Henüz duyuru yok." Kayıt yok, sorun yok.
// - hata: mercan ikon + sunucunun / hizmetin mesajı + "Tekrar Dene". Sunucu yanıt verdi ama istek olmadı.
// - bağlı değil: kehribar bulut-yok ikonu + "Sunucuya ulaşılamıyor" + "Tekrar Dene". İnternet / DNS / zaman aşımı /
//   502-504: kullanıcının yapacağı bir şey yok, bağlantı gelince yeniden denemesi yeter. Hata DEĞİLDİR, korkutmaz.
//
// Satır içi (varsayılan) görünüm mevcut liste desenlerinin ([EmptyCard], [InlineNotice]) aynısıdır: listeler ve ekran
// testleri o tiplere bağlıdır. [StateView.prominent] ekranın tamamını kaplayan durumlar için ortalanmış büyük rozetli
// düzendir ([EmptyState]).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/last_updated.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// [StateView] türü.
enum StateViewKind {
  /// Kayıt yok.
  empty,

  /// Sunucu yanıt verdi ama istek tamamlanamadı.
  error,

  /// Sunucuya ulaşılamıyor (internet yok, zaman aşımı, 502-504).
  offline,
}

class StateView extends StatelessWidget {
  const StateView._({
    super.key,
    required this.kind,
    required this.icon,
    required this.tone,
    required this.title,
    this.message,
    this.onRetry,
    this.action,
    this.lastUpdated,
    this.prominent = false,
  });

  /// Boş durum: [icon] rozeti + [title] (+ [message]). [action] metnin altına konur (ör. "Excel'den yükle");
  /// satır içi görünümde kartın içinde, [prominent] görünümde yok sayılır (tam ekranda eylemi çağıran verir).
  const StateView.empty({
    Key? key,
    required IconData icon,
    required String title,
    String? message,
    AppTone tone = AppTone.primary,
    Widget? action,
    bool prominent = false,
  }) : this._(
         key: key,
         kind: StateViewKind.empty,
         icon: icon,
         tone: tone,
         title: title,
         message: message,
         action: action,
         prominent: prominent,
       );

  /// Hata: [message] sunucunun / hizmetin kullanıcı metnidir (olduğu gibi gösterilir). [onRetry] verilirse
  /// "Tekrar Dene" çıkar. [lastUpdated]: ekranda eski kayıtlar duruyorsa en son başarılı güncellemenin anı.
  const StateView.error({
    Key? key,
    required String message,
    VoidCallback? onRetry,
    DateTime? lastUpdated,
    String title = errorTitle,
    bool prominent = false,
  }) : this._(
         key: key,
         kind: StateViewKind.error,
         icon: Icons.error_outline_rounded,
         tone: AppTone.danger,
         title: title,
         message: message,
         onRetry: onRetry,
         lastUpdated: lastUpdated,
         prominent: prominent,
       );

  /// Bağlı değil: sunucuya ulaşılamıyor. [message] verilmezse standart metin ([offlineMessage]).
  const StateView.offline({
    Key? key,
    String message = offlineMessage,
    VoidCallback? onRetry,
    DateTime? lastUpdated,
    bool prominent = false,
  }) : this._(
         key: key,
         kind: StateViewKind.offline,
         icon: Icons.cloud_off_rounded,
         tone: AppTone.warning,
         title: offlineTitle,
         message: message,
         onRetry: onRetry,
         lastUpdated: lastUpdated,
         prominent: prominent,
       );

  /// Yükleyicinin hatası: [offline] doğruysa "bağlı değil", değilse "hata" ([PagedLoader.errorOffline]).
  factory StateView.failure({
    Key? key,
    required String message,
    required bool offline,
    VoidCallback? onRetry,
    DateTime? lastUpdated,
    bool prominent = false,
  }) => offline
      ? StateView.offline(
          key: key,
          message: message,
          onRetry: onRetry,
          lastUpdated: lastUpdated,
          prominent: prominent,
        )
      : StateView.error(
          key: key,
          message: message,
          onRetry: onRetry,
          lastUpdated: lastUpdated,
          prominent: prominent,
        );

  /// Standart "bağlı değil" metni.
  static const String offlineMessage = 'Sunucuya ulaşılamıyor. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  /// Tam ekran görünümde başlıklar (satır içi görünümde mesaj tek başına gösterilir).
  static const String errorTitle = 'Bir sorun oluştu';
  static const String offlineTitle = 'Sunucuya ulaşılamıyor';

  final StateViewKind kind;
  final IconData icon;
  final AppTone tone;
  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final Widget? action;

  /// Eski kayıtlar ekranda duruyorsa son başarılı güncellemenin anı; hata / bağlı değil bildiriminin altına yazılır.
  final DateTime? lastUpdated;

  /// Ekranı kaplayan ortalanmış büyük düzen.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    if (prominent) return _buildProminent();
    switch (kind) {
      case StateViewKind.empty:
        return EmptyCard(icon: icon, title: title, message: message, tone: tone, child: action);
      case StateViewKind.error:
      case StateViewKind.offline:
        return _buildNotice(context);
    }
  }

  Widget _buildProminent() {
    final stamp = lastUpdated;
    return EmptyState(
      icon: icon,
      title: title,
      message: stamp == null || message == null ? message : '$message\n${formatLastUpdated(stamp)}',
      tone: tone,
      actionLabel: onRetry == null ? null : 'Tekrar Dene',
      onAction: onRetry,
    );
  }

  Widget _buildNotice(BuildContext context) {
    final stamp = lastUpdated;
    final notice = InlineNotice(message: message ?? title, tone: tone, icon: icon, onRetry: onRetry);
    if (stamp == null) return notice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        notice,
        const SizedBox(height: AppSpace.xs),
        LastUpdatedCaption(at: stamp, alignment: AlignmentDirectional.centerStart, stale: true),
      ],
    );
  }
}

/// "Son güncelleme 14:32" altyazısı (P2-26). Liste yenilendikten (aşağı çekme, "Tekrar Dene", yenile düğmesi) sonra
/// yükleyicinin [PagedLoader.lastLoadedAt] anıyla çizilir. [stale] true ise "(kayıtlar eski olabilir)" eklenir: hata
/// / bağlı değil bildiriminin altında eski kayıtlar durduğunda.
///
/// Küçük, sessiz metin (`textMuted`, yüzeylerde >= 4,5:1); sığmazsa alt satıra sarar (kırpılmaz).
class LastUpdatedCaption extends StatelessWidget {
  const LastUpdatedCaption({
    super.key,
    required this.at,
    this.alignment = AlignmentDirectional.centerEnd,
    this.stale = false,
  });

  final DateTime at;
  final AlignmentGeometry alignment;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = stale ? '${formatLastUpdated(at)}. Kayıtlar eski olabilir.' : formatLastUpdated(at);
    return Align(
      alignment: alignment,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.textMuted),
      ),
    );
  }
}
