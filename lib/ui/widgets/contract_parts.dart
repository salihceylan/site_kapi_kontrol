// Firma ve Sözleşme Takibi ekranlarının ortak parçaları: kategori ikonu, durum çipi, kalan gün metni, özet kutuları
// (süzgeç olarak da çalışır), sözleşme kartı ve firma kartı.
//
// Kurallar (diğer modüllerle aynı): metinler sarar ya da elips olur (320 dp x 2,0'da taşma yok); durum yalnız renkle
// verilmez (etiket + ikon); dokunma hedefleri en az 48 dp; ham renk yok. Firma adı / yetkili / telefon / e-posta
// günlüğe yazılmaz.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatDateField;
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

IconData contractCategoryIcon(ContractCategory category) => switch (category) {
  ContractCategory.asansor => Icons.elevator_rounded,
  ContractCategory.guvenlik => Icons.security_rounded,
  ContractCategory.temizlik => Icons.cleaning_services_rounded,
  ContractCategory.bahce => Icons.yard_rounded,
  ContractCategory.havuz => Icons.pool_rounded,
  ContractCategory.teknikBakim => Icons.build_rounded,
  ContractCategory.yazilim => Icons.computer_rounded,
  ContractCategory.sigorta => Icons.verified_user_rounded,
  ContractCategory.diger => Icons.handshake_rounded,
};

/// Durum tonu: yürürlükte başarı, bitişi yaklaşan uyarı, süresi dolan hata, feshedilen nötr.
AppTone contractStateTone(ContractState state) => switch (state) {
  ContractState.aktif => AppTone.success,
  ContractState.yaklasiyor => AppTone.warning,
  ContractState.sonaErdi => AppTone.danger,
  ContractState.feshedildi => AppTone.neutral,
  ContractState.unknown => AppTone.neutral,
};

IconData contractStateIcon(ContractState state) => switch (state) {
  ContractState.aktif => Icons.check_circle_outline_rounded,
  ContractState.yaklasiyor => Icons.hourglass_bottom_rounded,
  ContractState.sonaErdi => Icons.event_busy_rounded,
  ContractState.feshedildi => Icons.cancel_outlined,
  ContractState.unknown => Icons.help_outline_rounded,
};

/// Özet kutularının başlığı (çoğul; "Yürürlükte", "Bitişi yaklaşan", ...).
String contractSummaryLabel(ContractState state) => switch (state) {
  ContractState.aktif => 'Yürürlükte',
  ContractState.yaklasiyor => 'Bitişi yaklaşan',
  ContractState.sonaErdi => 'Süresi dolmuş',
  ContractState.feshedildi => 'Feshedilen',
  ContractState.unknown => 'Diğer',
};

/// Bitişe kalan gün: sunucunun `days_left` değeri; yoksa (eski sunucu) bitiş tarihinden İstanbul gününe göre
/// hesaplanır. Süresiz sözleşmede null. [today] testler içindir (İstanbul takvim günü).
int? contractDaysLeft(Contract contract, {DateTime? today}) {
  final fromServer = contract.daysLeft;
  if (fromServer != null) return fromServer;
  final end = contract.endDate;
  if (end == null) return null;
  final now = today ?? istanbulNow();
  return DateTime.utc(end.year, end.month, end.day)
      .difference(DateTime.utc(now.year, now.month, now.day))
      .inDays;
}

/// "73 gün kaldı" / "Bugün bitiyor" / "5 gün önce bitti" / "Süresiz".
String contractRemainingText(Contract contract, {DateTime? today}) {
  if (contract.isOpenEnded) return 'Süresiz';
  final days = contractDaysLeft(contract, today: today);
  if (days == null) return 'Süresiz';
  if (days > 0) return '$days gün kaldı';
  if (days == 0) return 'Bugün bitiyor';
  return '${-days} gün önce bitti';
}

/// Tutar metni ("1.250,00 ₺"; TRY dışında para birimi kodu yazılır); tutar yoksa null.
String? contractAmountText(Contract contract) {
  final minor = contract.amountMinor;
  if (minor == null) return null;
  if (contract.currency == 'TRY') return formatMinor(minor);
  return '${formatMinor(minor, symbol: false)} ${contract.currency}';
}

/// Tutar + dönem ("1.250,00 ₺ / Aylık"); tutar yoksa "Belirtilmedi".
String contractAmountWithPeriod(Contract contract) {
  final amount = contractAmountText(contract);
  if (amount == null) return 'Belirtilmedi';
  final period = contract.period;
  return period == null ? amount : '$amount / ${period.label}';
}

/// Durum çipi: ikon + etiket.
class ContractStateChip extends StatelessWidget {
  const ContractStateChip(this.state, {super.key});

  final ContractState state;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: state.label,
    tone: contractStateTone(state),
    icon: contractStateIcon(state),
  );
}

/// Salt okunur kullanıcı notu (yönetim kurulu / görevli).
class ContractReadOnlyNote extends StatelessWidget {
  const ContractReadOnlyNote({super.key, required this.access});

  final ContractSiteAccess access;

  @override
  Widget build(BuildContext context) => InlineNotice(
    key: const ValueKey<String>('contract_read_only_note'),
    tone: AppTone.info,
    icon: Icons.visibility_rounded,
    message: access == ContractSiteAccess.staff
        ? 'Görevli olarak firmaları ve sözleşmeleri yalnızca görüntüleyebilirsiniz.'
        : 'Yönetim kurulu üyesi olarak firmaları ve sözleşmeleri yalnızca görüntüleyebilirsiniz.',
  );
}

/// Dört özet kutusu (Yürürlükte / Bitişi yaklaşan / Süresi dolmuş / Feshedilen). Kutuya dokunmak o durumu süzer,
/// seçili kutuya yeniden dokunmak süzgeci kaldırır. Özet alınamadıysa sayı yerine "-" yazılır (liste yine çalışır).
class ContractSummaryTiles extends StatelessWidget {
  const ContractSummaryTiles({
    super.key,
    required this.summary,
    required this.selected,
    required this.onSelect,
  });

  final ContractSummary? summary;

  /// Seçili durum süzgeci (yoksa null: tümü).
  final ContractState? selected;
  final ValueChanged<ContractState> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
        final columns = maxWidth >= 560 ? 4 : 2;
        final width = (maxWidth - AppSpace.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final state in ContractState.known)
              SizedBox(
                width: width,
                child: _SummaryTile(
                  key: ValueKey<String>('contract_summary_${state.apiValue}'),
                  state: state,
                  count: summary?.countOf(state),
                  selected: selected == state,
                  onTap: () => onSelect(state),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    super.key,
    required this.state,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final ContractState state;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final tone = contractStateTone(state);
    final label = contractSummaryLabel(state);
    final value = count == null ? '-' : '$count';
    final semantic = count == null
        ? '$label: sayı alınamadı. Bu durumdaki sözleşmeleri göster.'
        : '$label: $count sözleşme. ${selected ? 'Süzgeç açık; kaldırmak için dokunun.' : 'Bu durumdaki sözleşmeleri göster.'}';
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      selected: selected,
      onTap: onTap,
      semanticLabel: semantic,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(contractStateIcon(state), size: 18, color: tone.ink(p)),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    label,
                    style: th.bodySmall?.copyWith(
                      color: p.textSecondary,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: th.titleLarge?.copyWith(color: tone.ink(p)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sözleşme listesi kartı: kategori ikonu, durum / kategori / otomatik yenileme çipleri, başlık, firma, bitiş ve
/// kalan gün; otomatik yenilenen sözleşmede fesih bildiriminin son günü. Dokununca [onTap] (ayrıntı).
class ContractCard extends StatelessWidget {
  const ContractCard({
    super.key,
    required this.contract,
    required this.onTap,
    this.today,
  });

  final Contract contract;
  final VoidCallback onTap;

  /// Testler için İstanbul günü (kalan gün hesabı sunucu değeri yoksa).
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final c = contract;
    final terminated = c.state == ContractState.feshedildi || c.isTerminated;
    final end = c.endDate;
    final remaining = contractRemainingText(c, today: today);
    final endLine = end == null
        ? 'Süresiz'
        : (terminated
              ? 'Bitiş: ${formatDateField(end)}'
              : 'Bitiş: ${formatDateField(end)} · $remaining');
    final deadline = c.noticeDeadline;
    final showDeadline = c.autoRenew && deadline != null && !terminated;
    final endTone = switch (c.state) {
      ContractState.yaklasiyor => AppTone.warning.ink(p),
      ContractState.sonaErdi => AppTone.danger.ink(p),
      _ => p.textSecondary,
    };
    final semantic = StringBuffer(
      '${c.displayTitle}. Firma: ${c.displayVendor}. Durum: ${c.state.label}. Kategori: ${c.category.label}. ',
    );
    if (end == null) {
      semantic.write('Süresiz.');
    } else {
      semantic.write(
        terminated
            ? 'Bitiş: ${formatDateField(end)}.'
            : 'Bitiş: ${formatDateField(end)}, $remaining.',
      );
    }
    if (c.autoRenew) semantic.write(' Otomatik yenilenir.');
    if (showDeadline) {
      semantic.write(' Fesih bildirimi son günü: ${formatDateField(deadline)}.');
    }
    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: semantic.toString(),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              icon: contractCategoryIcon(c.category),
              tone: contractStateTone(c.state),
              gap: AppSpace.md,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      ContractStateChip(c.state),
                      InfoChip(c.category.label),
                      if (c.autoRenew)
                        const InfoChip('Otomatik yenilenir', tone: AppTone.info),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    c.displayTitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: th.titleMedium,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    c.displayVendor,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: th.bodyMedium?.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    endLine,
                    key: ValueKey<String>('contract_end_${c.id}'),
                    style: th.bodyMedium?.copyWith(
                      color: endTone,
                      fontWeight: endTone == p.textSecondary ? null : FontWeight.w700,
                    ),
                  ),
                  if (showDeadline) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      'Fesih bildirimi son günü: ${formatDateField(deadline)}',
                      key: ValueKey<String>('contract_deadline_${c.id}'),
                      style: th.bodySmall?.copyWith(
                        color: AppTone.warning.ink(p),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Firma kartı: kategori, aktif / pasif, yetkili, telefon (dokununca arama), e-posta (dokununca e-posta), sözleşme
/// sayısı; yazma yetkisi varsa "Düzenle" ve "Pasife al" / "Etkinleştir".
class ContractVendorCard extends StatelessWidget {
  const ContractVendorCard({
    super.key,
    required this.vendor,
    required this.canWrite,
    this.busy = false,
    this.onCall,
    this.onEmail,
    this.onEdit,
    this.onToggleActive,
  });

  final ContractVendor vendor;
  final bool canWrite;
  final bool busy;
  final VoidCallback? onCall;
  final VoidCallback? onEmail;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleActive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final v = vendor;
    final contact = v.contactName?.trim() ?? '';
    final phone = v.phone?.trim() ?? '';
    final email = v.email?.trim() ?? '';
    final tax = v.taxNo?.trim() ?? '';
    final note = v.note?.trim() ?? '';
    final count = v.contractCount;
    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(
                  icon: contractCategoryIcon(v.category),
                  tone: v.isActive ? AppTone.primary : AppTone.neutral,
                  gap: AppSpace.md,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xs,
                        children: [
                          StatusChip(
                            label: v.isActive ? 'Aktif' : 'Pasif',
                            tone: v.isActive ? AppTone.success : AppTone.neutral,
                            icon: v.isActive
                                ? Icons.check_circle_outline_rounded
                                : Icons.pause_circle_outline_rounded,
                          ),
                          InfoChip(v.category.label),
                        ],
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        v.displayName,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: th.titleMedium,
                      ),
                      if (contact.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          'Yetkili: $contact',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: th.bodyMedium?.copyWith(color: p.textSecondary),
                        ),
                      ],
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        count == 0 ? 'Sözleşme yok' : '$count sözleşme',
                        key: ValueKey<String>('contract_vendor_count_${v.id}'),
                        style: th.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                      if (tax.isNotEmpty || note.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xs),
                        Wrap(
                          spacing: AppSpace.sm,
                          runSpacing: AppSpace.xs,
                          children: [if (tax.isNotEmpty) InfoChip('Vergi no: $tax')],
                        ),
                        if (note.isNotEmpty)
                          Text(
                            note,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: th.bodySmall?.copyWith(color: p.textSecondary),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (phone.isNotEmpty || email.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                if (phone.isNotEmpty)
                  TextButton.icon(
                    key: ValueKey<String>('contract_vendor_call_${v.id}'),
                    onPressed: onCall,
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: Text(
                      phone,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      semanticsLabel: 'Ara: $phone',
                    ),
                  ),
                if (email.isNotEmpty)
                  TextButton.icon(
                    key: ValueKey<String>('contract_vendor_mail_${v.id}'),
                    onPressed: onEmail,
                    icon: const Icon(Icons.mail_outline_rounded, size: 18),
                    label: Text(
                      email,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      semanticsLabel: 'E-posta gönder: $email',
                    ),
                  ),
              ],
            ),
          ],
          if (canWrite) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                PrimaryActionButton(
                  key: ValueKey<String>('contract_vendor_edit_${v.id}'),
                  label: 'Düzenle',
                  icon: Icons.edit_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: busy ? null : onEdit,
                ),
                PrimaryActionButton(
                  key: ValueKey<String>('contract_vendor_toggle_${v.id}'),
                  label: v.isActive ? 'Pasife al' : 'Etkinleştir',
                  icon: v.isActive
                      ? Icons.pause_circle_outline_rounded
                      : Icons.play_circle_outline_rounded,
                  variant: v.isActive ? AppButtonVariant.outline : AppButtonVariant.tonal,
                  tone: v.isActive ? AppTone.danger : AppTone.success,
                  expand: false,
                  loading: busy,
                  onPressed: busy ? null : onToggleActive,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Sekmelerin ortak yenileme arayüzü (sayfa kabuğunun aşağı çekip yenilemesi etkin sekmeyi yeniler).
abstract interface class ContractReloadable {
  Future<void> reload();
}

/// Modül kapalı (403 `MODULE_DISABLED`) kartı; [onOpenModules] verilirse Modüller ekranına götüren düğme.
class ContractModuleOffCard extends StatelessWidget {
  const ContractModuleOffCard({super.key, this.onOpenModules});

  final VoidCallback? onOpenModules;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final open = onOpenModules;
    return EmptyCard(
      key: const ValueKey<String>('contract_module_off'),
      icon: Icons.handshake_outlined,
      tone: AppTone.warning,
      title: 'Firma ve sözleşme takibi bu site için kapalı.',
      message: 'Modül açılınca hizmet aldığınız firmalar ve sözleşmelerin bitiş tarihleri burada izlenir.',
      child: open == null
          ? null
          : Column(
              children: [
                Text(
                  'Modüller ekranından açabilir ya da talep edebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: th.bodyMedium,
                ),
                const SizedBox(height: AppSpace.md),
                PrimaryActionButton(
                  key: const ValueKey<String>('contract_open_modules'),
                  label: 'Modüller',
                  icon: Icons.extension_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: open,
                ),
              ],
            ),
    );
  }
}
