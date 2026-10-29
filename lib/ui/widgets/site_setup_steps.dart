import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/management_terms.dart';
import 'package:site_kapi_kontrol/models/site_setup_progress.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/site_setup_actions.dart';
import 'package:site_kapi_kontrol/ui/views/site_setup_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_setup_parts.dart';

/// Şu anki adımın gövdesi: durum, kısa açıklama ve MEVCUT ekran / formları açan eylemler (P2-15).
///
/// Sihirbaz formları yeniden yazmaz; her adım var olan akışı açar ([SiteSetupActions]) ve dönünce durumu sunucudan
/// yeniden okur. Metinler sitenin yönetim türü terimleriyle yazılır (Blok -> Kat, Daire -> Ofis, Aidat -> Ortak gider).
class SiteSetupStepBody extends StatelessWidget {
  const SiteSetupStepBody({super.key, required this.controller});

  final SiteSetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return switch (c.current) {
      SiteSetupStep.siteInfo => _SiteInfoStep(controller: c),
      SiteSetupStep.blocks => _BlocksStep(controller: c),
      SiteSetupStep.apartments => _ApartmentsStep(controller: c),
      SiteSetupStep.people => _PeopleStep(controller: c),
      SiteSetupStep.modules => _ModulesStep(controller: c),
      SiteSetupStep.finance => _FinanceStep(controller: c),
    };
  }
}

/// Adımın verisi okunamadıysa kart içi hata ("durum alınamadı" + Tekrar Dene); aksi halde null.
Widget? _errorNotice(SiteSetupController c, SiteSetupStep step) {
  final error = c.snapshot.errorOf(step);
  if (error == null) return null;
  return InlineNotice(
    key: ValueKey<String>('site_setup_error_${step.name}'),
    message: error,
    onRetry: c.loading ? null : () => unawaited(c.refresh()),
  );
}

/// Yalnız süper kullanıcının site kaydını değiştirebildiğini açıklayan bilgi (sunucu yöneticiye 403 verir).
const InlineNotice _managerReadOnlyNotice = InlineNotice(
  key: ValueKey<String>('site_setup_manager_readonly'),
  tone: AppTone.info,
  message:
      'Site adı, adres ve yapı bilgilerini yalnızca sistem yöneticisi değiştirir. Bir düzeltme gerekiyorsa '
      '“Yardım ve Destek” bölümünden bize ulaşın.',
);

String _plural(int count, String singularLower) => '$count $singularLower';

/// Adımın ana eylem düğmesinin görünümü. Sayfada TEK vurgulu (dolu) düğme olur (tasarım dili §3): adım yapılmadıysa ana
/// eylem doludur ("Devam" henüz pasif); adım tamamsa ana eylem ikincil olur ve dolu düğme gezinmedeki "Devam"dır.
AppButtonVariant _primaryVariant(SiteSetupController c, SiteSetupStep step) =>
    c.statusOf(step) == SiteSetupStatus.done ? AppButtonVariant.tonal : AppButtonVariant.filled;

class _SiteInfoStep extends StatelessWidget {
  const _SiteInfoStep({required this.controller});

  final SiteSetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final site = c.snapshot.structure?.site;
    final city = <String>[
      if ((site?.city ?? '').trim().isNotEmpty) site!.city!.trim(),
      if ((site?.district ?? '').trim().isNotEmpty) site!.district!.trim(),
    ].join(' / ');
    final address = (site?.address ?? '').trim();
    return SetupStepCard(
      step: SiteSetupStep.siteInfo,
      title: siteSetupStepTitle(SiteSetupStep.siteInfo, c.snapshot.terms),
      status: c.statusOf(SiteSetupStep.siteInfo),
      description: 'Sitenizin adı, türü ve adresi aşağıda. Bilgiler doğruysa devam edin.',
      facts: <String>[
        if (site != null) ...[
          c.displayName,
          site.managementTypeLabel,
          if (city.isNotEmpty) city,
          if (address.isNotEmpty) address,
        ],
      ],
      notice: _errorNotice(c, SiteSetupStep.siteInfo) ?? (c.isSuperUser ? null : _managerReadOnlyNotice),
      actions: <Widget>[
        if (c.isSuperUser && site != null)
          PrimaryActionButton(
            key: const ValueKey<String>('site_setup_edit_site'),
            label: 'Site bilgilerini düzenle',
            icon: Icons.edit_outlined,
            variant: AppButtonVariant.tonal,
            onPressed: () => unawaited(SiteSetupActions.editSite(context, c)),
          ),
      ],
    );
  }
}

class _BlocksStep extends StatelessWidget {
  const _BlocksStep({required this.controller});

  final SiteSetupController controller;

  static const int _maxListed = 8;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final terms = c.snapshot.terms;
    final structure = c.snapshot.structure;
    final blockLower = terms.blockLower;
    final unitLower = terms.unitLower;
    final blocks = structure?.blocks ?? const [];
    final facts = <String>[];
    if (structure != null) {
      facts.add(_plural(blocks.length, blockLower));
      for (final block in blocks.take(_maxListed)) {
        final count = structure.apartments.where((a) => a.blockId == block.id).length;
        facts.add('${block.blockName} · ${_plural(count, unitLower)}');
      }
      if (blocks.length > _maxListed) facts.add('+${blocks.length - _maxListed} ${terms.blockPluralLower} daha');
    }
    final empty = structure != null && blocks.isEmpty;
    return SetupStepCard(
      step: SiteSetupStep.blocks,
      title: siteSetupStepTitle(SiteSetupStep.blocks, terms),
      status: c.statusOf(SiteSetupStep.blocks),
      description:
          '${terms.blockPlural} ve her birindeki $unitLower sayısı. Eksik ya da yanlış bir şey varsa düzeltin; '
          'yoksa devam edin.',
      facts: facts,
      notice:
          _errorNotice(c, SiteSetupStep.blocks) ??
          (empty
              ? InlineNotice(
                  key: const ValueKey<String>('site_setup_blocks_empty'),
                  tone: AppTone.warning,
                  message: 'Bu sitede henüz $blockLower tanımlı değil.',
                )
              : (c.isSuperUser ? null : _managerReadOnlyNotice)),
      actions: <Widget>[
        if (c.isSuperUser && structure != null)
          PrimaryActionButton(
            key: const ValueKey<String>('site_setup_edit_blocks'),
            label: '${terms.blockPlural} ve $unitLower sayılarını düzenle',
            icon: Icons.edit_outlined,
            variant: AppButtonVariant.tonal,
            onPressed: () => unawaited(SiteSetupActions.editSite(context, c)),
          ),
      ],
    );
  }
}

class _ApartmentsStep extends StatelessWidget {
  const _ApartmentsStep({required this.controller});

  final SiteSetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final terms = c.snapshot.terms;
    final count = c.snapshot.apartmentCount;
    return SetupStepCard(
      step: SiteSetupStep.apartments,
      title: siteSetupStepTitle(SiteSetupStep.apartments, terms),
      status: c.statusOf(SiteSetupStep.apartments),
      description:
          '${terms.unitPlural} sitenin temel kaydıdır. Kat, tip ve arsa payı gibi ayrıntıları ve sakinleri Excel ile '
          'toplu doldurabilirsiniz.',
      facts: <String>[if (count != null) _plural(count, terms.unitLower)],
      notice: _errorNotice(c, SiteSetupStep.apartments),
      actions: <Widget>[
        PrimaryActionButton(
          key: const ValueKey<String>('site_setup_apartments_excel'),
          label: "Excel'den yükle",
          icon: Icons.upload_file_rounded,
          variant: _primaryVariant(c, SiteSetupStep.apartments),
          onPressed: () => unawaited(SiteSetupActions.importFromExcel(context, c)),
        ),
        PrimaryActionButton(
          key: const ValueKey<String>('site_setup_apartments_list'),
          label: '${terms.unitPlural} listesini aç',
          icon: Icons.apartment_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: () => unawaited(SiteSetupActions.openPeople(context, c, tab: 1)),
        ),
      ],
    );
  }
}

class _PeopleStep extends StatelessWidget {
  const _PeopleStep({required this.controller});

  final SiteSetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final terms = c.snapshot.terms;
    final count = c.snapshot.peopleCount;
    return SetupStepCard(
      step: SiteSetupStep.people,
      title: siteSetupStepTitle(SiteSetupStep.people, terms),
      status: c.statusOf(SiteSetupStep.people),
      description:
          '${terms.owner}, ${ManagementTerms.lowerTr(terms.resident)} ve diğer kişileri ekleyin. En hızlı yol Excel ile '
          'toplu yüklemedir: şablonda sitenizin ${terms.blockLower} ve ${terms.unitLower} numaraları hazır gelir.',
      facts: <String>[if (count != null) (count == 0 ? 'Henüz kişi yok' : '$count kişi kayıtlı')],
      notice: _errorNotice(c, SiteSetupStep.people),
      actions: <Widget>[
        PrimaryActionButton(
          key: const ValueKey<String>('site_setup_people_excel'),
          label: "Excel'den yükle",
          icon: Icons.upload_file_rounded,
          variant: _primaryVariant(c, SiteSetupStep.people),
          onPressed: () => unawaited(SiteSetupActions.importFromExcel(context, c)),
        ),
        PrimaryActionButton(
          key: const ValueKey<String>('site_setup_people_manual'),
          label: 'Kişileri tek tek ekle',
          icon: Icons.person_add_alt_1_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: () => unawaited(SiteSetupActions.openPeople(context, c)),
        ),
      ],
    );
  }
}

class _ModulesStep extends StatelessWidget {
  const _ModulesStep({required this.controller});

  final SiteSetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final modules = c.snapshot.modules;
    final facts = <String>[];
    if (modules != null) {
      final core = modules.modules.where((m) => m.core).length;
      final optionalOn = modules.modules.where((m) => !m.core && m.isAvailable && m.enabled).length;
      final pending = modules.modules.where((m) => !m.core && m.hasPendingRequest && !m.enabled).length;
      final recommended = modules.modules
          .where((m) => !m.core && m.recommended && m.isAvailable && !m.enabled)
          .map((m) => m.name)
          .toList(growable: false);
      facts.add('$core temel modül açık');
      facts.add('$optionalOn isteğe bağlı modül açık');
      if (pending > 0) facts.add('$pending talep bekliyor');
      if (recommended.isNotEmpty) facts.add('Önerilen: ${recommended.join(', ')}');
    }
    return SetupStepCard(
      step: SiteSetupStep.modules,
      title: siteSetupStepTitle(SiteSetupStep.modules, c.snapshot.terms),
      status: c.statusOf(SiteSetupStep.modules),
      description: c.isSuperUser
          ? 'Temel modüller her sitede açıktır ve kapatılamaz. Diğer modülleri bu site için açıp kapatabilirsiniz.'
          : 'Temel modüller her sitede açıktır. İhtiyacınız olan diğer modülleri talep edebilirsiniz; talepleriniz '
                'sistem yöneticisine iletilir.',
      facts: facts,
      notice: _errorNotice(c, SiteSetupStep.modules),
      actions: <Widget>[
        PrimaryActionButton(
          key: const ValueKey<String>('site_setup_modules_open'),
          label: c.isSuperUser ? 'Modülleri seç' : 'Modülleri seç / talep et',
          icon: Icons.extension_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: () => unawaited(SiteSetupActions.openModules(context, c)),
        ),
      ],
    );
  }
}

class _FinanceStep extends StatelessWidget {
  const _FinanceStep({required this.controller});

  final SiteSetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final terms = c.snapshot.terms;
    final count = c.snapshot.feeDefinitionCount;
    final period = c.snapshot.openPeriodLabel;
    final fee = terms.fee;
    return SetupStepCard(
      step: SiteSetupStep.finance,
      title: siteSetupStepTitle(SiteSetupStep.finance, terms),
      status: c.statusOf(SiteSetupStep.finance),
      description:
          '$fee tanımını ekleyin; ardından Finans ekranından borçlandırırsınız. Eski yazılımdan devreden borç '
          'varsa devir bakiyesini Excel ile yükleyebilirsiniz.',
      facts: <String>[
        if (count != null) (count == 0 ? 'Henüz tanım yok' : _plural(count, '${ManagementTerms.lowerTr(fee)} tanımı')),
        if (period != null && period.isNotEmpty) 'Açık dönem: $period',
      ],
      notice: _errorNotice(c, SiteSetupStep.finance),
      actions: <Widget>[
        PrimaryActionButton(
          key: const ValueKey<String>('site_setup_finance_definition'),
          label: '$fee tanımı ekle',
          icon: Icons.request_quote_rounded,
          variant: _primaryVariant(c, SiteSetupStep.finance),
          onPressed: () => unawaited(SiteSetupActions.addFeeDefinition(context, c)),
        ),
        PrimaryActionButton(
          key: const ValueKey<String>('site_setup_finance_opening'),
          label: 'Devir bakiyesi yükle',
          icon: Icons.upload_file_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: () => unawaited(SiteSetupActions.openOpeningBalances(context, c)),
        ),
        PrimaryActionButton(
          key: const ValueKey<String>('site_setup_finance_open'),
          label: 'Finans ekranını aç',
          icon: Icons.account_balance_wallet_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: () => unawaited(SiteSetupActions.openFinance(context, c)),
        ),
      ],
    );
  }
}
