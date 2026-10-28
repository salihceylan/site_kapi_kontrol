import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmFormatNumber;
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/state_view.dart';

/// İlişki türünün çip tonu (renk tek başına anlam taşımaz: etiket de yazılır). Belirtilmemiş "Sakin"
/// nötr kalır.
AppTone? relationTone(ResidencyRelation relation) {
  switch (relation) {
    case ResidencyRelation.owner:
      return AppTone.success;
    case ResidencyRelation.tenant:
      return AppTone.info;
    case ResidencyRelation.familyMember:
      return AppTone.primary;
    case ResidencyRelation.resident:
      return AppTone.primary;
  }
}

/// İlişki çipi ("Malik", "Kiracı", "Aile Üyesi", "Sakin"). Sarar, kırpılmaz.
class RelationChip extends StatelessWidget {
  const RelationChip(this.relation, {super.key});

  final ResidencyRelation relation;

  @override
  Widget build(BuildContext context) =>
      StatusChip(
        label: relation.label,
        tone: relationTone(relation) ?? AppTone.primary,
      );
}

/// Pencere / form içindeki hata bildirimi: ekrana gelince (ya da mesajı değişince) kaydırılabilir üst
/// öğe içinde GÖRÜNÜR konuma getirilir. Hata, kaydırılmış uzun bir formun üstünde kalıp kullanıcıdan
/// gizli kalmasın (320 dp x 2,0 yazıda Kaydet'e basınca hata ekran dışında kalıyordu). [action] hatanın
/// hemen altına konan isteğe bağlı eylemdir (örn. "Kişiyi Aç").
///
/// [reveal] false ise bildirim kendini kaydırmaz (form doğrulamasında görünür kılma işini TEK bir yol,
/// [validateForm], yapar; iki `ensureVisible` birbirini ezmesin). [announce] true ise hata ortaya çıkınca
/// ekran okuyucuya ayrıca duyurulur (canlı bölge yeni eklenen düğümde güvenilir değildir).
class CrmFormError extends StatefulWidget {
  const CrmFormError({
    super.key,
    required this.message,
    this.action,
    this.reveal = true,
    this.announce = false,
  });

  final String message;
  final Widget? action;
  final bool reveal;
  final bool announce;

  @override
  State<CrmFormError> createState() => _CrmFormErrorState();
}

class _CrmFormErrorState extends State<CrmFormError> {
  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(CrmFormError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) _reveal();
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.reveal) {
        Scrollable.ensureVisible(context, duration: Duration.zero, alignment: 0.0);
      }
      if (widget.announce) announcePolite(context, widget.message);
    });
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineNotice(message: widget.message),
        if (action != null) ...[const SizedBox(height: AppSpace.sm), action],
        const SizedBox(height: AppSpace.md),
      ],
    );
  }
}

/// Üstte küçük etiket, altında değer: kart ve pencere satırları için. Değer sarar (kırpılmaz).
class CrmInfoLine extends StatelessWidget {
  const CrmInfoLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: th.bodySmall?.copyWith(color: p.textSecondary)),
        Text(value, style: th.bodyMedium),
      ],
    );
  }
}

/// Sayfalı liste gövdesi: iskelet / hata + "Tekrar Dene" / boş durum / kartlar + "Daha fazla yükle".
///
/// Kurallar (önceki incelemelerden): iskelet YALNIZ `loading && items.isEmpty` iken; liste boşken hata
/// varsa "kayıt yok" yerine hata gösterilir; ilk yükleme bitmeden boş durum çizilmez.
///
/// P2-21: boş / hata / bağlı değil üçlüsü [StateView] ile çizilir (görünümü eski [EmptyCard] / [InlineNotice] ile aynıdır);
/// sunucuya ulaşılamıyorsa ([PagedLoader.errorOffline]) bildirim "bağlı değil" olur. P2-26: [showLastUpdated] açıksa
/// listenin üstünde "Son güncelleme 14:32" ([PagedLoader.lastLoadedAt]) yazar; seçici / diyalog listelerinde kapalı kalır.
class CrmListBody<T> extends StatelessWidget {
  const CrmListBody({
    super.key,
    required this.loader,
    required this.itemBuilder,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptyMessage,
    this.filteredTitle,
    this.filtered = false,
    this.skeletonRows = 3,
    this.hideItemsOnError = false,
    this.emptyAction,
    this.showLastUpdated = false,
  });

  final PagedLoader<T> loader;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;

  /// Süzgeç / arama açıkken boş sonuç başlığı.
  final String? filteredTitle;
  final bool filtered;
  final int skeletonRows;

  /// true: yenileme başarısız olduysa ELDEKİ ESKİ kayıtlar gösterilmez, yalnız hata + "Tekrar Dene" çizilir.
  /// Para tutarı gösteren listelerde (bakiyeler) eski tutar, hata uyarısının altında güncelmiş gibi durmasın
  /// diye kullanılır. Varsayılan false: eski liste hata kutusuyla birlikte kalır.
  final bool hideItemsOnError;

  /// Süzgeçsiz boş durumda kartın içine konan eylem (örn. «Excel'den yükle»); süzgeçli boş sonuçta gösterilmez.
  final Widget? emptyAction;

  /// true: yükleme başarılıysa listenin üstünde "Son güncelleme 14:32" yazar (P2-26).
  final bool showLastUpdated;

  @override
  Widget build(BuildContext context) {
    final items = loader.items;
    final error = loader.error;
    final stamp = showLastUpdated ? loader.lastLoadedAt : null;
    if (items.isEmpty) {
      if (loader.loading || (error == null && !loader.loadedOnce)) {
        return ListSkeleton(rows: skeletonRows);
      }
      if (error != null) {
        return StateView.failure(message: error, offline: loader.errorOffline, onRetry: loader.reload);
      }
      final empty = StateView.empty(
        icon: emptyIcon,
        title: filtered ? (filteredTitle ?? emptyTitle) : emptyTitle,
        message: emptyMessage,
        action: filtered ? null : emptyAction,
      );
      if (stamp == null) return empty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LastUpdatedCaption(at: stamp),
          const SizedBox(height: AppSpace.xs),
          empty,
        ],
      );
    }
    if (hideItemsOnError && error != null) {
      return StateView.failure(message: error, offline: loader.errorOffline, onRetry: loader.reload);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          // Eski kayıtlar ekranda duruyor: bildirimin altında en son başarılı güncellemenin saati yazılır.
          StateView.failure(
            message: error,
            offline: loader.errorOffline,
            onRetry: loader.reload,
            lastUpdated: showLastUpdated ? loader.lastLoadedAt : null,
          ),
          const SizedBox(height: AppSpace.md),
        ] else if (stamp != null) ...[
          LastUpdatedCaption(at: stamp),
          const SizedBox(height: AppSpace.xs),
        ],
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: itemBuilder(context, item),
          ),
        if (loader.moreError != null) ...[
          StateView.failure(
            message: loader.moreError!,
            offline: loader.moreErrorOffline,
            onRetry: loader.loadMore,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (loader.hasMore)
          Align(
            alignment: Alignment.center,
            child: PrimaryActionButton(
              label: 'Daha fazla yükle',
              icon: Icons.expand_more_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              loading: loader.loadingMore,
              // Yenileme sürerken eski sayfa imleciyle yeni sayfa istenmez.
              onPressed: (loader.loadingMore || loader.loading) ? null : loader.loadMore,
            ),
          ),
      ],
    );
  }
}

/// Alan değeri: tam sayıysa "120", küsuratlıysa "120,5" (Türkçe ondalık virgül).
String formatNumber(double value) => crmFormatNumber(value);

/// Kişi adı; sunucu boş ad (silinmiş hesap, eksik kayıt) gönderirse boş görünmez.
String crmPersonName(String? name) {
  final trimmed = (name ?? '').trim();
  return trimmed.isEmpty ? 'İsimsiz kişi' : trimmed;
}
