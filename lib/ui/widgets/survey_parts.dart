// Anket ve Oylama ortak parçaları: durum çipi, sonuç çubuğu (tamsayı yüzde), "modül kapalı" kartı, sakin oy kartı.
//
// Kurallar: metinler sarar ya da elips olur (320 dp x 2,0'da taşma yok); durum yalnız renkle verilmez (etiket +
// ikon); ham renk yok; oy içeriği günlüğe yazılmaz.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/survey_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

AppTone surveyStatusTone(SurveyStatus status) => switch (status) {
  SurveyStatus.draft => AppTone.neutral,
  SurveyStatus.open => AppTone.success,
  SurveyStatus.closed => AppTone.info,
  SurveyStatus.unknown => AppTone.neutral,
};

IconData surveyStatusIcon(SurveyStatus status) => switch (status) {
  SurveyStatus.draft => Icons.edit_note_rounded,
  SurveyStatus.open => Icons.how_to_vote_rounded,
  SurveyStatus.closed => Icons.lock_outline_rounded,
  SurveyStatus.unknown => Icons.help_outline_rounded,
};

class SurveyStatusChip extends StatelessWidget {
  const SurveyStatusChip({super.key, required this.status, this.expired = false});

  final SurveyStatus status;

  /// Süresi dolmuş açık anket: "Süresi doldu" (sunucu `closed` okur).
  final bool expired;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: expired ? 'Süresi doldu' : status.label,
    tone: expired ? AppTone.warning : surveyStatusTone(status),
    icon: expired ? Icons.timer_off_outlined : surveyStatusIcon(status),
  );
}

/// Kapanış metni: "Kapanış: 20.10.2026 18:00" ya da "Kapanış tarihi yok".
String surveyClosesText(DateTime? closesAt) =>
    closesAt == null ? 'Kapanış tarihi yok' : 'Kapanış: ${formatIstanbulDateTime(closesAt)}';

/// Tek sonuç çubuğu: seçenek metni, oy sayısı ve TAMSAYI yüzde; [highlighted] benim oyum.
class SurveyResultBar extends StatelessWidget {
  const SurveyResultBar({
    super.key,
    required this.label,
    required this.count,
    required this.percent,
    this.highlighted = false,
  });

  final String label;
  final int count;
  final int percent;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final tone = highlighted ? AppTone.primary : AppTone.info;
    final clamped = percent < 0 ? 0 : (percent > 100 ? 100 : percent);
    return Semantics(
      label: '$label: $count oy, yüzde $clamped${highlighted ? ', sizin oyunuz' : ''}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (highlighted) ...[
                  Icon(Icons.check_circle_rounded, size: 18, color: tone.ink(p)),
                  const SizedBox(width: AppSpace.xs),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: th.bodyMedium?.copyWith(fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Text(
                  '%$clamped · $count',
                  style: th.bodySmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: clamped / 100,
                minHeight: 8,
                backgroundColor: tone.tint(p),
                valueColor: AlwaysStoppedAnimation<Color>(tone.ink(p)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tüm seçeneklerin çubukları + toplam satırı.
class SurveyResultBars extends StatelessWidget {
  const SurveyResultBars({super.key, required this.options, required this.results, this.myVote});

  final List<String> options;
  final SurveyResults results;
  final int? myVote;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final participation = results.participationPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          SurveyResultBar(
            key: ValueKey<String>('survey_bar_$i'),
            label: options[i].isEmpty ? 'Seçenek ${i + 1}' : options[i],
            count: results.countAt(i),
            percent: results.percentAt(i),
            highlighted: myVote == i,
          ),
          if (i < options.length - 1) const SizedBox(height: AppSpace.sm),
        ],
        const SizedBox(height: AppSpace.sm),
        Text(
          participation == null
              ? 'Toplam ${results.totalVotes} oy'
              : 'Toplam ${results.totalVotes} oy · ${results.eligibleCount} kişiden %$participation katılım',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }
}

/// Modül kapalı (403 `MODULE_DISABLED`) açıklayıcı kartı; [onOpenModules] verilirse "Modüller" düğmesi çıkar.
class SurveyModuleOffCard extends StatelessWidget {
  const SurveyModuleOffCard({
    super.key,
    this.message = 'Yönetim bu özelliği açtığında anketler ve oylamalar burada görünür.',
    this.onOpenModules,
  });

  final String message;
  final VoidCallback? onOpenModules;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return EmptyCard(
      key: const ValueKey<String>('survey_module_off'),
      icon: Icons.poll_outlined,
      tone: AppTone.warning,
      title: 'Anket ve Oylama bu site için kapalı.',
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
                  key: const ValueKey<String>('survey_open_modules'),
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

/// Kurul (salt okur) notu.
class SurveyReadOnlyNote extends StatelessWidget {
  const SurveyReadOnlyNote({super.key});

  @override
  Widget build(BuildContext context) => const InlineNotice(
    key: ValueKey<String>('survey_read_only_note'),
    tone: AppTone.info,
    icon: Icons.visibility_rounded,
    message: 'Yönetim kurulu üyesi olarak anketleri ve sonuçları yalnızca görüntüleyebilirsiniz. Oy verenler görünmez.',
  );
}

/// Yönetim liste kartı: başlık, durum çipi, oy sayısı / kitle, kapanış.
class SurveyManagedCard extends StatelessWidget {
  const SurveyManagedCard({super.key, required this.item, required this.onTap});

  final SurveySummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final votes = item.eligibleCount > 0
        ? '${item.totalVotes} / ${item.eligibleCount} oy'
        : '${item.totalVotes} oy';
    final status = item.isExpired ? 'Süresi doldu' : item.status.label;
    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: '${item.title}, $status, $votes, ${surveyClosesText(item.closesAt)}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(icon: surveyStatusIcon(item.status), tone: surveyStatusTone(item.status), gap: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      SurveyStatusChip(status: item.status, expired: item.isExpired),
                      if (!item.anonymous) const StatusChip(label: 'Açık oy', tone: AppTone.warning, icon: Icons.badge_outlined),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(item.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: th.titleMedium),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    '$votes · ${surveyClosesText(item.closesAt)}',
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sakin kartı: açık ve oy verilmemişse seçenekler + "Oy ver"; aksi halde (oy verilmiş / kapalı) sonuç çubukları.
class SurveyVoteCard extends StatefulWidget {
  const SurveyVoteCard({super.key, required this.item, required this.onVote, this.showSite = false});

  final SurveyResidentItem item;

  /// Seçilen seçenek için oy gönderir; başarıda true döner (onay ekranı çağıranda).
  final Future<bool> Function(int optionIndex) onVote;
  final bool showSite;

  @override
  State<SurveyVoteCard> createState() => _SurveyVoteCardState();
}

class _SurveyVoteCardState extends State<SurveyVoteCard> {
  int? _selected;
  bool _busy = false;

  Future<void> _submit() async {
    final index = _selected;
    if (index == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onVote(index);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final results = item.results;
    final showResults = item.showsResults && results != null;
    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              SurveyStatusChip(status: item.effectiveStatus),
              if (item.hasVoted)
                const StatusChip(label: 'Oy verildi', tone: AppTone.primary, icon: Icons.check_rounded),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(item.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: th.titleMedium),
          if (widget.showSite && item.siteName.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(item.siteName, maxLines: 1, overflow: TextOverflow.ellipsis, style: th.bodySmall?.copyWith(color: p.textSecondary)),
          ],
          const SizedBox(height: AppSpace.xs),
          Text(item.question, style: th.bodyMedium),
          const SizedBox(height: AppSpace.xs),
          Text(surveyClosesText(item.closesAt), style: th.bodySmall?.copyWith(color: p.textSecondary)),
          const SizedBox(height: AppSpace.md),
          if (showResults)
            SurveyResultBars(options: item.options, results: results, myVote: item.myVote)
          else if (item.canVote) ...[
            RadioGroup<int>(
              groupValue: _selected,
              onChanged: _busy ? (_) {} : (v) => setState(() => _selected = v),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < item.options.length; i++)
                    RadioListTile<int>(
                      key: ValueKey<String>('survey_option_${item.id}_$i'),
                      value: i,
                      enabled: !_busy,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(item.options[i], style: th.bodyMedium),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            PrimaryActionButton(
              key: ValueKey<String>('survey_vote_${item.id}'),
              label: 'Oy ver',
              icon: Icons.how_to_vote_rounded,
              loading: _busy,
              onPressed: _selected == null || _busy ? null : () => unawaited(_submit()),
            ),
          ] else
            Text(
              item.isOpen ? 'Oyunuz alındı. Sonuçlar yükleniyor.' : 'Sonuçlar henüz paylaşılmadı.',
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
        ],
      ),
    );
  }
}
