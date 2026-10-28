import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Kutucuk ızgarası sütun sayısı: telefonda 2, geniş ekranda 3-4; büyük yazı ölçeğinde sütun azalır (başlık kırılmasın).
/// Panel vitrininin kuralıyla aynıdır (`showcaseColumns`); [minTileWidth] kutucuğun yazı ölçeği 1,0'daki en az genişliğidir.
///
/// [width] ızgaranın kullanılabilir genişliği (dp), [textScale] yazı ölçeği (1,0 = normal).
int tileColumns(double width, double textScale, {double minTileWidth = 130}) {
  final cap = width < 600 ? 2 : (width < 900 ? 3 : 4);
  final scale = textScale < 1 ? 1.0 : textScale;
  final minTile = minTileWidth * (1 + (scale - 1) * 0.6);
  final fit = (width / minTile).floor();
  return fit.clamp(1, cap);
}

/// Duyarlı kutucuk ızgarası (liste ↔ kutucuk anahtarının kutucuk kipi): sütun sayısı genişliğe ve yazı ölçeğine göre
/// ([tileColumns]); her satırın kutucukları AYNI yüksekliktedir (içerik uzayınca satır birlikte uzar, taşma olmaz).
///
/// Sınırlı genişlikte (Column çocuğu) tüm genişliği kaplar. Çocuklar kendi yüksekliklerini belirler; satır içinde dikeyde
/// uzatılırlar.
class TileGrid extends StatelessWidget {
  const TileGrid({
    super.key,
    required this.children,
    this.minTileWidth = 130,
    this.spacing = AppSpace.md,
  });

  final List<Widget> children;
  final double minTileWidth;

  /// Sütunlar ve satırlar arası boşluk.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = tileColumns(constraints.maxWidth, scale, minTileWidth: minTileWidth);
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) SizedBox(width: spacing),
                    Expanded(
                      child: start + c < children.length ? children[start + c] : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) SizedBox(height: spacing),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}
