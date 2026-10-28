import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/management_terms.dart';
import 'package:site_kapi_kontrol/models/site_setup_progress.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/site_setup_controller.dart' show SiteSetupStatus;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Adımın kullanıcıya görünen başlığı. Blok ve daire adımları sitenin yönetim türünün terimleriyle yazılır
/// (Blok -> Kat, Daire -> Ofis ...); iş mantığı ve kayıt adları değişmez.
String siteSetupStepTitle(SiteSetupStep step, ManagementTerms terms) => switch (step) {
  SiteSetupStep.siteInfo => 'Site bilgileri',
  SiteSetupStep.blocks => terms.blockPlural,
  SiteSetupStep.apartments => terms.unitPlural,
  SiteSetupStep.people => 'Kişiler',
  SiteSetupStep.modules => 'Modüller',
  SiteSetupStep.finance => 'Finans açılışı',
};

IconData siteSetupStepIcon(SiteSetupStep step) => switch (step) {
  SiteSetupStep.siteInfo => Icons.location_city_rounded,
  SiteSetupStep.blocks => Icons.domain_rounded,
  SiteSetupStep.apartments => Icons.apartment_rounded,
  SiteSetupStep.people => Icons.groups_2_rounded,
  SiteSetupStep.modules => Icons.extension_rounded,
  SiteSetupStep.finance => Icons.account_balance_wallet_rounded,
};

/// Durum çipinin metni (renk tek başına anlam taşımaz: metin + nokta).
String siteSetupStatusLabel(SiteSetupStatus status) => switch (status) {
  SiteSetupStatus.done => 'Tamam',
  SiteSetupStatus.skipped => 'Atlandı',
  SiteSetupStatus.open => 'Yapılmadı',
  SiteSetupStatus.unknown => 'Durum alınamadı',
};

AppTone siteSetupStatusTone(SiteSetupStatus status) => switch (status) {
  SiteSetupStatus.done => AppTone.success,
  SiteSetupStatus.skipped => AppTone.warning,
  SiteSetupStatus.open => AppTone.neutral,
  SiteSetupStatus.unknown => AppTone.danger,
};

/// Adım durumu rozeti: nokta + kısa metin.
class SiteSetupStatusChip extends StatelessWidget {
  const SiteSetupStatusChip({super.key, required this.status});

  final SiteSetupStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusChip(label: siteSetupStatusLabel(status), tone: siteSetupStatusTone(status));
  }
}

/// Sihirbaz adım göstergesi: adım başına bir dilim (dekoratif) + "Adım 3 / 6 · Daireler" başlığı.
///
/// Başlık TEK anlamsal başlıktır (canlı bölge): adım değişince ekran okuyucu yeni adımı okur ve [focusNode] ile
/// odak oraya taşınır ([BulkStepHeader] kalıbı). Dilim rengi: tamamlanan ve şu anki adım dolu, atlanan uyarı rengi,
/// kalan boş; anlam başlıkta ve adım kartındaki durum çipindedir. [summary] true iken başlık özet başlığıdır.
class SiteSetupStepHeader extends StatelessWidget {
  const SiteSetupStepHeader({
    super.key,
    required this.step,
    required this.terms,
    required this.statuses,
    this.focusNode,
    this.summary = false,
  });

  final SiteSetupStep step;
  final ManagementTerms terms;

  /// Her adımın durumu (sıra: [SiteSetupStep.values]).
  final List<SiteSetupStatus> statuses;
  final FocusNode? focusNode;
  final bool summary;

  static String titleOf(SiteSetupStep step, ManagementTerms terms) =>
      'Adım ${step.index + 1} / ${SiteSetupProgress.stepCount} · ${siteSetupStepTitle(step, terms)}';

  static const String summaryTitle = 'Kurulum özeti';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final title = summary ? summaryTitle : titleOf(step, terms);
    Color segment(int i) {
      final status = i < statuses.length ? statuses[i] : SiteSetupStatus.open;
      if (!summary && i == step.index) return AppTone.primary.hue;
      return switch (status) {
        SiteSetupStatus.done => AppTone.primary.hue,
        SiteSetupStatus.skipped => AppTone.warning.hue,
        _ => p.border,
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < SiteSetupProgress.stepCount; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: segment(i),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const SizedBox(height: 5),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Focus(
          focusNode: focusNode,
          child: Semantics(
            header: true,
            liveRegion: true,
            container: true,
            label: title,
            child: ExcludeSemantics(
              child: Text(
                title,
                key: const ValueKey<String>('site_setup_step_title'),
                style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bir adımın kartı: ikon + başlık + durum çipi, açıklama, olgu çipleri, isteğe bağlı bildirim ve eylemler.
///
/// Eylemler (düğmeler) çağıranındır; kart alt alta dizer. Sabit genişlik yoktur: metinler sarar, çipler `Wrap`te akar.
class SetupStepCard extends StatelessWidget {
  const SetupStepCard({
    super.key,
    required this.step,
    required this.title,
    required this.status,
    required this.description,
    this.facts = const <String>[],
    this.notice,
    this.actions = const <Widget>[],
  });

  final SiteSetupStep step;
  final String title;
  final SiteSetupStatus status;
  final String description;

  /// Kısa olgu çipleri ("2 blok", "20 daire").
  final List<String> facts;

  /// Kart içi bildirim (hata + "Tekrar Dene", bilgi ...).
  final Widget? notice;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return AppCard(
      key: ValueKey<String>('site_setup_card_${step.name}'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                icon: siteSetupStepIcon(step),
                tone: siteSetupStatusTone(status),
                size: 44,
                gap: AppSpace.md,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: th.titleMedium),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    SiteSetupStatusChip(status: status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(description, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [for (final fact in facts) InfoChip(fact)],
            ),
          ],
          if (notice != null) ...[const SizedBox(height: AppSpace.md), notice!],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpace.lg),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpace.sm),
              actions[i],
            ],
          ],
        ],
      ),
    );
  }
}
