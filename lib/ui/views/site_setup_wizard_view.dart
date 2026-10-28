import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_setup_progress.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/site_setup_progress_store.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/views/site_setup_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_setup_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_setup_steps.dart';

/// Kurulum sihirbazı kapanırken çağırana dönen sonuç.
class SiteSetupOutcome {
  const SiteSetupOutcome({this.changed = false, this.finished = false});

  /// Bir alt akışta kayıtlar değişti: çağıran site listelerini / modül erişimini tazeler.
  final bool changed;

  /// Kullanıcı "Kurulumu bitir" dedi.
  final bool finished;
}

/// Site kurulum sihirbazı (P2-15): site bilgileri -> bloklar -> daireler -> kişiler -> modüller -> finans açılışı.
///
/// MEVCUT ekranları yeniden yazmaz; adım kabuğudur. Her adım var olan formu / ekranı açar (site düzenleme, «Toplu
/// Yükle», Kişiler, Modüller, aidat tanımı, devir bakiyesi, Finans) ve dönünce durumu sunucudan yeniden okur.
/// İlerleme cihazda saklanır ([SiteSetupProgressStore]): sihirbaz kapatılsa da yeniden açılınca kalınan adımdan
/// sürer ("yarım kalan kurulum devam eder"); tamamlanan adımlar sunucu verisinden de gözlenir.
///
/// "Devam" yalnız tamamlanmış adımda, "Atla" tamamlanmamış adımda vardır; atlananlar özette görünür ve sonradan
/// tamamlanır. Geri tuşu sihirbazı kapatır (ilerleme zaten kayıtlıdır). Yalnız site yöneticisi ve süper kullanıcı kullanır.
class SiteSetupWizardView extends StatefulWidget {
  const SiteSetupWizardView({
    super.key,
    required this.authService,
    required this.siteCode,
    this.siteName = '',
    this.controller,
    this.store,
  });

  final AuthService authService;
  final int siteCode;
  final String siteName;

  /// Test / özel kurulum için hazır denetleyici (verilirse sayfa onu yönetmez; kapanırken atmaz).
  final SiteSetupController? controller;

  /// İlerleme deposu (verilmezse uygulama geneli ortak depo).
  final SiteSetupProgressStore? store;

  /// Sihirbazı tam sayfa açar; kapanınca [SiteSetupOutcome] döner (geri tuşunda da).
  static Future<SiteSetupOutcome?> open(
    BuildContext context, {
    required AuthService authService,
    required int siteCode,
    String siteName = '',
    SiteSetupProgressStore? store,
  }) {
    return Navigator.of(context).push<SiteSetupOutcome>(
      MaterialPageRoute<SiteSetupOutcome>(
        builder: (_) => SiteSetupWizardView(
          authService: authService,
          siteCode: siteCode,
          siteName: siteName,
          store: store,
        ),
      ),
    );
  }

  @override
  State<SiteSetupWizardView> createState() => SiteSetupWizardViewState();
}

class SiteSetupWizardViewState extends State<SiteSetupWizardView> {
  /// Kısa pencerede ya da büyük yazıda sabit alt çubuk içeriğe yer bırakmaz: gezinme düğmeleri kaydırılan gövdenin
  /// SONUNA alınır.
  static const double _pinnedNavMinHeight = 560;

  late final SiteSetupController _c = widget.controller ?? _buildController();
  final FocusNode _headingFocus = FocusNode(debugLabel: 'site_setup_heading');
  final ScrollController _scroll = ScrollController();
  SiteSetupStep? _lastStep;
  bool? _lastSummary;
  bool _closing = false;

  SiteSetupController _buildController() {
    return SiteSetupController(
      authService: widget.authService,
      siteCode: widget.siteCode,
      userId: widget.authService.session?.id ?? 0,
      siteName: widget.siteName,
      store: widget.store,
    );
  }

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChanged);
    if (_c.isAllowed) unawaited(_c.start());
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (widget.controller == null) _c.dispose();
    _headingFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final moved = _c.started && (_c.current != _lastStep || _c.showingSummary != _lastSummary);
    if (moved) {
      final firstShow = _lastStep == null;
      _lastStep = _c.current;
      _lastSummary = _c.showingSummary;
      if (!firstShow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_scroll.hasClients) _scroll.jumpTo(0);
          _headingFocus.requestFocus();
          announcePolite(
            context,
            _c.showingSummary
                ? SiteSetupStepHeader.summaryTitle
                : SiteSetupStepHeader.titleOf(_c.current, _c.snapshot.terms),
          );
        });
      }
    }
    setState(() {});
  }

  /// Sihirbazı kapatır; ilerleme zaten kayıtlıdır.
  void _close({bool finished = false}) {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop(SiteSetupOutcome(changed: _c.dataChanged, finished: finished || _c.progress.finished));
  }

  Future<void> _finish() async {
    if (_closing) return;
    await _c.finish();
    if (!mounted) return;
    _close(finished: true);
  }

  List<SiteSetupStatus> get _statuses => <SiteSetupStatus>[for (final step in SiteSetupStep.values) _c.statusOf(step)];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final hPad = size.width < 360 ? AppSpace.md : AppSpace.lg;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final ready = _c.isAllowed && _c.started;
    final pinned = ready && !_c.showingSummary && size.height >= _pinnedNavMinHeight && !largeText;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Site Kurulum Sihirbazı'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            key: const ValueKey<String>('site_setup_close'),
            tooltip: 'Kapat',
            icon: const Icon(Icons.close_rounded),
            onPressed: _close,
          ),
          actions: [
            IconButton(
              key: const ValueKey<String>('site_setup_refresh'),
              tooltip: 'Yenile',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: (!ready || _c.loading) ? null : () => unawaited(_c.refresh()),
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              if (ready) await _c.refresh();
            },
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(hPad, AppSpace.sm, hPad, AppSpace.xl),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: _buildBody(context, inlineNav: ready && !_c.showingSummary && !pinned),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: pinned
            ? SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hPad, AppSpace.sm, hPad, AppSpace.md),
                  child: Align(
                    alignment: Alignment.centerRight,
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: _NavButtons(controller: _c),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildBody(BuildContext context, {required bool inlineNav}) {
    final c = _c;
    if (!c.isAllowed) {
      return const InlineNotice(
        key: ValueKey<String>('site_setup_forbidden'),
        tone: AppTone.info,
        message: 'Kurulum sihirbazı yalnızca site yöneticisi içindir.',
      );
    }
    if (!c.started) {
      return const Padding(padding: EdgeInsets.only(top: AppSpace.md), child: ListSkeleton(rows: 3));
    }
    final terms = c.snapshot.terms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SiteLine(name: c.displayName),
        const SizedBox(height: AppSpace.md),
        SiteSetupStepHeader(
          step: c.current,
          terms: terms,
          statuses: _statuses,
          focusNode: _headingFocus,
          summary: c.showingSummary,
        ),
        const SizedBox(height: AppSpace.lg),
        if (c.showingSummary)
          _Summary(controller: c, onFinish: () => unawaited(_finish()))
        else ...[
          SiteSetupStepBody(controller: c),
          if (inlineNav) ...[const SizedBox(height: AppSpace.lg), _NavButtons(controller: c)],
        ],
      ],
    );
  }
}

/// Sitenin adı (hangi site kuruluyor).
class _SiteLine extends StatelessWidget {
  const _SiteLine({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Row(
      children: [
        Icon(Icons.location_city_rounded, size: 18, color: p.textSecondary),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            name,
            key: const ValueKey<String>('site_setup_site_name'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: th.bodyMedium?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Geri / Atla / Devam düğmeleri. Düğmeler sığmazsa alt satıra sarar (sabit genişlik yok).
class _NavButtons extends StatelessWidget {
  const _NavButtons({required this.controller});

  final SiteSetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        if (!c.isFirst)
          PrimaryActionButton(
            key: const ValueKey<String>('site_setup_back'),
            label: 'Geri',
            icon: Icons.arrow_back_rounded,
            variant: AppButtonVariant.outline,
            expand: false,
            onPressed: c.back,
          ),
        if (c.canSkip)
          Semantics(
            hint: 'Bu adımı şimdi yapmadan sıradakine geçer; özetten sonra tamamlayabilirsiniz.',
            child: PrimaryActionButton(
              key: const ValueKey<String>('site_setup_skip'),
              label: 'Atla',
              icon: Icons.skip_next_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: c.skip,
            ),
          ),
        PrimaryActionButton(
          key: const ValueKey<String>('site_setup_next'),
          label: c.isLast ? 'Özeti gör' : 'Devam',
          icon: c.isLast ? Icons.fact_check_rounded : Icons.arrow_forward_rounded,
          expand: false,
          onPressed: c.canContinue ? c.next : null,
        ),
      ],
    );
  }
}

/// Kurulum özeti: altı adımın durumu, tamamlanmayanlara dönüş ve "Kurulumu bitir".
class _Summary extends StatelessWidget {
  const _Summary({required this.controller, required this.onFinish});

  final SiteSetupController controller;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final terms = c.snapshot.terms;
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final allDone = SiteSetupStep.values.every((s) => c.statusOf(s) == SiteSetupStatus.done);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Adımların durumu aşağıda. Tamamlanmayan bir adıma dokunup devam edebilirsiniz.',
          style: th.bodyMedium?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.md),
        for (final step in SiteSetupStep.values) ...[
          _SummaryRow(
            step: step,
            title: siteSetupStepTitle(step, terms),
            status: c.statusOf(step),
            onOpen: () => c.goTo(step),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        const SizedBox(height: AppSpace.sm),
        InlineNotice(
          key: ValueKey<String>(allDone ? 'site_setup_summary_all_done' : 'site_setup_summary_pending'),
          tone: allDone ? AppTone.success : AppTone.info,
          message: allDone
              ? 'Tüm adımlar tamam. Kurulumu bitirebilirsiniz.'
              : 'Atlanan ya da tamamlanmayan adımları istediğiniz zaman Site Yönetimi bölümündeki “Kurulum Sihirbazı” '
                    'düğmesiyle tamamlayabilirsiniz.',
        ),
        const SizedBox(height: AppSpace.lg),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            PrimaryActionButton(
              key: const ValueKey<String>('site_setup_back'),
              label: 'Geri',
              icon: Icons.arrow_back_rounded,
              variant: AppButtonVariant.outline,
              expand: false,
              onPressed: c.back,
            ),
            PrimaryActionButton(
              key: const ValueKey<String>('site_setup_finish'),
              label: c.progress.finished ? 'Kapat' : 'Kurulumu bitir',
              icon: Icons.check_circle_rounded,
              expand: false,
              onPressed: onFinish,
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.step, required this.title, required this.status, required this.onOpen});

  final SiteSetupStep step;
  final String title;
  final SiteSetupStatus status;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final done = status == SiteSetupStatus.done;
    return AppCard(
      key: ValueKey<String>('site_setup_summary_${step.name}'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: siteSetupStepIcon(step), tone: siteSetupStatusTone(status), size: 40, gap: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${step.index + 1}. $title', style: th.titleSmall),
                    const SizedBox(height: AppSpace.xs),
                    SiteSetupStatusChip(status: status),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: ValueKey<String>('site_setup_summary_open_${step.name}'),
              onPressed: onOpen,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(done ? '$title adımını gözden geçir' : '$title adımını tamamla'),
            ),
          ),
        ],
      ),
    );
  }
}
