import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/late_fee_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_late_fee_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_late_fee_lines_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reason_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_settings_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Gecikme tazminatı" bölümü (Dönemler sekmesi; Platform Faz 4b, Ö2): durum kartı (açık / kapalı / hukuk onayı bekleniyor),
/// ayar özeti, sıradaki ay, **Hesapla** (önizleme + onay) ve çalıştırma geçmişi (**Son çalıştırmayı iptal et**).
///
/// - Özellik kullanılamıyorsa ([FinanceFeatureGate]) nedeni açıklayan pasif kart gösterilir; uydurma hukuki iddia YOKTUR.
/// - Çalıştırma listesi başarısızsa "çalıştırma yok" yazılmaz ("Tekrar Dene"). Yalnız SON aktif çalıştırma iptal edilebilir.
/// - Kurul salt okur (hesaplama / iptal / ayar düğmesi yok).
class FinanceLateFeeSection extends StatefulWidget {
  const FinanceLateFeeSection({
    super.key,
    required this.scope,
    required this.settings,
    required this.onOpenSettings,
    required this.onDataChanged,
    this.now,
  });

  final PeopleScope scope;
  final FinanceSettingsController settings;
  final VoidCallback onOpenSettings;
  final VoidCallback onDataChanged;
  final DateTime Function()? now;

  @override
  State<FinanceLateFeeSection> createState() => FinanceLateFeeSectionState();
}

class FinanceLateFeeSectionState extends State<FinanceLateFeeSection> {
  FinancePeriod? _nextPeriod;
  int? _voidableRunId;
  bool _opening = false;
  bool _runsRequested = false;

  late final PagedLoader<LateFeeRun> _loader = PagedLoader<LateFeeRun>(
    fetch: (offset, limit) async {
      final page = await widget.scope.f4Call(
        (api, t, s) => api.listLateFeeRuns(token: t, siteCode: s, limit: limit, offset: offset),
      );
      if (offset == 0 && mounted) {
        _nextPeriod = page.nextPeriod;
        _voidableRunId = page.voidableRunId;
      }
      return (items: page.items, total: page.total);
    },
    keyOf: (r) => r.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    pageSize: 24,
    errorFallback: 'Çalıştırma geçmişi yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    messageOf: financeMessageOf,
  );

  bool get _canWrite => widget.scope.canWrite;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettings);
    _maybeLoadRuns();
  }

  @override
  void didUpdateWidget(FinanceLateFeeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_onSettings);
      widget.settings.addListener(_onSettings);
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    _loader.dispose();
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {});
    _maybeLoadRuns();
  }

  /// Çalıştırma geçmişi yalnız özellik KULLANILABİLİR olunca yüklenir.
  void _maybeLoadRuns() {
    if (_runsRequested) return;
    if (lateFeeAvailability(widget.settings) != FeatureAvailability.ready) return;
    _runsRequested = true;
    unawaited(_loader.reload());
  }

  /// Üst ekran yenilemesi.
  Future<void> reload() async {
    await widget.settings.load();
    if (lateFeeAvailability(widget.settings) == FeatureAvailability.ready) {
      _runsRequested = true;
      await _loader.reload();
    }
  }

  FinancePeriod? get _suggested => _nextPeriod ?? widget.settings.settings?.lateFee.nextPeriod;

  Future<void> _calculate() async {
    if (_opening) return;
    _opening = true;
    try {
      final outcome = await FinanceLateFeeDialog.show(
        context,
        scope: widget.scope,
        initialPeriod: _suggested,
        now: widget.now,
        onRefreshNeeded: _afterChange,
      );
      if (outcome == null || !mounted) return;
      showFinanceSnack(context, outcome.message);
      _afterChange();
    } finally {
      _opening = false;
    }
  }

  void _afterChange() {
    widget.onDataChanged();
    if (!mounted) return;
    unawaited(widget.settings.load());
    unawaited(_loader.reload());
  }

  Future<void> _void(LateFeeRun run) async {
    if (_opening) return;
    _opening = true;
    try {
      final label = run.period?.label ?? 'Seçili ay';
      final text = run.empty
          ? '$label için "tazminat yok" kaydı kaldırılır. Ters çevrilecek borç yoktur. Sonra aynı ay yeniden hesaplanabilir.'
          : '$label tazminat çalıştırması (${run.apartmentCount} daire, ${formatMinor(run.totalMinor)}) iptal edilir: '
                'henüz iptal edilmemiş tüm kalemlere ters kayıt yazılır. Sonra aynı ay yeniden hesaplanabilir.';
      final done = await FinanceReasonDialog.show(
        context,
        title: 'Son Çalıştırmayı İptal Et',
        subtitle: label,
        message: text,
        semanticMessage: spokenMoneyText(text),
        confirmLabel: 'Çalıştırmayı İptal Et',
        signatureBase: 'latefee-void|${run.id}',
        keyPrefix: 'late-v',
        keyOwner: widget.scope.authService,
        onUncertain: _afterChange,
        failure: 'Çalıştırma iptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        action: (reason, key) => widget.scope.f4Call(
          (api, t, s) => api.voidLateFeeRun(token: t, siteCode: s, runId: run.id, reason: reason, idempotencyKey: key),
        ),
      );
      if (!done || !mounted) return;
      showFinanceSnack(context, '$label gecikme tazminatı çalıştırması iptal edildi.');
      _afterChange();
    } finally {
      _opening = false;
    }
  }

  Future<void> _lines(LateFeeRun run) async {
    if (_opening) return;
    _opening = true;
    try {
      await FinanceLateFeeLinesDialog.show(context, scope: widget.scope, run: run);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final controller = widget.settings;
    final availability = lateFeeAvailability(controller);
    return Column(
      key: const ValueKey<String>('finance_latefee_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'Gecikme tazminatı', icon: Icons.gavel_rounded),
        const SizedBox(height: AppSpace.sm),
        if (availability != FeatureAvailability.ready)
          FinanceFeatureGate(
            featureName: 'Gecikme tazminatı',
            availability: availability,
            error: controller.error,
            canWrite: _canWrite,
            onRetry: controller.load,
            onOpenSettings: widget.onOpenSettings,
          )
        else
          ..._buildReady(context, th),
      ],
    );
  }

  List<Widget> _buildReady(BuildContext context, TextTheme th) {
    final p = context.palette;
    final late = widget.settings.settings!.lateFee;
    final suggested = _suggested;
    final current = FinancePeriod.of(istanbulNow(widget.now?.call()));
    return [
      AppCard(
        key: const ValueKey<String>('finance_latefee_status'),
        padding: listCardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: const [
                DialogMetaPill('Açık', tone: AppTone.success, icon: Icons.check_circle_rounded),
                DialogMetaPill('Önizleme ve onayla çalışır', icon: Icons.verified_user_rounded),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Oran ${formatRateBp(late.rateBp)} aylık • ${late.method.label} • vadeye ek ${late.graceDays} gün',
              key: const ValueKey<String>('finance_latefee_settings_line'),
              style: th.bodyMedium,
            ),
            if (late.startPeriod != null)
              Text('İlk hesaplanacak ay: ${late.startPeriod!.label}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
            Text(
              suggested == null ? 'Sıradaki ay henüz bilinmiyor.' : 'Sıradaki ay: ${suggested.label}',
              key: const ValueKey<String>('finance_latefee_next'),
              style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (suggested != null && suggested >= current)
              Text(
                'Bu ay henüz bitmedi veya kapatılmadı; tazminat yalnızca bitmiş ve kapatılmış ay için hesaplanır.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            if (_canWrite) ...[
              const SizedBox(height: AppSpace.md),
              PrimaryActionButton(
                key: const ValueKey<String>('finance_latefee_calculate'),
                label: 'Hesapla',
                icon: Icons.calculate_rounded,
                onPressed: _calculate,
              ),
              const SizedBox(height: AppSpace.sm),
              PrimaryActionButton(
                key: const ValueKey<String>('finance_latefee_settings'),
                label: 'Finans Ayarları',
                icon: Icons.tune_rounded,
                variant: AppButtonVariant.tonal,
                onPressed: widget.onOpenSettings,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpace.md),
      Semantics(header: true, container: true, child: Text('Çalıştırma geçmişi', style: th.titleMedium)),
      const SizedBox(height: AppSpace.sm),
      CrmListBody<LateFeeRun>(
        loader: _loader,
        emptyIcon: Icons.history_rounded,
        emptyTitle: 'Henüz gecikme tazminatı hesaplanmadı.',
        skeletonRows: 1,
        hideItemsOnError: true,
        itemBuilder: (context, run) => _RunCard(
          run: run,
          onLines: () => _lines(run),
          onVoid: _canWrite && !run.isVoided && run.id == _voidableRunId ? () => _void(run) : null,
          busy: _opening,
        ),
      ),
    ];
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.run, required this.onLines, this.onVoid, this.busy = false});

  final LateFeeRun run;
  final VoidCallback onLines;
  final VoidCallback? onVoid;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final r = run;
    final net = r.netTotalMinor;
    final semantic = StringBuffer('Tazminat: ${r.period?.label ?? ''}. ${r.isVoided ? 'İptal edildi' : 'Geçerli'}.');
    if (r.empty) {
      semantic.write(' Tazminat yok, işaret kaydı. Borç yazılmadı.');
    } else {
      semantic.write(' ${r.apartmentCount} daire. Toplam: ${moneySemanticLabel(r.totalMinor)}.');
      if (net != null && net != r.totalMinor) semantic.write(' Net: ${moneySemanticLabel(net)}.');
    }
    return AppCard(
      key: ValueKey<String>('latefee_run_${r.id}'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: semantic.toString(),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      DialogMetaPill(
                        r.isVoided ? 'İptal edildi' : 'Geçerli',
                        tone: r.isVoided ? AppTone.neutral : AppTone.success,
                        icon: r.isVoided ? Icons.block_rounded : Icons.check_circle_rounded,
                      ),
                      if (r.waivedCount > 0) DialogMetaPill('${r.waivedCount} muaf', icon: Icons.do_not_disturb_on_rounded),
                      if (r.empty) const DialogMetaPill('Tazminat yok (işaret)', tone: AppTone.info, icon: Icons.event_available_rounded),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(r.period?.label ?? 'Dönem bilinmiyor', style: th.titleMedium),
                  if (r.empty)
                    Text('Bu ay için tazminat doğmadı; borç yazılmadı.', style: th.bodyMedium)
                  else ...[
                    Text(
                      formatMinor(r.totalMinor),
                      style: th.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        decoration: r.isVoided ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (net != null && net != r.totalMinor)
                      Text('Net (iptal edilen kalemler düşülmüş): ${formatMinor(net)}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                    Text('${r.apartmentCount} daire', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  ],
                  Text(
                    '${formatRateBp(r.params.rateBp)} aylık • ${r.params.method.label} • ek ${r.params.graceDays} gün',
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                  if (r.postedAt != null)
                    Text(
                      'Yazıldı: ${formatIstanbulDateTime(r.postedAt)}${r.postedByName == null ? '' : ' • ${r.postedByName}'}',
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  if (r.isVoided && r.voidedAt != null)
                    Text(
                      'İptal: ${formatIstanbulDateTime(r.voidedAt)}${r.voidedByName == null ? '' : ' • ${r.voidedByName}'}',
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              if (!r.empty)
                TextButton.icon(
                  key: ValueKey<String>('latefee_run_lines_${r.id}'),
                  onPressed: busy ? null : onLines,
                  icon: const Icon(Icons.list_alt_rounded, size: 18),
                  label: const Text('Satırlar'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              if (onVoid != null)
                TextButton.icon(
                  key: ValueKey<String>('latefee_run_void_${r.id}'),
                  onPressed: busy ? null : onVoid,
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('Son çalıştırmayı iptal et'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: AppTone.danger.ink(p)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
