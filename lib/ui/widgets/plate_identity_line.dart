import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart' show PlateIdentity;
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Kimlik satırı metni: sakin "Daire A - 5 · Ali Y." (daire ya da kişi yoksa yalnız olan), misafir "Misafir — Daire A - 5".
/// Kimlik yoksa (tanımsız plaka, yetkisiz okuyucu, bilinmeyen tür) ya da gösterilecek hiçbir alan yoksa null: satır HİÇ çizilmez.
String? plateIdentityText(PlateIdentity? identity) {
  if (identity == null) return null;
  final apartment = identity.apartmentLabel;
  if (identity.isGuest) return apartment == null ? 'Misafir' : 'Misafir — Daire $apartment';
  final parts = <String>[if (apartment != null) 'Daire $apartment', if (identity.personLabel != null) identity.personLabel!];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Karar sonrası kapı durumu metni. `triggered` = SmartKeyPass komutu KABUL ETTİ (fiziksel açılma kanıtı değildir, P1-15);
/// `no_response` = komut kabul edilmedi / cihaz yanıt vermedi. Bilinmeyen / boş durumda null (rozet yok).
String? gateStateText(String? state) => switch (state) {
  'triggered' => 'Kapı tetiklendi ✓',
  'no_response' => 'Kapı yanıt vermedi ✗',
  _ => null,
};

/// Ekran okuyucu cümlesi (simgesiz).
String? gateStateSpeech(String? state) => switch (state) {
  'triggered' => 'Kapı tetiklendi, komut kabul edildi',
  'no_response' => 'Kapı yanıt vermedi',
  _ => null,
};

/// Plakanın altındaki "Daire A - 5 · Ali Y." satırı. Kimlik yoksa boş (0 boyutlu) widget.
class PlateIdentityLine extends StatelessWidget {
  const PlateIdentityLine({super.key, required this.identity, this.style});

  final PlateIdentity? identity;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = plateIdentityText(identity);
    if (text == null) return const SizedBox.shrink();
    final p = context.palette;
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(identity!.isGuest ? Icons.badge_outlined : Icons.home_rounded, size: 16, color: p.textSecondary),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Text(text, key: const ValueKey<String>('plate_identity_text'), style: base?.copyWith(color: p.text, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// "Kapı tetiklendi ✓" / "Kapı yanıt vermedi ✗" rozeti; durum yoksa boş widget. Renk tek başına anlam taşımaz (metin + simge).
class GateStateBadge extends StatelessWidget {
  const GateStateBadge({super.key, required this.state});

  final String? state;

  @override
  Widget build(BuildContext context) {
    final label = gateStateText(state);
    if (label == null) return const SizedBox.shrink();
    final p = context.palette;
    final tone = state == 'triggered' ? AppTone.success : AppTone.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
      decoration: BoxDecoration(color: tone.tint(p), borderRadius: BorderRadius.circular(AppRadius.sm), border: Border.all(color: tone.hue)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tone.ink(p), fontWeight: FontWeight.w800, letterSpacing: 0.3)),
    );
  }
}
