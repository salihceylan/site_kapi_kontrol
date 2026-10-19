// Karar Defteri ortak parçaları: numara / taslak çipi, oylama sonucu çipi, "Sakinlere açık" işareti, yasal not, "modül
// kapalı" kartı, kurul notu, yıl başlığı ve liste kartı.
//
// Kurallar: metinler sarar ya da elips olur (320 dp x 2,0'da taşma yok); durum yalnız renkle verilmez (etiket + ikon);
// ham renk yok; karar metni günlüğe yazılmaz.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatCrmDate;
import 'package:site_kapi_kontrol/ui/helpers/decision_loader.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

AppTone decisionVoteTone(DecisionVoteResult result) => switch (result) {
  DecisionVoteResult.kabul => AppTone.success,
  DecisionVoteResult.ret => AppTone.danger,
  DecisionVoteResult.ertelendi => AppTone.warning,
  DecisionVoteResult.bilgi => AppTone.info,
  DecisionVoteResult.unknown => AppTone.neutral,
};

IconData decisionVoteIcon(DecisionVoteResult result) => switch (result) {
  DecisionVoteResult.kabul => Icons.check_circle_outline_rounded,
  DecisionVoteResult.ret => Icons.cancel_outlined,
  DecisionVoteResult.ertelendi => Icons.schedule_rounded,
  DecisionVoteResult.bilgi => Icons.info_outline_rounded,
  DecisionVoteResult.unknown => Icons.help_outline_rounded,
};

/// "05.03.2026 · Yönetim Kurulu".
String decisionMeetingText(Decision d) => '${formatCrmDate(d.meetingDate)} · ${d.meetingType.label}';

/// Kesin kararda numara ("2026/3"), taslakta "Taslak" çipi.
class DecisionNumberChip extends StatelessWidget {
  const DecisionNumberChip({super.key, required this.decision});

  final Decision decision;

  @override
  Widget build(BuildContext context) {
    if (decision.isFinal) {
      return StatusChip(label: decision.displayNumber, tone: AppTone.primary, icon: Icons.tag_rounded);
    }
    return StatusChip(
      label: decision.isDraft ? 'Taslak' : decision.status.label,
      tone: AppTone.neutral,
      icon: Icons.edit_note_rounded,
    );
  }
}

class DecisionVoteChip extends StatelessWidget {
  const DecisionVoteChip({super.key, required this.result});

  final DecisionVoteResult result;

  @override
  Widget build(BuildContext context) =>
      StatusChip(label: result.label, tone: decisionVoteTone(result), icon: decisionVoteIcon(result));
}

/// "Sakinlere açık" işareti (yalnız yönetim görünümü).
class DecisionResidentsMarker extends StatelessWidget {
  const DecisionResidentsMarker({super.key});

  @override
  Widget build(BuildContext context) =>
      const StatusChip(label: 'Sakinlere açık', tone: AppTone.info, icon: Icons.groups_rounded);
}

/// Her Karar Defteri ekranında görünen yasal not ([kDecisionLegalNotice]).
class DecisionLegalNote extends StatelessWidget {
  const DecisionLegalNote({super.key});

  @override
  Widget build(BuildContext context) => const InlineNotice(
    key: ValueKey<String>('decision_legal_notice'),
    tone: AppTone.warning,
    icon: Icons.gavel_rounded,
    message: kDecisionLegalNotice,
  );
}

/// Kurul (salt okur) notu.
class DecisionReadOnlyNote extends StatelessWidget {
  const DecisionReadOnlyNote({super.key});

  @override
  Widget build(BuildContext context) => const InlineNotice(
    key: ValueKey<String>('decision_read_only_note'),
    tone: AppTone.info,
    icon: Icons.visibility_rounded,
    message: 'Yönetim kurulu üyesi olarak kararları (taslaklar dahil) yalnızca görüntüleyebilirsiniz.',
  );
}

/// Modül kapalı (403 `MODULE_DISABLED`) açıklayıcı kartı; [onOpenModules] verilirse "Modüller" düğmesi çıkar.
class DecisionModuleOffCard extends StatelessWidget {
  const DecisionModuleOffCard({
    super.key,
    this.message = 'Yönetim bu özelliği açtığında kararlar burada görünür.',
    this.onOpenModules,
  });

  final String message;
  final VoidCallback? onOpenModules;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return EmptyCard(
      key: const ValueKey<String>('decision_module_off'),
      icon: Icons.gavel_rounded,
      tone: AppTone.warning,
      title: 'Karar Defteri bu site için kapalı.',
      message: message,
      child: onOpenModules == null
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
                  key: const ValueKey<String>('decision_open_modules'),
                  label: 'Modüller',
                  icon: Icons.extension_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: onOpenModules,
                ),
              ],
            ),
    );
  }
}

/// Listede yıl grubu başlığı.
class DecisionYearHeader extends StatelessWidget {
  const DecisionYearHeader({super.key, required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Row(
          children: [
            Icon(Icons.calendar_month_rounded, size: 18, color: p.textSecondary),
            const SizedBox(width: AppSpace.xs),
            Flexible(
              child: Text(
                year > 0 ? '$year' : 'Yılı bilinmeyen',
                style: th.titleSmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liste kartı: numara / taslak, oylama sonucu, (yönetimde) "Sakinlere açık", başlık, tarih + toplantı türü ve
/// değiştirildiyse "X sayılı kararla değiştirildi".
class DecisionCard extends StatelessWidget {
  const DecisionCard({
    super.key,
    required this.decision,
    required this.onTap,
    this.showManagerMarkers = true,
    this.siteLabel,
  });

  final Decision decision;
  final VoidCallback onTap;

  /// Yönetim görünümü: "Sakinlere açık" işareti.
  final bool showManagerMarkers;

  /// Sakin görünümünde birden çok site varsa site adı (null: gösterilmez).
  final String? siteLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final d = decision;
    final superseded = d.supersededText;
    final number = d.isFinal ? 'Karar ${d.displayNumber}' : 'Taslak karar';
    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: <String>[
        number,
        d.title,
        decisionMeetingText(d),
        d.voteResult.label,
        if (showManagerMarkers && d.isVisibleToResidents) 'Sakinlere açık',
        ?siteLabel,
        ?superseded,
      ].join(', '),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              icon: d.isFinal ? Icons.gavel_rounded : Icons.edit_note_rounded,
              tone: d.isFinal ? AppTone.primary : AppTone.neutral,
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
                      DecisionNumberChip(decision: d),
                      DecisionVoteChip(result: d.voteResult),
                      if (showManagerMarkers && d.isVisibleToResidents) const DecisionResidentsMarker(),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(d.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: th.titleMedium),
                  const SizedBox(height: AppSpace.xs),
                  Text(decisionMeetingText(d), style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  if (siteLabel != null && siteLabel!.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      siteLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ],
                  if (superseded != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    Row(
                      key: ValueKey<String>('decision_superseded_${d.id}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.swap_horiz_rounded, size: 18, color: AppTone.warning.ink(p)),
                        const SizedBox(width: AppSpace.xs),
                        Expanded(
                          child: Text(
                            superseded,
                            style: th.bodySmall?.copyWith(color: AppTone.warning.ink(p), fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
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

/// Yıl seçici açılır listesi: "Tüm yıllar" + [years] (seçili yıl listede olmasa da gösterilir).
class DecisionYearDropdown extends StatelessWidget {
  const DecisionYearDropdown({
    super.key,
    required this.years,
    required this.selected,
    required this.onChanged,
    this.fieldKey = 'decision_year',
  });

  final List<int> years;
  final int? selected;
  final ValueChanged<int?> onChanged;
  final String fieldKey;

  static const int _all = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final options = <int>{...years, ?selected}.toList()..sort((a, b) => b.compareTo(a));
    return DropdownButtonFormField<int>(
      key: ValueKey<String>('${fieldKey}_${selected ?? _all}_${options.length}'),
      isExpanded: true,
      initialValue: selected ?? _all,
      dropdownColor: p.surface,
      style: th.bodyMedium?.copyWith(color: p.text),
      decoration: const InputDecoration(labelText: 'Yıl', prefixIcon: Icon(Icons.calendar_month_rounded)),
      items: [
        const DropdownMenuItem<int>(
          value: _all,
          child: Text('Tüm yıllar', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        for (final y in options)
          DropdownMenuItem<int>(value: y, child: Text('$y', maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (value) {
        if (value == null) return;
        final next = value == _all ? null : value;
        if (next != selected) onChanged(next);
      },
    );
  }
}

/// Kartları yıl başlıklarıyla dizer: yıllar yeniden eskiye (yılı bilinmeyenler sonda), her yılın içinde sunucu sırası
/// korunur. Sunucu yönetim listesinde önce taslakları, sonra kesin kararları verir (yıllar iki kez geçer); burada aynı
/// yılın taslakları ve kesin kararları tek başlık altında toplanır.
List<Widget> decisionCardsByYear(List<Decision> items, Widget Function(Decision d) card) {
  final groups = <int, List<Decision>>{};
  for (final d in items) {
    groups.putIfAbsent(d.effectiveYear, () => <Decision>[]).add(d);
  }
  final years = groups.keys.toList()
    ..sort((a, b) {
      if (a <= 0 || b <= 0) return a <= 0 ? (b <= 0 ? 0 : 1) : -1;
      return b.compareTo(a);
    });
  final out = <Widget>[];
  for (final y in years) {
    if (out.isNotEmpty) out.add(const SizedBox(height: AppSpace.sm));
    out.add(DecisionYearHeader(key: ValueKey<String>('decision_year_header_$y'), year: y));
    for (final d in groups[y]!) {
      out
        ..add(card(d))
        ..add(const SizedBox(height: AppSpace.md));
    }
  }
  return out;
}

/// Liste gövdesi: iskelet / hata + "Tekrar Dene" / boş durum / yıl başlıklı kartlar + "Daha fazla yükle". İskelet
/// YALNIZ ilk yükleme sürerken; liste boşken hata varsa "karar yok" yerine hata gösterilir.
class DecisionListBody extends StatelessWidget {
  const DecisionListBody({
    super.key,
    required this.loader,
    required this.cardBuilder,
    required this.emptyTitle,
    this.emptyMessage,
  });

  final DecisionListLoader loader;
  final Widget Function(Decision d) cardBuilder;
  final String emptyTitle;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final items = loader.items;
    final error = loader.error;
    if (items.isEmpty) {
      if (loader.loading || (error == null && !loader.loadedOnce)) return const ListSkeleton(rows: 2);
      if (error != null) {
        return EmptyCard(
          key: const ValueKey<String>('decision_error'),
          icon: Icons.cloud_off_rounded,
          tone: AppTone.danger,
          title: error,
          child: TextButton.icon(
            onPressed: loader.loading ? null : loader.reload,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tekrar Dene'),
          ),
        );
      }
      return EmptyCard(
        key: const ValueKey<String>('decision_empty'),
        icon: Icons.gavel_outlined,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          InlineNotice(message: error, onRetry: loader.reload),
          const SizedBox(height: AppSpace.md),
        ],
        ...decisionCardsByYear(items, cardBuilder),
        if (loader.moreError != null) ...[
          InlineNotice(message: loader.moreError!, onRetry: loader.loadMore),
          const SizedBox(height: AppSpace.md),
        ],
        if (loader.hasMore)
          Align(
            alignment: Alignment.center,
            child: PrimaryActionButton(
              key: const ValueKey<String>('decision_more'),
              label: 'Daha fazla yükle',
              icon: Icons.expand_more_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              loading: loader.loadingMore,
              onPressed: (loader.loadingMore || loader.loading) ? null : loader.loadMore,
            ),
          ),
      ],
    );
  }
}
