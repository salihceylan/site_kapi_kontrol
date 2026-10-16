import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// İmleçli sayfalı liste gövdesi ([CursorLoader]): iskelet / hata + "Tekrar Dene" / boş durum / kartlar +
/// "Daha fazla yükle". [CrmListBody] ile aynı kurallar: iskelet YALNIZ `loading && items.isEmpty` iken;
/// liste boşken hata varsa "kayıt yok" yerine hata gösterilir; ilk yükleme bitmeden boş durum çizilmez.
class CursorListBody<T> extends StatelessWidget {
  const CursorListBody({
    super.key,
    required this.loader,
    required this.itemBuilder,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptyMessage,
    this.skeletonRows = 3,
  });

  final CursorLoader<T> loader;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;
  final int skeletonRows;

  @override
  Widget build(BuildContext context) {
    final items = loader.items;
    final error = loader.error;
    if (items.isEmpty) {
      if (loader.loading || (error == null && !loader.loadedOnce)) {
        return ListSkeleton(rows: skeletonRows);
      }
      if (error != null) {
        return InlineNotice(message: error, onRetry: loader.reload);
      }
      return EmptyCard(icon: emptyIcon, title: emptyTitle, message: emptyMessage);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          InlineNotice(message: error, onRetry: loader.reload),
          const SizedBox(height: AppSpace.md),
        ],
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: itemBuilder(context, item),
          ),
        if (loader.moreError != null) ...[
          InlineNotice(message: loader.moreError!, onRetry: loader.loadMore),
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
