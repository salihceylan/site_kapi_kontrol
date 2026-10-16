import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/views/legal_document_view.dart';
import 'package:site_kapi_kontrol/ui/views/legal_markdown.dart';

/// "Güncellenen koşullar" tam ekran onay sayfası: giriş sonrası `GET /me/consents` -> `pending` doluysa
/// gösterilir. Kullanıcı belgeleri okuyup onaylar ya da oturumu kapatır.
///
/// - Onay kutusu işaretlenmeden "Kabul Et ve Devam Et" kapalıdır ve NEDEN yazılıdır.
/// - Gönderim sürerken çift dokunma ikinci istek göndermez; 429'da düğme geçici kilitlenir.
/// - Sunucu listeyle çelişen bir yanıt verirse (409 `CONSENT_VERSION_STALE`, 409 `DOCUMENT_INCOMPLETE`,
///   400 `DOCUMENT_NOT_ACCEPTABLE`, 400 `INVALID_ACCEPTED_DOCUMENTS`) onay işareti kalkar ve [onStale] çağrılır
///   (güncel liste yeniden okunur; bayat listeyle takılıp kalınmaz).
/// - Ağ/sunucu hatasında sayfa açık kalır, hata gösterilir ve yeniden denenebilir.
class LegalConsentPage extends StatefulWidget {
  const LegalConsentPage({
    super.key,
    required this.pending,
    required this.api,
    required this.tokenProvider,
    required this.onAccepted,
    required this.onDecline,
    this.onStale,
    this.onSessionProblem,
    this.onOpenLink,
  });

  final List<PendingConsent> pending;
  final LegalApi api;

  /// Anlık oturum belirteci (yoksa null).
  final String? Function() tokenProvider;

  /// Onay kaydedildi. [remaining]: sunucu yanıtında hâlâ onay bekleyen belgeler (yanıtta alan yoksa null,
  /// bekleyen kalmadıysa boş liste).
  final void Function(List<PendingConsent>? remaining) onAccepted;

  /// "Oturumu kapat" onaylandı.
  final VoidCallback onDecline;

  /// Liste bayat görünüyorsa ([refreshCodes]): çağıran güncel bekleyen listesini yeniden okur.
  final Future<void> Function()? onStale;

  /// Gönderimde bu hata kodlarından biri gelirse bekleyen listesi yeniden okunur.
  static const Set<String> refreshCodes = <String>{
    'CONSENT_VERSION_STALE',
    'DOCUMENT_INCOMPLETE',
    'DOCUMENT_NOT_ACCEPTABLE',
    'INVALID_ACCEPTED_DOCUMENTS',
  };

  /// 401: oturum geçersiz olabilir (çağıran oturumu doğrular).
  final VoidCallback? onSessionProblem;

  final LegalLinkOpener? onOpenLink;

  @override
  State<LegalConsentPage> createState() => _LegalConsentPageState();
}

class _LegalConsentPageState extends State<LegalConsentPage> {
  final RetryLock _retry = RetryLock();
  final FocusNode _titleFocus = FocusNode(debugLabel: 'legal_consent_title');

  bool _accepted = false;
  bool _submitting = false;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _titleFocus.requestFocus();
      announcePolite(
        context,
        'Güncellenen koşullar. Devam etmek için belgeleri onaylamanız gerekiyor.',
      );
    });
  }

  @override
  void didUpdateWidget(LegalConsentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Belge kümesi/sürümü değiştiyse eski onay geçersizdir.
    if (_signature(oldWidget.pending) != _signature(widget.pending)) _accepted = false;
  }

  static String _signature(List<PendingConsent> pending) =>
      pending.map((d) => '${d.id}@${d.version}').join('|');

  @override
  void dispose() {
    _retry.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _openDocument(PendingConsent document) async {
    if (_opening || _submitting) return;
    _opening = true;
    try {
      await LegalDocumentView.open(
        context,
        documentId: document.id,
        title: document.title,
        api: widget.api,
        onOpenLink: widget.onOpenLink,
      );
    } finally {
      _opening = false;
    }
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked || !_accepted) return;
    final token = widget.tokenProvider();
    if (token == null) {
      setState(() => _error = 'Oturum bulunamadı. Çıkış yapıp yeniden giriş yapın.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.api.acceptDocuments(
        token: token,
        documents: <AcceptedDocument>[for (final d in widget.pending) d.toAccepted()],
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _submitting = false;
        _accepted = false;
      });
      widget.onAccepted(result.pending);
    } on ApiException catch (e) {
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      final stale = LegalConsentPage.refreshCodes.contains(e.code);
      final message = e.message.trim();
      setState(() {
        _submitting = false;
        // Boş sunucu iletisi boş hata kutusu üretmez.
        _error = limited
            ? RetryLock.messageFor(e)
            : (message.isNotEmpty ? message : LegalMessages.consentSubmitFailed);
        if (stale) _accepted = false;
      });
      if (e.isUnauthorized) widget.onSessionProblem?.call();
      if (stale) unawaited(widget.onStale?.call());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = LegalMessages.consentSubmitFailed;
      });
    }
  }

  Future<void> _confirmDecline() async {
    if (_submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Oturum kapatılsın mı?',
        icon: Icons.logout_rounded,
        tone: AppTone.warning,
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Oturumu Kapat'),
          ),
        ],
        child: Text(
          'Güncel koşulları kabul etmezseniz uygulamayı kullanamazsınız. '
          'Oturum kapatılır; daha sonra giriş yaptığınızda koşullar yeniden sunulur.',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
      ),
    );
    if (confirmed == true && mounted) widget.onDecline();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final hPad = MediaQuery.sizeOf(context).width < 400 ? AppSpace.lg : AppSpace.xl;
    final canSubmit = _accepted && !_submitting && !_retry.locked;
    final reason = _accepted
        ? null
        : 'Devam etmek için belgeleri okuyup onay kutusunu işaretleyin.';
    // Pasif düğmenin NEDENİ düğmenin kendisine bağlanır (ekran okuyucu düğmeye odaklanınca ipucunu da okur).
    final buttonHint = reason ?? (_retry.locked ? _error : null);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: AppSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AppCard(
                level: 2,
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: AppSpace.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Center(
                      child: IconOrb(icon: Icons.policy_rounded, size: 64, glow: true),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    Focus(
                      focusNode: _titleFocus,
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Güncellenen Koşullar',
                          textAlign: TextAlign.center,
                          style: th.headlineMedium,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      'Hizmet koşullarımız güncellendi. Uygulamayı kullanmaya devam etmek için '
                      'aşağıdaki belgeleri okuyup onaylamanız gerekir.',
                      textAlign: TextAlign.center,
                      style: th.bodyMedium,
                    ),
                    const SizedBox(height: AppSpace.lg),
                    for (final document in widget.pending) ...<Widget>[
                      _DocumentRow(
                        document: document,
                        enabled: !_submitting,
                        onOpen: () => unawaited(_openDocument(document)),
                      ),
                      const SizedBox(height: AppSpace.sm),
                    ],
                    const SizedBox(height: AppSpace.sm),
                    MergeSemantics(
                      child: InkWell(
                        onTap: _submitting ? null : () => setState(() => _accepted = !_accepted),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Row(
                            children: <Widget>[
                              Checkbox(
                                value: _accepted,
                                onChanged: _submitting
                                    ? null
                                    : (value) => setState(() => _accepted = value ?? false),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                                  child: Text(
                                    widget.pending.length > 1
                                        ? 'Yukarıdaki belgeleri okudum ve kabul ediyorum.'
                                        : 'Yukarıdaki belgeyi okudum ve kabul ediyorum.',
                                    style: th.bodyMedium?.copyWith(color: p.text),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: AppSpace.md),
                      InlineNotice(message: _error!),
                    ],
                    if (reason != null) ...<Widget>[
                      const SizedBox(height: AppSpace.md),
                      Text(reason, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                    ],
                    const SizedBox(height: AppSpace.md),
                    Semantics(
                      hint: canSubmit || _submitting ? null : buttonHint,
                      child: PrimaryActionButton(
                        label: 'Kabul Et ve Devam Et',
                        icon: Icons.check_rounded,
                        loading: _submitting,
                        onPressed: canSubmit ? _submit : null,
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    TextButton(
                      onPressed: _submitting ? null : _confirmDecline,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: AppTone.danger.ink(p),
                      ),
                      child: const Text(
                        'Kabul etmiyorum, oturumu kapat',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.document, required this.enabled, required this.onOpen});

  final PendingConsent document;
  final bool enabled;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(document.title, style: th.titleMedium),
            const SizedBox(height: AppSpace.xs),
            Text('Sürüm: ${document.version}', style: th.bodySmall),
            TextButton.icon(
              onPressed: enabled ? onOpen : null,
              icon: const Icon(Icons.description_outlined, size: 18),
              label: Text('${document.title} metnini oku'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
                alignment: AlignmentDirectional.centerStart,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
