import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_error_notice.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Sonuç ekranında tek tek listelenen en çok hesap sayısı (kalanı sayıyla özetlenir; kullanıcı adları kişi kartlarında da görünür).
const int kMaxListedAccounts = 30;

/// Adım 5: sonuç özeti, hata raporu, «Kişilere git» ve «Sıradakini yükle».
class BulkResultStep extends StatelessWidget {
  const BulkResultStep({
    super.key,
    required this.controller,
    required this.onGoToList,
    required this.onNext,
    required this.onFinish,
  });

  final BulkImportController controller;
  final VoidCallback onGoToList;
  final void Function(ImportKind next) onNext;
  final VoidCallback onFinish;

  static String listLabel(ImportKind kind) => switch (kind) {
    ImportKind.people => 'Kişilere git',
    ImportKind.apartments => 'Dairelere git',
    ImportKind.vehicles => 'Araçlara git',
    ImportKind.allInOne => 'Kişilere git',
    ImportKind.openingBalances => 'Dairelere git',
  };

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final result = c.result;
    final kind = c.kind;
    if (result == null || kind == null) {
      return const InlineNotice(message: 'Sonuç bilgisi alınamadı. Kişiler ekranından kayıtları kontrol edin.');
    }
    final issues = c.reportIssues;
    final errors = issues.where((i) => i.isError).length;
    final next = c.suggestedNextKind;
    final planStats = <ImportStat>[
      for (final entry in kImportPlanLabels.entries)
        // `account_create` önizleme tahminidir; gerçekleşen hesaplar aşağıdaki «Kullanıcı hesapları» bölümünde
        if (entry.key != 'account_create' && (result.counts[entry.key] ?? 0) > 0) ImportStat(entry.value, result.counts[entry.key]!),
    ];
    final accounts = result.accounts;
    final nameByLine = <int, String>{
      for (final row in c.rows) row.n: row.cells['ad_soyad']?.toString().trim() ?? '',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineNotice(
          key: const ValueKey<String>('bulk_result_notice'),
          tone: AppTone.success,
          message: result.replayed
              ? 'Bu yükleme daha önce tamamlanmıştı; aynı dosya yeniden uygulanmadı.'
              : '${kind.label} yüklemesi tamamlandı.',
        ),
        const SizedBox(height: AppSpace.lg),
        Semantics(
          container: true,
          label:
              'Uygulanan satır ${result.applied}, değişmeyen ${result.unchanged}, atlanan ${result.skipped}',
          child: ExcludeSemantics(
            child: Wrap(
              key: const ValueKey<String>('bulk_result_chips'),
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                InfoChip('Uygulanan: ${result.applied}', tone: result.applied > 0 ? AppTone.success : null),
                InfoChip('Değişmeyen: ${result.unchanged}'),
                InfoChip('Atlanan: ${result.skipped}', tone: result.skipped > 0 ? AppTone.warning : null),
              ],
            ),
          ),
        ),
        if (planStats.isNotEmpty) ...[
          const SizedBox(height: AppSpace.lg),
          AppCard(
            padding: listCardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Yapılanlar'),
                const SizedBox(height: AppSpace.sm),
                for (final stat in planStats)
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
              ],
            ),
          ),
        ],
        if (accounts != null && !accounts.isEmpty) ...[
          const SizedBox(height: AppSpace.lg),
          AppCard(
            key: const ValueKey<String>('bulk_result_accounts'),
            padding: listCardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Kullanıcı hesapları'),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    InfoChip('Açılan hesap: ${accounts.created}', tone: accounts.created > 0 ? AppTone.success : null),
                    if (accounts.linked > 0) InfoChip('Mevcut hesaba bağlanan: ${accounts.linked}'),
                    if (accounts.skipped > 0) InfoChip('Hesabı açılmayan: ${accounts.skipped}', tone: AppTone.warning),
                  ],
                ),
                if (accounts.items.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Kesinleşen kullanıcı adları (aynı ad başka bir hesapta varsa sonuna _2, _3 eklenir). '
                    'Kişiler ilk girişte şifrelerini değiştirir.',
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  for (final item in accounts.items.take(kMaxListedAccounts))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.xs),
                      child: SelectableText.rich(
                        TextSpan(
                          style: th.bodyMedium,
                          children: [
                            if (item.n != null) TextSpan(text: 'Satır ${item.n}  ', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                            if ((nameByLine[item.n] ?? '').isNotEmpty) TextSpan(text: '${nameByLine[item.n]} → '),
                            TextSpan(text: item.loginName, style: th.titleSmall),
                            if (item.linked) TextSpan(text: '  (mevcut hesap)', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  if (accounts.items.length > kMaxListedAccounts)
                    Text(
                      '… ve ${accounts.items.length - kMaxListedAccounts} hesap daha. Kullanıcı adlarını kişi kartlarında görebilirsiniz.',
                      key: const ValueKey<String>('bulk_result_accounts_more'),
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                ],
                if (accounts.skippedItems.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  InlineNotice(
                    key: const ValueKey<String>('bulk_result_accounts_skipped'),
                    tone: AppTone.warning,
                    message:
                        '${accounts.skippedItems.length} kişinin kaydı yapıldı ama hesabı açılmadı: '
                        '${[for (final skip in accounts.skippedItems.take(3)) '${skip.n != null ? 'satır ${skip.n}: ' : ''}${skip.message}'].join(' ')}'
                        '${accounts.skippedItems.length > 3 ? ' …' : ''}',
                  ),
                ],
              ],
            ),
          ),
        ],
        if (issues.isNotEmpty) ...[
          const SizedBox(height: AppSpace.lg),
          InlineNotice(
            key: const ValueKey<String>('bulk_result_issues'),
            tone: errors > 0 ? AppTone.warning : AppTone.info,
            message:
                '${issues.length} satırda sorun var ($errors hata, ${issues.length - errors} uyarı). Hatalı '
                'satırlar aktarılmadı; dosyayı düzeltip yeniden yükleyebilirsiniz.',
          ),
          if (result.issuesTruncated || (result.issues == null && (c.preview?.issuesTruncated ?? false))) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              'Sorun listesi çok uzun olduğu için raporda yalnızca ilk 4.000 sorun var (hatalar öncelikli).',
              key: const ValueKey<String>('bulk_result_truncated'),
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
          if (result.replayed && result.issues == null) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              'Bu yüklemenin satır ayrıntıları saklanmadığı için rapor, bu oturumdaki önizlemeden hazırlanır.',
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PrimaryActionButton(
              key: const ValueKey<String>('bulk_result_report'),
              label: 'Hata raporunu indir',
              icon: Icons.download_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              loading: c.reportBusy,
              onPressed: c.reportBusy ? null : c.downloadReport,
            ),
          ),
          if (c.reportMessage != null) ...[
            const SizedBox(height: AppSpace.sm),
            InlineNotice(tone: AppTone.success, message: c.reportMessage!),
          ],
          if (c.reportError != null) ...[
            const SizedBox(height: AppSpace.sm),
            BulkErrorNotice(message: c.reportError!, takeFocus: false),
          ],
        ],
        const SizedBox(height: AppSpace.xl),
        PrimaryActionButton(
          key: const ValueKey<String>('bulk_result_go'),
          label: listLabel(kind),
          icon: Icons.groups_2_rounded,
          onPressed: onGoToList,
        ),
        if (next != null) ...[
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('bulk_result_next'),
            label: 'Sıradakini yükle: ${next.label}',
            icon: Icons.arrow_forward_rounded,
            variant: AppButtonVariant.tonal,
            onPressed: () => onNext(next),
          ),
        ],
        const SizedBox(height: AppSpace.sm),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            key: const ValueKey<String>('bulk_result_finish'),
            onPressed: onFinish,
            child: const Text('Bitir', textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}
