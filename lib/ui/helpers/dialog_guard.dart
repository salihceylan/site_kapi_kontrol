import 'package:flutter/material.dart';

/// Penceresi hâlâ en üstteki yol ise kapatır ([result] ile). Çift dokunuşta (seçici satırı, Vazgeç) ikinci
/// `pop` bir üst formu da kapatmasın diye: ilk `pop` başlayınca yol artık "güncel" değildir ve ikinci çağrı
/// yok sayılır. Başka bir pencere (örn. seçici) üstteyken de kapatmaz.
void popIfCurrent<T extends Object?>(BuildContext context, [T? result]) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isCurrent) return;
  Navigator.of(context).pop(result);
}
