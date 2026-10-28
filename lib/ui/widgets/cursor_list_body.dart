import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/state_view.dart';

/// İmleçli sayfalı liste gövdesi ([CursorLoader]): iskelet / hata + "Tekrar Dene" / boş durum / kartlar +
/// "Daha fazla yükle". [CrmListBody] ile aynı kurallar: iskelet YALNIZ `loading && items.isEmpty` iken;
/// liste boşken hata varsa "kayıt yok" yerine hata gösterilir; ilk yükleme bitmeden boş durum çizilmez.
///
/// P2-21: boş / hata / bağlı değil üçlüsü [StateView] ile çizilir; sunucuya ulaşılamıyorsa ([CursorLoader.errorOffline])
/// bildirim "bağlı değil" olur. P2-26: [showLastUpdated] açıksa listenin üstünde "Son güncelleme 14:32" yazar.
class CursorListBody<T> extends StatelessWidget {
  const CursorListBody({
    super.key,
    required this.loader,
    required this.itemBuilder,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptyMessage,
    this.skeletonRows = 3,
    this.showLastUpdated = false,
  });

  final CursorLoader<T> loader;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;
  final int skeletonRows;

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
      final empty = StateView.empty(icon: emptyIcon, title: emptyTitle, message: emptyMessage);
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
              // Yenileme sürerken eski imleçle yeni sayfa istenmez.
              onPressed: (loader.loadingMore || loader.loading) ? null : loader.loadMore,
            ),
          ),
      ],
    );
  }
}
