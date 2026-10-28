import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dial_call.dart';
import 'package:site_kapi_kontrol/ui/widgets/dial_fallback.dart';

/// Büyük 112 düğmesi ("dokun-ara", P2-23, karar K13): acil durumlar bölümünde tek dokunuşla acil çağrı merkezini arama
/// ekranını `tel:112` ile açar.
///
/// - Düğme aramayı KENDİSİ başlatmaz; telefon uygulaması 112 yazılı açılır (Android arama ekranı, iOS onay penceresi): kazara
///   dokunuşla çağrı yapılmaz.
/// - KURU MOD: cihaz aramayı açamazsa (tablet, emülatör, masaüstü, web, arama uygulaması yok) düğmenin altında numara büyük
///   gösterilir ve kopyalanabilir ([DialFallbackCard]); sonraki başarılı dokunuş kartı kaldırır. Arama hiçbir zaman sessizce
///   başarısız olmaz.
/// - Acil yardım AKIŞI (yangın / asansör ayrı düğmeler) başka paketin işidir; bu bileşen onun içine de konabilir
///   (aynı düğme, aynı kuru mod). [launcher] testlerde sahte verilir.
///
/// Görünüm: durum tonlu dolu düğme (mercan [AppTone.danger] `a` + beyaz metin, 4,70:1); düz, gölgesiz. En az 72 dp yüksek,
/// büyük yazıda metin sarar (sabit boyutlu metin kutusu yok). Erişilebilirlik: tek düğüm, adı görünen metindir
/// ("112 Acil Çağrı Merkezi'ni ara"), ipucu dokununca olanı söyler; klavye odağında 2 dp halka görünür.
class EmergencyCallButton extends StatefulWidget {
  const EmergencyCallButton({super.key, this.launcher, this.number = kEmergencyNumber});

  /// Telefon uygulamasını açan işlev (varsayılan: `url_launcher`).
  final DialLauncher? launcher;

  /// Aranacak acil numara (varsayılan 112).
  final String number;

  @override
  State<EmergencyCallButton> createState() => _EmergencyCallButtonState();
}

class _EmergencyCallButtonState extends State<EmergencyCallButton> {
  bool _unavailable = false;
  bool _focused = false;
  bool _busy = false;

  Future<void> _call() async {
    if (_busy) return;
    _busy = true;
    try {
      unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
      final outcome = await dialPhone(widget.number, launcher: widget.launcher);
      if (!mounted) return;
      // Başarıda kuru mod kartı kalkar; başarısızlıkta (geçersiz numara dahil) numara gösterilir.
      setState(() => _unavailable = outcome != DialOutcome.started);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final fill = AppTone.danger.a;
    const ink = Colors.white;
    final radius = BorderRadius.circular(AppRadius.lg);
    final dialable = dialableNumber(widget.number) ?? widget.number;
    final button = Semantics(
      container: true,
      button: true,
      label: '$dialable Acil Çağrı Merkezi\'ni ara',
      hint: 'Telefon uygulamasını $dialable numarasıyla açar',
      onTap: () => unawaited(_call()),
      excludeSemantics: true,
      child: Material(
        key: const ValueKey<String>('acil_112_dugme'),
        color: fill,
        shape: RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(_call()),
          onFocusChange: (focused) {
            if (focused != _focused) setState(() => _focused = focused);
          },
          borderRadius: radius,
          splashColor: ink.withValues(alpha: 0.20),
          highlightColor: ink.withValues(alpha: 0.10),
          focusColor: ink.withValues(alpha: 0.18),
          hoverColor: ink.withValues(alpha: 0.08),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
              child: Row(
                children: [
                  const Icon(Icons.call_rounded, size: 32, color: ink),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(dialable, style: th.headlineMedium?.copyWith(color: ink)),
                        Text(
                          'Acil Çağrı Merkezi\'ni ara',
                          style: th.bodyMedium?.copyWith(color: ink, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Klavye odağı halkası (bağlantı / odak mavisi): düğmenin 2 dp dışında; düzeni değiştirmez (hep 2 dp boşluk ayrılır).
        DecoratedBox(
          key: const ValueKey<String>('acil_112_odak'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg + 4),
            border: Border.all(color: _focused ? p.focusRing : Colors.transparent, width: 2),
          ),
          child: Padding(padding: const EdgeInsets.all(2), child: button),
        ),
        if (_unavailable) ...[
          const SizedBox(height: AppSpace.sm),
          DialFallbackCard(dialable: dialable),
        ],
      ],
    );
  }
}
