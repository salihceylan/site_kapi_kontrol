import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_error_notice.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Adım 1: ne yükleneceği + şablon indirme.
class BulkKindStep extends StatelessWidget {
  const BulkKindStep({super.key, required this.controller});

  final BulkImportController controller;

  static const Map<ImportKind, IconData> icons = <ImportKind, IconData>{
    ImportKind.apartments: Icons.apartment_rounded,
    ImportKind.people: Icons.groups_2_rounded,
    ImportKind.vehicles: Icons.directions_car_rounded,
    ImportKind.allInOne: Icons.table_chart_rounded,
    ImportKind.openingBalances: Icons.account_balance_wallet_rounded,
  };

  static const Map<ImportKind, String> descriptions = <ImportKind, String>{
    ImportKind.apartments:
        'Var olan dairelerin kat, tip, m², arsa payı ve borç sorumlusu bilgilerini doldurur. Yeni daire eklemez.',
    ImportKind.people:
        'Kişileri, daire ilişkilerini ve araç plakalarını ekler. Hesap açmaz, e-posta göndermez.',
    ImportKind.vehicles: 'Yalnızca araç plakalarını sitedeki mevcut kişilere bağlar.',
    ImportKind.allInOne:
        'Tek dosyada daire bilgisi, sakin ve ilişkisi, telefon, e-posta, taşınma tarihi, plaka ve not. Bir dairenin '
        'birden çok sakini alt alta yazılır.',
    ImportKind.openingBalances:
        'Eski yazılımdan devreden daire borçlarını tek seferde deftere yazar. Yüklemeyi sonradan geri alabilirsiniz.',
  };

  static const Map<ImportKind, int> _order = <ImportKind, int>{};

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final Widget body;
    if (c.spec == null) {
      body = c.specLoading || (c.specError == null)
          ? const ListSkeleton(rows: 3)
          : BulkErrorNotice(
              key: const ValueKey<String>('bulk_spec_error'),
              message: c.specError!,
              onRetry: c.loadSpec,
            );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final kind in c.allowedKinds)
            if (c.spec!.of(kind) != null) ...[
              _KindTile(controller: c, kind: kind),
              const SizedBox(height: AppSpace.md),
            ],
          if (c.kind != null) ...[
            _TemplateCard(controller: c),
            const SizedBox(height: AppSpace.lg),
          ],
          _Continue(controller: c),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          c.allowedKinds.contains(ImportKind.openingBalances) && c.allowedKinds.length == 1
              ? 'Excel (.xlsx) veya CSV dosyasıyla eski yazılımdan devreden bakiyeleri yükleyin.'
              : 'Excel (.xlsx) veya CSV dosyasıyla toplu yükleme yapın. «Hepsi bir arada» tek dosyada daireleri, sakinleri ve araçları birlikte yükler.',
          style: th.bodyMedium?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            if (c.siteName.trim().isNotEmpty) InfoChip(c.siteName.trim()),
            if (c.siteSummary != null) InfoChip(c.siteSummary!),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        body,
      ],
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({required this.controller, required this.kind});

  final BulkImportController controller;
  final ImportKind kind;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final selected = controller.kind == kind;
    final done = controller.completedKinds.contains(kind);
    final order = BulkKindStep._order[kind];
    final description = BulkKindStep.descriptions[kind]!;
    return AppCard(
      key: ValueKey<String>('bulk_kind_${kind.apiValue}'),
      selected: selected,
      onTap: controller.busy ? null : () => controller.selectKind(kind),
      semanticLabel: '${kind.label}. ${selected ? 'Seçili. ' : ''}${done ? 'Bu oturumda yüklendi.' : ''}'.trim(),
      padding: listCardPadding(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(
            icon: BulkKindStep.icons[kind]!,
            tone: selected ? AppTone.primary : AppTone.neutral,
            size: 44,
            gap: AppSpace.md,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kind.label, style: th.titleMedium),
                const SizedBox(height: AppSpace.xs),
                Text(description, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    if (kind == ImportKind.allInOne) const InfoChip('Önerilen', tone: AppTone.primary),
                    if (order != null) InfoChip('Önerilen sıra: $order'),
                    if (done) const InfoChip('Yüklendi', tone: AppTone.success),
                    if (selected) const InfoChip('Seçili', tone: AppTone.primary),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.controller});

  final BulkImportController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final kind = c.kind!;
    return AppCard(
      key: const ValueKey<String>('bulk_template_card'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Şablon', icon: Icons.description_outlined),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Şablon sitenizin mevcut blok ve daire numaraları doldurulmuş olarak hazır gelir; ilgili '
            'bilgileri yazmanız yeterlidir. Kendi dosyanızı da doğrudan yükleyebilirsiniz.',
            style: th.bodyMedium?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              PrimaryActionButton(
                key: const ValueKey<String>('bulk_template_xlsx'),
                label: 'Şablonu indir (Excel)',
                icon: Icons.download_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                loading: c.templateBusy,
                onPressed: c.busy ? null : () => c.downloadTemplate(ExportFormat.xlsx),
              ),
              PrimaryActionButton(
                key: const ValueKey<String>('bulk_template_csv'),
                label: 'Şablonu indir (CSV)',
                icon: Icons.download_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                onPressed: c.busy ? null : () => c.downloadTemplate(ExportFormat.csv),
              ),
            ],
          ),
          if (c.templateMessage != null) ...[
            const SizedBox(height: AppSpace.md),
            InlineNotice(
              key: const ValueKey<String>('bulk_template_message'),
              tone: AppTone.success,
              message: c.templateMessage!,
            ),
          ],
          if (c.templateError != null) ...[
            const SizedBox(height: AppSpace.md),
            BulkErrorNotice(
              key: const ValueKey<String>('bulk_template_error'),
              message: c.templateError!,
            ),
          ],
        ],
      ),
    );
  }
}

class _Continue extends StatelessWidget {
  const _Continue({required this.controller});

  final BulkImportController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final enabled = c.kind != null && !c.busy;
    Widget button = PrimaryActionButton(
      key: const ValueKey<String>('bulk_kind_continue'),
      label: 'Devam: Dosya seç',
      icon: Icons.arrow_forward_rounded,
      onPressed: enabled ? c.goToFileStep : null,
    );
    if (c.kind == null) {
      button = Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        enabled: false,
        label: 'Devam: Dosya seç',
        hint: 'Önce yukarıdan ne yükleyeceğinizi seçin.',
        child: button,
      );
    }
    return button;
  }
}
