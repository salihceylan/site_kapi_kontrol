import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/announcement_parts.dart' show isLongTitle;
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_parts.dart';

/// Süper kullanıcı kararının sonucu: ekrana yansıtılacak kısa Türkçe ileti.
@immutable
class SiteApplicationDecisionResult {
  const SiteApplicationDecisionResult({required this.message, required this.approved});

  final String message;
  final bool approved;
}

/// Süper kullanıcı başvuru ayrıntı penceresi (Platform: site başvurusu): başvuran iletişimi, site bilgisi,
/// bloklar, kapılar, cihaz durumu, not ve (bekleyen başvuruda) "Onayla" / "Reddet".
///
/// - Ayrıntı açılışta çekilir (`device_available` gibi alanlar yalnız ayrıntıdadır): yüklenirken iskelet,
///   hata olursa "Tekrar Dene" (boş pencere ASLA çizilmez). Başvuru artık yoksa (404) eylemler gösterilmez.
/// - Onay: onay penceresi ("N bloklu M daireli site kurulacak, X yönetici olacak"); red: isteğe bağlı gerekçe.
/// - Çift gönderim koruması: eylem sürerken düğmeler kilitli, geri tuşu pencereyi kapatmaz. 429 sonrası
///   eylemler `retry_after` kadar kilitlenir. 409 `APPLICATION_NOT_PENDING` (başka yerden karar verilmiş)
///   mesajı gösterilir, ayrıntı sunucudan yeniden okunur ve liste tazelenir ([onChanged]).
/// - Karar başarılıysa pencere [SiteApplicationDecisionResult] ile kapanır (çağıran ileti gösterir).
class SiteApplicationDetailDialog extends StatefulWidget {
  const SiteApplicationDetailDialog({
    super.key,
    required this.authService,
    required this.applicationId,
    this.initialTitle = '',
    this.onChanged,
  });

  final AuthService authService;
  final int applicationId;

  /// Ayrıntı gelene kadar başlıkta görünen site adı (liste satırından).
  final String initialTitle;

  /// Karar sonrası (ve durum uyuşmazlığında) çağrılır: liste ve rozet tazelenir.
  final VoidCallback? onChanged;

  /// Reddetme gerekçesi sınırı (sunucu ile aynı).
  static const int maxReasonLength = 300;

  static Future<SiteApplicationDecisionResult?> show(
    BuildContext context, {
    required AuthService authService,
    required int applicationId,
    String initialTitle = '',
    VoidCallback? onChanged,
  }) {
    return showDialog<SiteApplicationDecisionResult>(
      context: context,
      builder: (_) => SiteApplicationDetailDialog(
        authService: authService,
        applicationId: applicationId,
        initialTitle: initialTitle,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<SiteApplicationDetailDialog> createState() => _SiteApplicationDetailDialogState();
}

class _SiteApplicationDetailDialogState extends State<SiteApplicationDetailDialog> {
  SiteApplication? _detail;
  bool _loading = false;
  String? _error;
  String? _actionError;
  String? _busyAction;
  bool _gone = false;
  int _token = 0;
  final RetryLock _retry = RetryLock();

  bool get _busy => _busyAction != null;
  bool get _actionsLocked => _busy || _retry.locked;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    _retry.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.authService.getAdminSiteApplication(widget.applicationId);
      if (!mounted || token != _token) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      final gone = e is ApiException && e.code == 'APPLICATION_NOT_FOUND';
      setState(() {
        _loading = false;
        if (gone) {
          _detail = null;
          _gone = true;
          _actionError = null;
        }
        _error = gone
            ? 'Bu başvuru artık yok. Liste yenilendi.'
            : crmMessageOf(
                e,
                'Başvuru yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
              );
      });
      if (gone) widget.onChanged?.call();
    }
  }

  /// Eylem hatası: mesaj gösterilir; durum uyuşmazlığında ayrıntı yeniden okunur ve liste tazelenir.
  void _fail(Object e, String fallback) {
    if (!mounted) return;
    final limited = _retry.lockIfRateLimited(e, () {
      if (mounted) setState(() {});
    });
    setState(() {
      _busyAction = null;
      _actionError = limited ? RetryLock.messageFor(e) : crmMessageOf(e, fallback);
    });
    if (e is ApiException &&
        (e.code == 'APPLICATION_NOT_PENDING' || e.code == 'APPLICATION_NOT_FOUND')) {
      widget.onChanged?.call();
      unawaited(_load());
    }
  }

  String _approveMessage(SiteApplication a) {
    final who = a.applicant?.fullName ?? 'Başvuran';
    final buffer = StringBuffer(
      '"${a.siteNameLabel}" için ${a.blockCount} bloklu ${a.apartmentCount} daireli site kurulacak, '
      '$who site yöneticisi olacak.',
    );
    if (a.hasDevice) {
      if (a.deviceAvailable == false) {
        buffer.write(
          ' Seçilen cihaz artık başvuranın hesabında değil; site cihazsız kurulacak.',
        );
      } else {
        // Sunucu cihazı yalnız hâlâ başvuranın VE başka bir siteye bağlı değilse bağlar.
        buffer.write(' Uygunsa seçilen cihaz 1. kapıya bağlanacak.');
      }
    }
    return buffer.toString();
  }

  Future<void> _approve() async {
    final detail = _detail;
    if (detail == null || !detail.isPending || _actionsLocked) return;
    final confirmed = await confirmCrmAction(
      context,
      title: 'Başvuru onaylansın mı?',
      message: _approveMessage(detail),
      confirmLabel: 'Onayla',
      icon: Icons.check_circle_outline,
      tone: AppTone.success,
    );
    if (!confirmed || !mounted || _actionsLocked) return;
    setState(() {
      _busyAction = 'approve';
      _actionError = null;
    });
    try {
      final decision = await widget.authService.approveSiteApplication(detail.id);
      widget.onChanged?.call();
      if (!mounted) return;
      final who = detail.applicant?.fullName ?? 'Başvuran';
      final buffer = StringBuffer(
        '"${detail.siteNameLabel}" sitesi kuruldu; $who artık site yöneticisi.',
      );
      if (detail.hasDevice && decision.deviceAttached == false) {
        buffer.write(' Cihaz bağlanamadı, sonradan bağlanabilir.');
      }
      popIfCurrent(
        context,
        SiteApplicationDecisionResult(message: buffer.toString(), approved: true),
      );
    } catch (e) {
      _fail(e, 'Başvuru onaylanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
  }

  Future<void> _reject() async {
    final detail = _detail;
    if (detail == null || !detail.isPending || _actionsLocked) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectDialog(siteName: detail.siteNameLabel),
    );
    if (reason == null || !mounted || _actionsLocked) return;
    setState(() {
      _busyAction = 'reject';
      _actionError = null;
    });
    try {
      await widget.authService.rejectSiteApplication(detail.id, reason: reason);
      widget.onChanged?.call();
      if (!mounted) return;
      popIfCurrent(
        context,
        const SiteApplicationDecisionResult(message: 'Başvuru reddedildi.', approved: false),
      );
    } catch (e) {
      _fail(e, 'Başvuru reddedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final title = (detail?.siteName ?? widget.initialTitle).trim();
    final Widget body;
    if (detail == null) {
      body = _loading || _error == null
          ? const DialogRowsSkeleton(rows: 3, caption: 'Başvuru yükleniyor...')
          : InlineNotice(message: _error!, onRetry: _gone ? null : _load);
    } else {
      body = _buildDetail(context, detail);
    }
    return PopScope(
      // Karar sürerken pencere kapanmaz: sonuç listeye yansıtılabilsin.
      canPop: !_busy,
      child: AppDialog(
        title: title.isEmpty ? 'Site Başvurusu' : title,
        subtitle: 'Site başvurusu',
        icon: Icons.domain_add_rounded,
        actions: [
          TextButton(
            onPressed: _busy ? null : () => popIfCurrent(context),
            child: const Text('Kapat'),
          ),
        ],
        child: body,
      ),
    );
  }

  Widget _buildDetail(BuildContext context, SiteApplication a) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    final applicant = a.applicant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          InlineNotice(message: _error!, onRetry: _load),
          const SizedBox(height: AppSpace.md),
        ],
        if (_actionError != null) CrmFormError(message: _actionError!),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            SiteApplicationStatusChip(a),
            if (a.managementTypeLabel != null) InfoChip(a.managementTypeLabel!),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        // Pencere başlığı en çok 3 satır gösterir; uzun site adı büyük yazıda kesilebilir: tam ad gövdede de var.
        if (isLongTitle(a.siteName)) ...[
          DialogPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DialogSectionTitle(icon: Icons.title_rounded, title: 'Site adı'),
                const SizedBox(height: AppSpace.md),
                SelectableText(
                  a.siteNameLabel,
                  key: const ValueKey<String>('site_application_full_name'),
                  style: th.titleSmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        DialogPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(
                icon: Icons.person_rounded,
                title: 'Başvuran',
                tone: AppTone.violet,
              ),
              const SizedBox(height: AppSpace.md),
              CrmInfoLine(label: 'Ad soyad', value: a.applicantLabel),
              if (applicant == null) ...[
                const SizedBox(height: AppSpace.sm),
                Text(
                  'Bu hesap silinmiş; başvuru onaylanamaz, isterseniz reddedebilirsiniz.',
                  key: const ValueKey<String>('site_application_deleted_applicant'),
                  style: secondary,
                ),
              ],
              if (applicant?.email != null) ...[
                const SizedBox(height: AppSpace.sm),
                CrmInfoLine(label: 'E-posta', value: applicant!.email!),
              ],
              if (applicant?.phone != null) ...[
                const SizedBox(height: AppSpace.sm),
                CrmInfoLine(label: 'Telefon', value: applicant!.phone!),
              ],
              if (applicant?.role != null) ...[
                const SizedBox(height: AppSpace.sm),
                CrmInfoLine(label: 'Rol', value: _roleLabel(applicant!.role!)),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        DialogPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(icon: Icons.apartment_rounded, title: 'Site'),
              const SizedBox(height: AppSpace.md),
              CrmInfoLine(label: 'Yapı', value: a.structureLabel),
              if (a.locationLabel != null) ...[
                const SizedBox(height: AppSpace.sm),
                CrmInfoLine(label: 'Konum', value: a.locationLabel!),
              ],
              if (a.address != null) ...[
                const SizedBox(height: AppSpace.sm),
                CrmInfoLine(label: 'Adres', value: a.address!),
              ],
              if (a.blocks.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                Text('Bloklar', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                const SizedBox(height: AppSpace.xs),
                _PillWrap(
                  labels: [
                    for (final b in a.blocks) '${b.name} • ${b.apartmentCount} daire',
                  ],
                  noun: 'blok',
                ),
              ],
              if (a.doors.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                Text('Kapılar', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                const SizedBox(height: AppSpace.xs),
                _PillWrap(labels: [for (final d in a.doors) d.name], noun: 'kapı'),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        DialogPanel(
          // Uyarı tonu yalnız BEKLEYEN başvuruda: karara bağlanmış başvuruda cihaz zaten kullanılmış olabilir.
          tone: a.isPending && a.hasDevice && a.deviceAvailable == false ? AppTone.warning : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(
                icon: Icons.developer_board_rounded,
                title: 'Cihaz',
                tone: AppTone.violet,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(_deviceText(a), style: th.bodyMedium),
            ],
          ),
        ),
        if (a.note != null) ...[
          const SizedBox(height: AppSpace.md),
          DialogPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DialogSectionTitle(
                  icon: Icons.notes_rounded,
                  title: 'Başvuran notu',
                  tone: AppTone.info,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(a.note!, style: th.bodyMedium),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        DialogPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(
                icon: Icons.schedule_rounded,
                title: 'Süreç',
                tone: AppTone.info,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'Başvuru: ${formatIstanbulDateTime(a.createdAt)} (İstanbul saati)',
                style: secondary,
              ),
              if (!a.isPending) ...[
                const SizedBox(height: AppSpace.xs),
                Text(_decisionText(a), style: secondary),
                if (a.decisionNote != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text('Gerekçe: ${a.decisionNote}', style: secondary),
                ],
                if (a.isApproved && a.siteCode != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text('Kurulan site kodu: ${a.siteCode}', style: secondary),
                ],
              ],
            ],
          ),
        ),
        if (a.isPending) ...[
          const SizedBox(height: AppSpace.lg),
          PrimaryActionButton(
            key: const ValueKey<String>('site_application_action_approve'),
            label: 'Onayla',
            icon: Icons.check_circle_outline,
            tone: AppTone.success,
            loading: _busyAction == 'approve',
            onPressed: _actionsLocked ? null : _approve,
          ),
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('site_application_action_reject'),
            label: 'Reddet',
            icon: Icons.cancel_outlined,
            tone: AppTone.danger,
            variant: AppButtonVariant.outline,
            loading: _busyAction == 'reject',
            onPressed: _actionsLocked ? null : _reject,
          ),
        ],
      ],
    );
  }

  static String _deviceText(SiteApplication a) {
    if (!a.hasDevice) return 'Cihaz seçilmedi. Cihaz sonra eklenebilir; site cihazsız kurulur.';
    final available = a.deviceAvailable;
    final uid = a.deviceUid!;
    if (!a.isPending) {
      return 'Başvuruda seçilen cihaz: $uid';
    }
    if (available == false) {
      return 'Başvuruda seçilen cihaz: $uid. Bu cihaz artık başvuranın hesabında değil; onaylarsanız site cihazsız kurulur.';
    }
    return 'Başvuruda seçilen cihaz: $uid. Onaylarsanız, uygunsa 1. kapıya bağlanır.';
  }

  static String _decisionText(SiteApplication a) {
    final who = a.decidedByName;
    final when = a.decidedAt == null ? '' : ' • ${formatIstanbulDateTime(a.decidedAt)}';
    if (a.isCancelled) {
      return 'Başvuran iptal etti$when';
    }
    return '${a.statusLabel}${who == null ? '' : ': $who'}$when';
  }

  static String _roleLabel(String role) {
    switch (role) {
      case 'individual':
        return 'Bireysel Kullanıcı';
      case 'apartment_owner':
        return 'Daire Kullanıcısı';
      case 'site_manager':
        return 'Site Yöneticisi';
      case 'super_user':
        return 'Süper Kullanıcı';
      default:
        return 'Diğer';
    }
  }
}

/// Uzun listeleri (100 bloğa kadar) sınırlı gösteren çip kümesi: ilk [limit] öğe, kalanı "+N blok daha".
class _PillWrap extends StatelessWidget {
  const _PillWrap({required this.labels, required this.noun});

  final List<String> labels;
  final String noun;

  static const int limit = 12;

  @override
  Widget build(BuildContext context) {
    final shown = labels.take(limit).toList(growable: false);
    final hidden = labels.length - shown.length;
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final label in shown) DialogMetaPill(label),
        if (hidden > 0) DialogMetaPill('+$hidden $noun daha'),
      ],
    );
  }
}

/// Reddetme penceresi: isteğe bağlı gerekçe (en çok 300 karakter). "Vazgeç" `null`, "Reddet" gerekçe metni
/// (boş olabilir) döndürür. Çift dokunuşta ikinci `pop` alttaki pencereyi kapatmaz ([popIfCurrent]).
class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.siteName});

  final String siteName;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// Gerekçe sınırı aşıldı mı? Sınırı aşan giriş (yapıştırma) sessizce KIRPILMAZ: sayaç ve hata gösterilir,
  /// "Reddet" kapanır.
  bool get _tooLong => _reason.text.trim().length > SiteApplicationDetailDialog.maxReasonLength;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return AppDialog(
      title: 'Başvuru reddedilsin mi?',
      icon: Icons.cancel_outlined,
      tone: AppTone.danger,
      actions: [
        TextButton(
          onPressed: () => popIfCurrent(context),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          style: filledToneStyle(context, tone: AppTone.danger),
          onPressed: _tooLong ? null : () => popIfCurrent<String>(context, _reason.text.trim()),
          child: const Text('Reddet'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"${widget.siteName}" başvurusu reddedilecek. Başvuran daha sonra yeniden başvurabilir. '
            'İsterseniz başvurana gösterilecek bir gerekçe yazabilirsiniz.',
            style: th.bodyMedium?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const ValueKey<String>('site_application_reject_reason'),
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            maxLength: SiteApplicationDetailDialog.maxReasonLength,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Gerekçe (isteğe bağlı)',
              alignLabelWithHint: true,
              errorText: _tooLong
                  ? 'Gerekçe en çok ${SiteApplicationDetailDialog.maxReasonLength} karakter olabilir.'
                  : null,
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
}
