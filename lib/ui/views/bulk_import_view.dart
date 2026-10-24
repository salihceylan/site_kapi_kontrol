import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_file_step.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_kind_step.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_mapping_step.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_preview_step.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_result_step.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_step_header.dart';

/// "Toplu Yükle" sihirbazı (Platform Faz 2b; docs/PLATFORM_TOPLU_ISLEMLER.md "Ekranlar"): tam sayfa, adım
/// göstergeli. Dosya cihazda ayrıştırılır (sunucuya yalnız JSON satırlar gider), önizleme HİÇBİR ŞEY yazmaz,
/// onay `preview_hash` + `idempotency_key` ile gider.
///
/// Sayfa kapanırken [BulkImportOutcome] döner (kayıtlar değiştiyse çağıran listeleri tazeler, «Kişilere git»
/// için sekme dizini taşır). Geri tuşu adım adım geri gider; onay sürerken çıkış engellenir.
class BulkImportView extends StatefulWidget {
  const BulkImportView({
    super.key,
    required this.scope,
    this.initialKind,
    this.controller,
    this.allowedKinds = kClassicImportKinds,
  });

  final PeopleScope scope;

  /// Açılışta önseçili tür (boş sekmedeki «Excel'den yükle» kısayolu).
  final ImportKind? initialKind;

  /// Test / özel kurulum için hazır denetleyici (verilirse sayfa onu yönetmez ama dinler; kapanırken atılır).
  final BulkImportController? controller;

  /// Bu girişte seçilebilen türler (Kişiler: klasik + hepsi bir arada; Finans > Daireler: devir bakiyesi).
  final List<ImportKind> allowedKinds;

  static Future<BulkImportOutcome?> open(
    BuildContext context, {
    required PeopleScope scope,
    ImportKind? initialKind,
    List<ImportKind> allowedKinds = kClassicImportKinds,
  }) {
    return Navigator.of(context).push<BulkImportOutcome>(
      MaterialPageRoute<BulkImportOutcome>(
        builder: (_) => BulkImportView(scope: scope, initialKind: initialKind, allowedKinds: allowedKinds),
      ),
    );
  }

  @override
  State<BulkImportView> createState() => BulkImportViewState();
}

class BulkImportViewState extends State<BulkImportView> {
  /// Test düzeneği: sihirbazı kendisi kuran ekranlar (Kişiler) için sahte servis / seçici / teslim ile kurulmuş
  /// denetleyici.
  @visibleForTesting
  static BulkImportController Function(PeopleScope scope)? debugControllerFactory;

  late final BulkImportController _c = widget.controller ?? _buildController();
  final FocusNode _headingFocus = FocusNode(debugLabel: 'bulk_step_heading');
  final ScrollController _scroll = ScrollController();
  BulkStep _lastStep = BulkStep.kind;
  bool _closing = false;

  /// «Aktar» çift dokunuşunda ikinci onay penceresi açılmasın (bir sonraki kare modal bariyer çizilmeden ikinci
  /// tıklama gelebilir).
  bool _confirming = false;

  BulkImportController _buildController() {
    final scope = widget.scope;
    final factory = debugControllerFactory;
    if (factory != null) return factory(scope);
    return BulkImportController(
      service: BulkService(authService: scope.authService),
      siteCode: scope.siteCode,
      siteName: scope.siteName,
      allowedKinds: widget.allowedKinds,
      siteSummaryLoader: () async {
        final (structure, _) = await scope.authService.getSiteStructure(siteCode: scope.siteCode);
        if (structure == null) return null;
        return '${structure.blocks.length} blok, ${structure.apartments.length} daire';
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChanged);
    if (widget.scope.canWrite) {
      unawaited(
        _c.loadSpec().then((_) {
          if (!mounted) return;
          final wanted = widget.initialKind ?? ImportKind.allInOne;
          final ImportKind initial = wanted == ImportKind.allInOne && _c.spec?.of(ImportKind.allInOne) == null
              ? (_c.allowedKinds.contains(ImportKind.people) ? ImportKind.people : _c.allowedKinds.first)
              : wanted;
          // Sunucu «Hepsi bir arada» türünü bilmiyorsa (eski sürüm) klasik Kişiler türüne düşülür.
          final chosen = initial;
          if (_c.spec?.of(chosen) != null && _c.kind == null) _c.selectKind(chosen);
        }),
      );
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _c.dispose();
    _headingFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    if (_c.step != _lastStep) {
      _lastStep = _c.step;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scroll.hasClients) _scroll.jumpTo(0);
        _headingFocus.requestFocus();
        announcePolite(context, BulkStepHeader.titleOf(_c.step));
      });
    }
    setState(() {});
  }

  void _finish({int? goToTab}) {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop(BulkImportOutcome(changed: _c.dataChanged, goToTab: goToTab));
  }

  Future<void> _onBack() async {
    if (_closing) return;
    if (_c.committing) {
      announcePolite(context, 'Yükleme sürüyor, lütfen bekleyin.');
      AppSnack.show(context, 'Yükleme sürüyor, lütfen bekleyin.', kind: AppSnackKind.warning);
      return;
    }
    if (_c.parsing || _c.picking) {
      _c.cancelParse();
      return;
    }
    if (_c.step == BulkStep.result) {
      _finish();
      return;
    }
    if (_c.step == BulkStep.kind) {
      if (_c.hasProgress) {
        final leave = await confirmCrmAction(
          context,
          title: 'Yüklemeden çıkılsın mı?',
          message: 'Okunan dosya ve hazırlanan önizleme kapatılacak. Hiçbir kayıt değiştirilmedi.',
          confirmLabel: 'Çık',
          cancelLabel: 'Kal',
          icon: Icons.logout_rounded,
        );
        if (!leave || !mounted) return;
      }
      _finish();
      return;
    }
    _c.back();
  }

  Future<void> _confirm() async {
    final preview = _c.preview;
    final kind = _c.kind;
    if (_confirming || preview == null || kind == null || !_c.canCommit) return;
    _confirming = true;
    try {
      final ok = await BulkConfirmDialog.show(
        context,
        kind: kind,
        preview: preview,
        strict: _c.strict,
        allowOverwrite: _c.allowOverwrite,
        cutoverDate: _c.cutoverDate,
      );
      if (!ok || !mounted) return;
      unawaited(_c.commit(acknowledged: true));
    } finally {
      _confirming = false;
    }
  }

  int _tabOf(ImportKind kind) => switch (kind) {
    ImportKind.people => 0,
    ImportKind.apartments => 1,
    ImportKind.vehicles => 2,
    ImportKind.allInOne => 0,
    ImportKind.openingBalances => 0,
  };

  @override
  Widget build(BuildContext context) {
    final hPad = MediaQuery.sizeOf(context).width < 360 ? AppSpace.md : AppSpace.lg;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onBack());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Toplu Yükle'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            key: const ValueKey<String>('bulk_back'),
            tooltip: 'Geri',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => unawaited(_onBack()),
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: AppSpace.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _c.step == BulkStep.mapping ? 1000 : 640),
                child: widget.scope.canWrite ? _buildSteps() : _buildForbidden(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForbidden() {
    return const InlineNotice(
      key: ValueKey<String>('bulk_forbidden'),
      tone: AppTone.info,
      message: 'Toplu yükleme yalnızca site yöneticisi içindir.',
    );
  }

  Widget _buildSteps() {
    final c = _c;
    final Widget step;
    switch (c.step) {
      case BulkStep.kind:
        step = BulkKindStep(controller: c);
      case BulkStep.file:
        step = BulkFileStep(controller: c, onBack: () => unawaited(_onBack()), onToMapping: c.goToMappingStep);
      case BulkStep.mapping:
        step = BulkMappingStep(controller: c, onBack: () => unawaited(_onBack()));
      case BulkStep.preview:
        step = BulkPreviewStep(controller: c, onConfirm: () => unawaited(_confirm()), onBack: () => unawaited(_onBack()));
      case BulkStep.result:
        step = BulkResultStep(
          controller: c,
          onGoToList: () => _finish(goToTab: _tabOf(c.kind ?? ImportKind.people)),
          onNext: (next) => c.startNext(next),
          onFinish: _finish,
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BulkStepHeader(step: c.step, focusNode: _headingFocus),
        const SizedBox(height: AppSpace.lg),
        step,
      ],
    );
  }
}
