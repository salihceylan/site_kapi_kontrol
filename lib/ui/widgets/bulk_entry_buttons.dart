import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Kişi, daire ve araç listelerinin üstündeki «Excel'den yükle» kısayolu (P2-16): mevcut «Toplu Yükle» sihirbazını,
/// listeye uygun tür önseçili açar (kişiler ve daireler «Hepsi bir arada», araçlar «Araçlar»). Düğme [buttonKey]'i
/// taşır; yalnız yazma yetkisi olanda çizilir (çağıran karar verir: kurul üyesi göremez).
///
/// Etiket görünen metindir; ekran okuyucuya hangi listeyi yükleyeceği [hint] ile söylenir. Boşluk çağıranındır.
class BulkListImportButton extends StatelessWidget {
  const BulkListImportButton({super.key, required this.buttonKey, required this.onImport, required this.hint});

  final Key buttonKey;
  final VoidCallback onImport;

  /// Ekran okuyucu ipucu ("Kişileri Excel ya da CSV dosyasından toplu yüklemek için sihirbazı açar.").
  final String hint;

  /// Düğme etiketi.
  static const String label = "Excel'den yükle";

  @override
  Widget build(BuildContext context) {
    return Semantics(
      hint: hint,
      child: PrimaryActionButton(
        key: buttonKey,
        label: label,
        icon: Icons.upload_file_rounded,
        variant: AppButtonVariant.tonal,
        onPressed: onImport,
      ),
    );
  }
}

/// Boş Kişiler listesindeki «Excel'den yükle» eylemi (EmptyCard içinde): site kurulduktan hemen sonra daire ve
/// kişi bilgilerini dosyadan yüklemek için kısayol.
class BulkEmptyImportAction extends StatelessWidget {
  const BulkEmptyImportAction({super.key, required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Daire ve kişi bilgilerini şimdi toplu yükleyin.',
          textAlign: TextAlign.center,
          style: th.bodyMedium?.copyWith(color: context.palette.textSecondary),
        ),
        const SizedBox(height: AppSpace.sm),
        PrimaryActionButton(
          key: const ValueKey<String>('people_empty_bulk_import'),
          label: "Excel'den yükle",
          icon: Icons.upload_file_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: onImport,
        ),
      ],
    );
  }
}
