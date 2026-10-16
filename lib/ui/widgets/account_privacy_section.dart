import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/account_data_export.dart';
import 'package:site_kapi_kontrol/services/account_api.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/views/account_deletion_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/account_password_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Profilde "Gizlilik ve Veri" bölümü: "Verilerimi İndir" ve "Hesabımı Sil".
///
/// Verilerimi İndir: parola penceresi -> `POST /me/data-export` -> JSON paylaşım menüsüne verilir. Dosya
/// kişisel veri içerir: kullanıcı kapatınca ya da bölüm ekrandan kalkınca bellekten atılır, geçici dosya
/// silinir. Paylaşım menüsü kapatılırsa veri bellekte KALIR ve "Paylaş / Kaydet" ile yeniden açılır
/// (sunucu 24 saatte 3 dışa aktarmaya izin verir; kullanıcı hakkını boşa harcamasın).
///
/// Hesabımı Sil: ayrı bir sayfada ([AccountDeletionView]) önizleme -> engeller -> parola + "SİL" onayı.
class AccountPrivacySection extends StatefulWidget {
  const AccountPrivacySection({
    super.key,
    required this.authService,
    this.service,
    this.sharer,
    this.sweepLeftovers = _defaultSweep,
  });

  final AuthService authService;

  /// Testler için: verilmezse [authService] üzerinden kurulur.
  final AccountService? service;
  final AccountExportSharer? sharer;

  /// Bölüm açılınca çalışır: önceki oturumlardan diskte kalmış kişisel veri geçici dosyalarını siler (Android
  /// süreci 2 dakika dolmadan öldürürse silme zamanlayıcısı çalışmamıştır). Hata fırlatmaz.
  final Future<void> Function() sweepLeftovers;

  static Future<void> _defaultSweep() => AccountExportSharer.sweepAll(staleAfter: Duration.zero);

  @override
  State<AccountPrivacySection> createState() => AccountPrivacySectionState();
}

class AccountPrivacySectionState extends State<AccountPrivacySection> {
  AccountService? _ownService;
  AccountExportSharer? _ownSharer;
  AccountDataExport? _export;
  bool _exporting = false;
  bool _sharing = false;
  bool _openingDeletion = false;
  String? _shareError;
  final GlobalKey _shareButtonKey = GlobalKey();

  // Odak: pencere / sayfa kapanınca odak onu açan düğmeye geri döner (klavye ve ekran okuyucu kullanıcısı yerini
  // kaybetmesin).
  final FocusNode _exportFocus = FocusNode(debugLabel: 'account_export_button');
  final FocusNode _deleteFocus = FocusNode(debugLabel: 'account_delete_button');
  final FocusNode _shareFocus = FocusNode(debugLabel: 'account_export_share');

  @override
  void initState() {
    super.initState();
    unawaited(widget.sweepLeftovers());
  }

  AccountService get _service =>
      widget.service ?? (_ownService ??= AccountService(authService: widget.authService));
  AccountExportSharer get _sharer =>
      widget.sharer ?? (_ownSharer ??= AccountExportSharer());

  /// Testler için: bellekteki dışa aktarma dosyası var mı.
  AccountDataExport? get pendingExport => _export;

  @override
  void didUpdateWidget(AccountPrivacySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.authService, widget.authService)) {
      // Hesap değişti: önceki hesabın verisi bellekte kalmasın.
      _ownService = null;
      _export = null;
      _shareError = null;
    }
  }

  @override
  void dispose() {
    _export = null;
    _exportFocus.dispose();
    _deleteFocus.dispose();
    _shareFocus.dispose();
    super.dispose();
  }

  void _focusAfterFrame(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.canRequestFocus) node.requestFocus();
    });
  }

  Future<void> _startExport() async {
    if (_exporting || _sharing) return;
    setState(() {
      _exporting = true;
      _shareError = null;
    });
    AccountDataExport? export;
    try {
      export = await AccountPasswordDialog.show<AccountDataExport>(
        context,
        title: 'Verilerimi İndir',
        icon: Icons.download_rounded,
        message:
            'Hesabınıza ait kişisel verilerin bir kopyasını JSON dosyası olarak hazırlarız. '
            'Devam etmek için şifrenizi girin. Bu işlem 24 saat içinde en fazla 3 kez yapılabilir.',
        confirmLabel: 'Verilerimi Hazırla',
        busyLabel: 'Hazırlanıyor...',
        onSubmit: _service.exportData,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
    if (!mounted) return;
    if (export == null) {
      _focusAfterFrame(_exportFocus);
      return;
    }
    setState(() => _export = export);
    _focusAfterFrame(_shareFocus);
    announcePolite(context, 'Veri dosyanız hazır. Paylaşım menüsü açılıyor.');
    await _share();
  }

  Rect? _shareOrigin() {
    final box = _shareButtonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _share() async {
    final export = _export;
    if (export == null || _sharing) return;
    setState(() {
      _sharing = true;
      _shareError = null;
    });
    try {
      await _sharer.share(export, sharePositionOrigin: _shareOrigin());
      if (!mounted) return;
      setState(() => _sharing = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sharing = false;
        _shareError =
            'Paylaşım menüsü açılamadı. Dosya hazır; "Paylaş / Kaydet" ile yeniden deneyebilirsiniz.';
      });
    }
  }

  void _discardExport() {
    setState(() {
      _export = null;
      _shareError = null;
    });
    _focusAfterFrame(_exportFocus);
  }

  Future<void> _openDeletion() async {
    if (_openingDeletion) return;
    setState(() => _openingDeletion = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AccountDeletionView(service: _service),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingDeletion = false);
        _focusAfterFrame(_deleteFocus);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final export = _export;
    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Gizlilik ve Veri', icon: Icons.privacy_tip_outlined),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Kişisel verilerinizin bir kopyasını alabilir veya hesabınızı kalıcı olarak silebilirsiniz.',
            style: th.bodySmall,
          ),
          const SizedBox(height: AppSpace.lg),
          _ActionBlock(
            icon: Icons.download_rounded,
            title: 'Verilerimi İndir',
            description:
                'Hesabınıza ait kişisel verilerin bir kopyasını JSON dosyası olarak alın. '
                'Şifreniz istenir; 24 saatte en fazla 3 kez yapılabilir.',
            button: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('account_export_button'),
                focusNode: _exportFocus,
                style: tonalActionStyle(context),
                onPressed: (_exporting || _sharing) ? null : _startExport,
                icon: _exporting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: p.textSecondary),
                      )
                    : const Icon(Icons.download_rounded),
                label: const Text('Verilerimi İndir', textAlign: TextAlign.center),
              ),
            ),
          ),
          if (_shareError != null) ...[
            const SizedBox(height: AppSpace.md),
            InlineNotice(message: _shareError!),
          ],
          if (export != null) ...[
            const SizedBox(height: AppSpace.md),
            _ExportReadyCard(
              export: export,
              sharing: _sharing,
              shareButtonKey: _shareButtonKey,
              shareFocus: _shareFocus,
              onShare: _share,
              onDiscard: _discardExport,
            ),
          ],
          const Divider(height: AppSpace.xl),
          _ActionBlock(
            icon: Icons.delete_forever_rounded,
            tone: AppTone.danger,
            title: 'Hesabımı Sil',
            description:
                'Hesabınızı kalıcı olarak silin. Önce neyin silineceğini ve neyin saklanacağını '
                'görür, sonra şifrenizle onaylarsınız. Bu işlem geri alınamaz.',
            button: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('account_delete_button'),
                focusNode: _deleteFocus,
                style: dangerOutlineStyle(context),
                onPressed: _openingDeletion ? null : _openDeletion,
                icon: const Icon(Icons.delete_forever_rounded),
                label: const Text('Hesabımı Sil', textAlign: TextAlign.center),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Başlık + açıklama + tam genişlik düğme. Başlık ve açıklama kırpılmaz (sarar).
class _ActionBlock extends StatelessWidget {
  const _ActionBlock({
    required this.icon,
    required this.title,
    required this.description,
    required this.button,
    this.tone = AppTone.primary,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget button;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon, size: 20, color: tone.ink(p))),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: th.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(description, style: th.bodySmall?.copyWith(color: p.textSecondary)),
        const SizedBox(height: AppSpace.md),
        button,
      ],
    );
  }
}

/// Hazır dosya kartı: ad + boyut, "Paylaş / Kaydet" ve "Kapat".
class _ExportReadyCard extends StatelessWidget {
  const _ExportReadyCard({
    required this.export,
    required this.sharing,
    required this.shareButtonKey,
    required this.shareFocus,
    required this.onShare,
    required this.onDiscard,
  });

  final AccountDataExport export;
  final bool sharing;
  final GlobalKey shareButtonKey;
  final FocusNode shareFocus;
  final VoidCallback onShare;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineNotice(
          key: const ValueKey<String>('account_export_ready'),
          tone: AppTone.success,
          message:
              'Veri dosyanız hazır: ${export.fileName} (${export.sizeLabel}). Dosya kişisel verilerinizi '
              'içerir; güvenli bir yerde saklayın ve başkalarıyla paylaşmayın.',
        ),
        const SizedBox(height: AppSpace.md),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: shareButtonKey,
            focusNode: shareFocus,
            onPressed: sharing ? null : onShare,
            icon: sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.ios_share_rounded),
            label: Text(sharing ? 'Açılıyor...' : 'Paylaş / Kaydet', textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey<String>('account_export_discard'),
            onPressed: sharing ? null : onDiscard,
            icon: const Icon(Icons.close_rounded),
            label: const Text('Kapat (dosyayı bellekten at)'),
          ),
        ),
      ],
    );
  }
}
