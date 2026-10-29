import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart' show formatMinor;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show filledToneStyle;

/// Yükleme onay penceresi: ne yazılacağının sayıları, atlanacak/uyarılı satırlar, (daireler için) üzerine
/// yazılacak alan sayısı ve — kişi / araç yüklemesinde — ZORUNLU KVKK onay kutusu. [show] onaylanırsa true döner.
///
/// Çift dokunma koruması: onay düğmesi bir kez basılınca pencere kapanır ve ikinci `pop` yok sayılır
/// ([popIfCurrent]). KVKK kutusu işaretlenmeden onay düğmesi PASİFTİR.
class BulkConfirmDialog extends StatefulWidget {
  const BulkConfirmDialog({
    super.key,
    required this.kind,
    required this.preview,
    required this.strict,
    required this.allowOverwrite,
    this.cutoverDate,
  });

  final ImportKind kind;

  /// Devir bakiyesi: devir tarihi (YYYY-MM-DD).
  final String? cutoverDate;
  final ImportPreview preview;
  final bool strict;
  final bool allowOverwrite;

  static const String ackText =
      'Kişi verilerini işlemek için gerekli yasal dayanağa sahip olduğumu onaylıyorum.';

  static Future<bool> show(
    BuildContext context, {
    required ImportKind kind,
    required ImportPreview preview,
    required bool strict,
    required bool allowOverwrite,
    String? cutoverDate,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BulkConfirmDialog(
        kind: kind,
        preview: preview,
        strict: strict,
        allowOverwrite: allowOverwrite,
        cutoverDate: cutoverDate,
      ),
    );
    return result ?? false;
  }

  @override
  State<BulkConfirmDialog> createState() => _BulkConfirmDialogState();
}

class _BulkConfirmDialogState extends State<BulkConfirmDialog> {
  bool _ack = false;

  static String _dateText(String? iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso ?? '');
    return m == null ? (iso ?? '') : '${m[3]}.${m[2]}.${m[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final preview = widget.preview;
    final kind = widget.kind;
    final stats = preview.planStats();
    final skipped = widget.strict ? 0 : preview.totals.error;
    final needsAck = kind.needsAcknowledgement;
    final isOpening = kind.isOpening;
    final canConfirm = isOpening ? _ack : (!needsAck || _ack);
    return AppDialog(
      title: 'Yüklemeyi onaylayın',
      subtitle: kind.label,
      icon: Icons.cloud_upload_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('bulk_confirm_cancel'),
          onPressed: () => popIfCurrent(context, false),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const ValueKey<String>('bulk_confirm_submit'),
          style: filledToneStyle(context),
          onPressed: canConfirm ? () => popIfCurrent(context, true) : null,
          child: const Text('Onayla ve Aktar'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isOpening
                ? ((preview.plan['credit_total_minor'] ?? 0) > 0
                      // Alacaklı devir (K16): borç ve alacak toplamları ayrı gösterilir ve ayrı onaylanır
                      ? 'Toplam ${formatMinor(preview.plan['total_minor'] ?? 0)} devir borcu ve ${formatMinor(preview.plan['credit_total_minor'] ?? 0)} devir alacağı '
                            '(${preview.plan['opening_add'] ?? preview.totals.ok} kayıt) hesaplara ${_dateText(widget.cutoverDate)} tarihiyle yazılacak. '
                            'Alacak, sonraki borçlardan (vadesi en eski borçtan başlayarak) düşer. Yanlışsa Finans > Daireler > Devir '
                            'bakiyesi ekranından yüklemeyi geri alabilirsiniz.'
                      : 'Toplam ${formatMinor(preview.plan['total_minor'] ?? 0)} devir borcu ${preview.plan['opening_add'] ?? preview.totals.ok} '
                            'hesaba ${_dateText(widget.cutoverDate)} tarihiyle yazılacak. Yanlışsa Finans > Daireler > Devir '
                            'bakiyesi ekranından yüklemeyi geri alabilirsiniz.')
                : '${preview.totals.ok} satır aktarılacak. Bu işlem toplu geri alınamaz; yanlış yüklenen kayıtlar tek '
                      'tek düzeltilir.',
            key: const ValueKey<String>('bulk_confirm_summary'),
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          for (final stat in stats)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Semantics(
                container: true,
                label: '${stat.label}: ${stat.count}',
                child: ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(stat.label, style: th.bodyMedium)),
                      const SizedBox(width: AppSpace.sm),
                      Text('${stat.count}', style: th.titleSmall),
                    ],
                  ),
                ),
              ),
            ),
          if (skipped > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                '$skipped hatalı satır aktarılmayacak.',
                key: const ValueKey<String>('bulk_confirm_skipped'),
                style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppTone.warning.ink(p)),
              ),
            ),
          if (preview.totals.withWarnings > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                '${preview.totals.withWarnings} satırda uyarı var (aktarılır, bir kısmı atlanmış olabilir).',
                style: th.bodyMedium,
              ),
            ),
          if (widget.allowOverwrite && (preview.plan['overwritten_cells'] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                '${preview.plan['overwritten_cells']} alanın mevcut değerinin üzerine yazılacak.',
                key: const ValueKey<String>('bulk_confirm_overwrite'),
                style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppTone.danger.ink(p)),
              ),
            ),
          if (widget.strict)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                'Katı mod açık: hatalı satır çıkarsa hiçbir satır aktarılmaz.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
          if (isOpening) ...[
            const SizedBox(height: AppSpace.md),
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                key: const ValueKey<String>('bulk_confirm_amount_ack'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _ack,
                onChanged: (value) => setState(() => _ack = value ?? false),
                title: const Text('Tutarları eski kayıtlarla karşılaştırdım.'),
              ),
            ),
          ] else if (needsAck) ...[
            const SizedBox(height: AppSpace.md),
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                key: const ValueKey<String>('bulk_confirm_ack'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _ack,
                onChanged: (value) => setState(() => _ack = value ?? false),
                title: const Text(BulkConfirmDialog.ackText),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
