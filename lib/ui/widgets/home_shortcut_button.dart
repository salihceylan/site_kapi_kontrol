import 'package:flutter/material.dart';
import 'package:phosphor_glyphs/phosphor_glyphs.dart';
import 'package:site_kapi_kontrol/services/panel_return_requests.dart';

/// Üst çubuktaki "Ana sayfa" düğmesi (karşılaştırma raporu P1-13): bulunduğunuz ekrandan tek dokunuşla Panel'e (ana sayfa)
/// döner. Mevcut geri davranışı (donanım geri tuşu, çekmece, sakin alt çubuğu) DEĞİŞTİRMEZ; yanına eklenen görünür bir yoldur.
///
/// - Ana kabukta (HomePage) menü düğmesinin yanında, ekranda sakin alt çubuğu (Özet sekmesi) YOKKEN durur: `showsHomeShortcut`.
///   Orada [onPressed] verilir ve çekmeceden "Panel"i seçmekle aynı korumalı gezinme çalışır.
/// - Derin (yeni sayfa olarak açılan) ekranlarda üst çubuğun `actions` listesine konur; [onPressed] verilmezse
///   [PanelReturnRequests.returnToPanel] açık ekranların hepsini kapatıp kabuğa Panel'i seçtirir. Kaydedilmemiş veri taşıyan
///   formlara (sihirbaz, düzenleme) konmaz: kapanış onay sormadan tüm ekranları atar.
///
/// Dokunma hedefi 44 dp; ekran okuyucu ve ipucu adı "Ana sayfa". Simge Panel'in menüdeki ve alt çubuktaki ("Özet") simgesidir:
/// aynı hedef, aynı simge; ev simgesi üst çubuktaki "Sakin Modu" hapına ayrılmıştır, ikisi karışmaz.
class HomeShortcutButton extends StatelessWidget {
  const HomeShortcutButton({super.key, this.onPressed});

  /// Ekran okuyucu adı ve ipucu.
  static const String label = 'Ana sayfa';

  /// Panel'in simgesi (çekmecedeki "Panel" ve sakin alt çubuğundaki "Özet" ile aynı).
  static const IconData icon = PhosphorIconsRegular.squaresFour;

  /// Dokununca yapılacak iş; verilmezse derin ekran davranışı ([PanelReturnRequests.returnToPanel]).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey<String>('ana_sayfa_dugmesi'),
      visualDensity: VisualDensity.standard,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      tooltip: label,
      // Ekran okuyucu adı: ipucu tek başına anlamsal `label` üretmez; simgenin etiketi düğme düğümüne birleşir
      // (ThemeToggleButton ile aynı kalıp).
      icon: const Icon(icon, size: 24, semanticLabel: label),
      onPressed: onPressed ?? () => PanelReturnRequests.returnToPanel(context),
    );
  }
}
