import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_error_notice.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Adım 4: önizleme. Sayı çipleri, sorunlu satırlar (süzgeçli, sayfalı), yazma/katı mod anahtarları, hata raporu,
/// örnek satırlar ve onay düğmesi. Hata / yükleme durumunda "boş" ileti ÇİZİLMEZ.
class BulkPreviewStep extends StatefulWidget {
  const BulkPreviewStep({super.key, required this.controller, required this.onConfirm, required this.onBack});

  final BulkImportController controller;

  /// «Aktar»: onay penceresini açar (KVKK onayı orada alınır).
  final VoidCallback onConfirm;
  final VoidCallback onBack;

  @override
  State<BulkPreviewStep> createState() => _BulkPreviewStepState();
}

enum _IssueFilter { all, errors, warnings }

class _BulkPreviewStepState extends State<BulkPreviewStep> {
  _IssueFilter _filter = _IssueFilter.all;
  int _visible = 0;

  BulkImportController get c => widget.controller;

  List<ImportIssue> _filtered(ImportPreview preview) => switch (_filter) {
    _IssueFilter.all => preview.issues,
    _IssueFilter.errors => <ImportIssue>[for (final i in preview.issues) if (i.isError) i],
    _IssueFilter.warnings => <ImportIssue>[for (final i in preview.issues) if (!i.isError) i],
  };

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final preview = c.preview;
    final kind = c.kind!;
    final children = <Widget>[];

    if (preview == null) {
      // Önizleme yok: yükleniyor ya da hata. «Boş» durum çizilmez.
      if (c.previewError != null && !c.previewing) {
        children.add(
          BulkErrorNotice(
            key: const ValueKey<String>('bulk_preview_error'),
            message: c.previewError!,
            onRetry: c.retryLocked ? null : c.requestPreview,
          ),
        );
      } else {
        children
          ..add(const ListSkeleton(rows: 2))
          ..add(const SizedBox(height: AppSpace.md))
          ..add(
            Semantics(
              liveRegion: true,
              container: true,
              label: 'Önizleme hazırlanıyor',
              child: ExcludeSemantics(
                child: Text(
                  'Önizleme hazırlanıyor… Hiçbir kayıt değiştirilmez.',
                  key: const ValueKey<String>('bulk_preview_loading'),
                  style: th.bodyMedium,
                ),
              ),
            ),
          );
      }
      children
        ..add(const SizedBox(height: AppSpace.lg))
        ..add(_BackButton(onBack: c.previewing ? null : widget.onBack));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }

    final labels = c.fieldLabels;
    final filtered = _filtered(preview);
    final pageSize = c.previewPageSize;
    final shown = (_visible < pageSize ? pageSize : _visible).clamp(0, filtered.length);
    final remaining = filtered.length - shown;
    final errorIssues = preview.issues.where((i) => i.isError).length;
    final warningIssues = preview.issues.length - errorIssues;
    final reason = c.commitBlockedReason;
    final canCommit = c.canCommit;

    children.add(
      Text(
        'Önizleme hiçbir kaydı değiştirmez. Aşağıdaki özeti ve sorunlu satırları inceleyip aktarın.',
        style: th.bodyMedium?.copyWith(color: p.textSecondary),
      ),
    );
    children.add(const SizedBox(height: AppSpace.md));

    if (c.uncachedFormulaCells > 0) {
      children
        ..add(
          InlineNotice(
            key: const ValueKey<String>('bulk_uncached_formulas'),
            tone: AppTone.warning,
            message:
                '${c.uncachedFormulaCells} hücrede formül var ama sonucu dosyada kayıtlı değildi; bu hücreler BOŞ '
                'okundu. Eksik kayıt hataları bundan olabilir: dosyayı Excel içinde açıp kaydedin ve yeniden yükleyin.',
          ),
        )
        ..add(const SizedBox(height: AppSpace.md));
    }
    // Mali kaydı olan dairelerde mali alan değişikliği: satır başına uyarı yerine TEK bilgi notu (yüklemeyi engellemez).
    if (preview.financeRecords != null) {
      children
        ..add(
          InlineNotice(
            key: const ValueKey<String>('bulk_finance_records'),
            tone: AppTone.info,
            message: preview.financeRecords!.message,
          ),
        )
        ..add(const SizedBox(height: AppSpace.md));
    }
    if (c.staleNotice != null) {
      children
        ..add(
          InlineNotice(
            key: const ValueKey<String>('bulk_stale_notice'),
            tone: AppTone.warning,
            message: c.staleNotice!,
          ),
        )
        ..add(const SizedBox(height: AppSpace.md));
    }
    if (c.previewError != null && !c.previewing) {
      children
        ..add(BulkErrorNotice(key: const ValueKey<String>('bulk_preview_error'), message: c.previewError!))
        ..add(const SizedBox(height: AppSpace.md));
    }
    if (c.previewing) {
      children
        ..add(
          Semantics(
            liveRegion: true,
            container: true,
            label: 'Önizleme yenileniyor',
            child: const ExcludeSemantics(
              child: Row(
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  SizedBox(width: AppSpace.md),
                  Expanded(child: Text('Önizleme yenileniyor…')),
                ],
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: AppSpace.md));
    }
    if (c.previewStale && !c.previewing) {
      children
        ..add(
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PrimaryActionButton(
              key: const ValueKey<String>('bulk_preview_refresh'),
              label: 'Önizlemeyi Yenile',
              icon: Icons.refresh_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: c.committing || c.retryLocked ? null : c.refreshPreview,
            ),
          ),
        )
        ..add(const SizedBox(height: AppSpace.md));
    }

    // Sayı çipleri (TEK anlamsal özet).
    final chips = preview.chips();
    children.add(
      Semantics(
        container: true,
        label: 'Özet: ${[for (final s in chips) '${s.label} ${s.count}'].join(', ')}',
        child: ExcludeSemantics(
          child: Wrap(
            key: const ValueKey<String>('bulk_preview_chips'),
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final stat in chips)
                InfoChip(
                  '${stat.label}: ${stat.count}',
                  tone: switch (stat.label) {
                    'Hatalı' when stat.count > 0 => AppTone.danger,
                    'Uyarılı' when stat.count > 0 => AppTone.warning,
                    'Eklenecek' || 'Güncellenecek' when stat.count > 0 => AppTone.success,
                    _ => null,
                  },
                ),
            ],
          ),
        ),
      ),
    );
    children.add(const SizedBox(height: AppSpace.md));

    if (preview.totals.ok <= 0) {
      children
        ..add(
          InlineNotice(
            key: const ValueKey<String>('bulk_nothing_to_apply'),
            tone: preview.totals.error > 0 ? AppTone.danger : AppTone.info,
            message: preview.totals.error > 0
                ? 'Aktarılacak geçerli satır yok. Aşağıdaki sorunları dosyada düzeltip yeniden yükleyin.'
                : (preview.totals.withWarnings > 0
                      ? (kind.supportsOverwrite
                            ? 'Değişecek bir şey yok: dosyadaki bazı dolu alanlar sistemdeki farklı değerlerle '
                                  'çakıştığı için korunuyor (uyarılara bakın). Mevcut değerlerin üzerine yazmak '
                                  'için aşağıdaki «Dolu alanların üzerine yaz» anahtarını açın.'
                            : 'Aktarılacak bir değişiklik yok. Dosyadaki bazı değerler uygulanamadı; ayrıntı '
                                  'için aşağıdaki uyarılara bakın.')
                      : 'Dosyadaki kayıtlar zaten sistemde var; aktarılacak bir değişiklik yok.'),
          ),
        )
        ..add(const SizedBox(height: AppSpace.md));
    }

    final planStats = preview.planStats();
    if (planStats.isNotEmpty) {
      children
        ..add(
          AppCard(
            key: const ValueKey<String>('bulk_plan_card'),
            padding: listCardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Ne olacak?'),
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
        )
        ..add(const SizedBox(height: AppSpace.md));
    }

    // Kullanıcı adları: sistem verir, tabloda görülür ve değiştirilebilir (Geri -> tablo). Hesap açılmayacak kişiler ayrıca belirtilir.
    if (kind.createsAccounts && preview.accounts.isNotEmpty) {
      final created = preview.accounts.where((a) => a.status == AccountProposalStatus.create).length;
      final linked = preview.accounts.where((a) => a.status == AccountProposalStatus.existing).length;
      final noAccount = preview.accounts.where((a) => a.status == AccountProposalStatus.emailInUse).length;
      if (created > 0 || noAccount > 0) {
        children
          ..add(
            InlineNotice(
              key: const ValueKey<String>('bulk_preview_login_note'),
              tone: noAccount > 0 ? AppTone.warning : AppTone.info,
              message: [
                if (created > 0)
                  '$created yeni hesap için kullanıcı adlarını sistem verdi${linked > 0 ? ' ($linked kişi mevcut hesabına bağlanır)' : ''}; '
                      'adları görmek ya da değiştirmek için «Geri» ile dönüp tabloya bakın.',
                if (noAccount > 0)
                  '$noAccount kişinin e-postası başka bir hesaba ait olduğundan kişi kaydedilir ama hesabı açılmaz.',
              ].join(' '),
            ),
          )
          ..add(const SizedBox(height: AppSpace.md));
      }
    }

    if (c.blankRows > 0) {
      children
        ..add(
          InlineNotice(
            key: const ValueKey<String>('bulk_blank_rows'),
            tone: AppTone.info,
            message:
                '${c.blankRows} satır atlandı: boş ya da yalnız Blok / Daire No dolu (yüklenecek veri yok). '
                'Bu satırlar önizlemeye ve yüklemeye girmez.',
          ),
        )
        ..add(const SizedBox(height: AppSpace.md));
    }

    if (preview.landShare != null) {
      children
        ..add(
          InlineNotice(
            key: const ValueKey<String>('bulk_land_share'),
            tone: preview.landShare!.complete ? AppTone.success : AppTone.warning,
            message: 'Arsa payı toplamı: ${preview.landShare!.message}',
          ),
        )
        ..add(const SizedBox(height: AppSpace.md));
    }

    // Seçenekler.
    children.add(
      AppCard(
        padding: listCardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kind.isOpening)
              ListTile(
                key: const ValueKey<String>('bulk_cutover_tile'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: const Text('Devir tarihi'),
                subtitle: Text(_dateText(c.cutoverDate)),
                trailing: TextButton(
                  key: const ValueKey<String>('bulk_cutover_change'),
                  onPressed: c.committing || c.previewing ? null : () => _pickCutover(context, c),
                  child: const Text('Değiştir'),
                ),
              ),
            if (kind.supportsOverwrite) ...[
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  key: const ValueKey<String>('bulk_allow_overwrite'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dolu alanların üzerine yaz'),
                  subtitle: const Text(
                    'Kapalıyken yalnız boş alanlar doldurulur; farklı olan değerler korunur.',
                  ),
                  value: c.allowOverwrite,
                  onChanged: c.committing || c.previewing ? null : c.setAllowOverwrite,
                ),
              ),
              if (c.allowOverwrite && preview.plan['overwritten_cells'] != null && preview.plan['overwritten_cells']! > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: InlineNotice(
                    key: const ValueKey<String>('bulk_overwrite_warning'),
                    tone: AppTone.warning,
                    message: '${preview.plan['overwritten_cells']} alanın üzerine yazılacak.',
                  ),
                ),
            ],
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                key: const ValueKey<String>('bulk_strict'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Hatalı satır varsa hiçbirini aktarma'),
                subtitle: const Text(
                  'Kapalıyken geçerli satırlar aktarılır, hatalılar atlanır; düzeltilmiş dosyayı sonra yeniden '
                  'yükleyebilirsiniz.',
                ),
                value: c.strict,
                onChanged: c.committing ? null : c.setStrict,
              ),
            ),
          ],
        ),
      ),
    );
    children.add(const SizedBox(height: AppSpace.lg));

    // Sorunlu satırlar.
    children.add(
      Semantics(
        header: true,
        child: Text('Sorunlu satırlar (${preview.issues.length})', style: th.titleMedium),
      ),
    );
    children.add(const SizedBox(height: AppSpace.sm));
    if (preview.issues.isEmpty) {
      children.add(
        const InlineNotice(
          key: ValueKey<String>('bulk_no_issues'),
          tone: AppTone.success,
          message: 'Sorunlu satır bulunamadı.',
        ),
      );
    } else {
      if (preview.issuesTruncated) {
        children
          ..add(
            const InlineNotice(
              key: ValueKey<String>('bulk_issues_truncated'),
              tone: AppTone.warning,
              message:
                  'Çok sayıda sorun var: yalnızca ilk 4.000 tanesi listelenir (hatalar öncelikli). Dosyayı '
                  'düzeltip yeniden yükleyin; kalan sorunlar sonraki önizlemede görünür.',
            ),
          )
          ..add(const SizedBox(height: AppSpace.md));
      }
      children
        ..add(
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final entry in <(_IssueFilter, String)>[
                (_IssueFilter.all, 'Tümü (${preview.issues.length})'),
                (_IssueFilter.errors, 'Hatalar ($errorIssues)'),
                (_IssueFilter.warnings, 'Uyarılar ($warningIssues)'),
              ])
                ChoiceChip(
                  key: ValueKey<String>('bulk_issue_filter_${entry.$1.name}'),
                  label: Text(entry.$2),
                  selected: _filter == entry.$1,
                  onSelected: (_) => setState(() {
                    _filter = entry.$1;
                    _visible = 0;
                  }),
                ),
            ],
          ),
        )
        ..add(const SizedBox(height: AppSpace.md));
      if (filtered.isEmpty) {
        children.add(
          Text('Bu süzgece uyan satır yok.', key: const ValueKey<String>('bulk_issue_filter_empty'), style: th.bodyMedium),
        );
      }
      for (var i = 0; i < shown; i++) {
        children
          ..add(_IssueTile(issue: filtered[i], fieldLabel: labels[filtered[i].field]))
          ..add(const SizedBox(height: AppSpace.sm));
      }
      if (remaining > 0) {
        children.add(
          Align(
            alignment: Alignment.center,
            child: PrimaryActionButton(
              key: const ValueKey<String>('bulk_issue_more'),
              label: 'Daha fazla göster ($remaining)',
              icon: Icons.expand_more_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: () => setState(() => _visible = shown + pageSize),
            ),
          ),
        );
      }
      children
        ..add(const SizedBox(height: AppSpace.md))
        ..add(
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PrimaryActionButton(
              key: const ValueKey<String>('bulk_report_download'),
              label: 'Hata raporunu indir',
              icon: Icons.download_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              loading: c.reportBusy,
              onPressed: c.reportBusy ? null : c.downloadReport,
            ),
          ),
        );
      if (c.reportMessage != null) {
        children
          ..add(const SizedBox(height: AppSpace.sm))
          ..add(InlineNotice(tone: AppTone.success, message: c.reportMessage!));
      }
      if (c.reportError != null) {
        children
          ..add(const SizedBox(height: AppSpace.sm))
          ..add(BulkErrorNotice(message: c.reportError!, takeFocus: false));
      }
    }
    children.add(const SizedBox(height: AppSpace.lg));

    // Örnek satırlar.
    if (preview.samples.isNotEmpty) {
      children
        ..add(
          AppCard(
            key: const ValueKey<String>('bulk_samples'),
            padding: listCardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Örnek satırlar'),
                const SizedBox(height: AppSpace.sm),
                for (final sample in preview.samples.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: Text(
                      'Satır ${sample.n} · ${_actionLabel(sample.action)}: ${sample.summary}',
                      style: th.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
        )
        ..add(const SizedBox(height: AppSpace.lg));
    }

    // Onay alanı.
    if (c.committing) {
      children
        ..add(
          Semantics(
            liveRegion: true,
            container: true,
            label: 'Aktarılıyor, lütfen bekleyin',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Aktarılıyor… Lütfen bu ekranda bekleyin; bu sırada çıkış yapılamaz.',
                    key: const ValueKey<String>('bulk_committing'),
                    style: th.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: AppSpace.md));
    }
    if (c.commitError != null) {
      children
        ..add(
          BulkErrorNotice(
            key: const ValueKey<String>('bulk_commit_error'),
            message: c.commitError!,
            onRetry: c.commitRetryable && !c.committing && !c.retryLocked ? c.retryCommit : null,
          ),
        )
        ..add(const SizedBox(height: AppSpace.md));
    }
    final showReason = reason != null && !c.previewing && (c.previewStale || preview.totals.ok > 0);
    if (showReason) {
      children
        ..add(
          Text(
            'Aktarmak için: $reason',
            key: const ValueKey<String>('bulk_blocked_reason'),
            style: th.bodySmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w600),
          ),
        )
        ..add(const SizedBox(height: AppSpace.sm));
    }

    Widget confirm = PrimaryActionButton(
      key: const ValueKey<String>('bulk_commit'),
      label: 'Aktar (${preview.totals.ok} satır)',
      icon: Icons.cloud_upload_rounded,
      loading: c.committing,
      onPressed: canCommit ? widget.onConfirm : null,
    );
    if (!canCommit && !c.committing && reason != null) {
      confirm = Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        enabled: false,
        label: 'Aktar, ${preview.totals.ok} satır',
        hint: reason,
        child: confirm,
      );
    }
    children
      ..add(confirm)
      ..add(const SizedBox(height: AppSpace.sm))
      ..add(_BackButton(onBack: c.committing || c.previewing ? null : widget.onBack));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  static String _actionLabel(String action) => switch (action) {
    'create' => 'Yeni',
    'link' => 'Bağlanır',
    'update' => 'Güncellenir',
    'unchanged' => 'Değişmez',
    _ => 'Satır',
  };
}

String _dateText(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  return m == null ? iso : '${m[3]}.${m[2]}.${m[1]}';
}

Future<void> _pickCutover(BuildContext context, BulkImportController c) async {
  final now = DateTime.now();
  final parsed = DateTime.tryParse(c.cutoverDate) ?? now;
  final picked = await showDatePicker(
    context: context,
    initialDate: parsed.isAfter(now) ? now : parsed,
    firstDate: DateTime(now.year - 5, now.month, now.day),
    lastDate: now,
    helpText: 'Devir tarihi',
  );
  if (picked == null) return;
  c.setCutoverDate(
    '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
  );
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        key: const ValueKey<String>('bulk_preview_back'),
        onPressed: onBack,
        child: const Text('Geri', textAlign: TextAlign.center),
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.issue, required this.fieldLabel});

  final ImportIssue issue;
  final String? fieldLabel;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final tone = issue.isError ? AppTone.danger : AppTone.warning;
    final field = fieldLabel ?? issue.field;
    final title = 'Satır ${issue.n}${field == null ? '' : ' · $field'}';
    return Semantics(
      container: true,
      label: '${issue.isError ? 'Hata' : 'Uyarı'}. $title. ${issue.message}',
      child: ExcludeSemantics(
        child: AppCard(
          tone: tone,
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                issue.isError ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                size: 20,
                color: tone.ink(p),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: th.titleSmall?.copyWith(color: tone.ink(p))),
                    const SizedBox(height: AppSpace.xs),
                    Text(issue.message, style: th.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
