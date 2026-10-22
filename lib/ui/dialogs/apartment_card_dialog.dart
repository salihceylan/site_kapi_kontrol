import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_admin_dialogs.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_edit_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/history_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/residency_log_section.dart';

/// Daire kartı penceresi (Platform Faz 2a): alanlar (kat, m², arsa payı, kategori, borç ve bildirim
/// muhatabı), güncel malik / kiracı ve sakinler, geçmiş sakinler.
///
/// Ayrıntı açılışta çekilir: yüklenirken iskelet, hata olursa "Tekrar Dene" (boş kart ASLA çizilmez).
/// "Düzenle" YALNIZ [PeopleScope.canWrite] iken vardır (kurul üyesi salt okur). Başarılı düzenlemeden
/// sonra kart güncellenir ve [onChanged] çağrılır.
class ApartmentCardDialog extends StatefulWidget {
  const ApartmentCardDialog({
    super.key,
    required this.scope,
    required this.apartmentId,
    this.initialLabel = '',
    this.onChanged,
  });

  final PeopleScope scope;
  final int apartmentId;
  final String initialLabel;
  final VoidCallback? onChanged;

  static Future<void> show(
    BuildContext context, {
    required PeopleScope scope,
    required int apartmentId,
    String initialLabel = '',
    VoidCallback? onChanged,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ApartmentCardDialog(
        scope: scope,
        apartmentId: apartmentId,
        initialLabel: initialLabel,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<ApartmentCardDialog> createState() => _ApartmentCardDialogState();
}

class _ApartmentCardDialogState extends State<ApartmentCardDialog> {
  ApartmentDetail? _detail;
  bool _loading = false;
  String? _error;
  int _token = 0;

  /// Adli kayıt bölümü için tek servis (her yeniden çizimde yeni HTTP istemcisi açılmasın).
  late final ApartmentManagementService _residencyService = ApartmentManagementService(authService: widget.scope.authService);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
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
      final detail = await widget.scope.authService.getApartment(
        widget.scope.siteCode,
        widget.apartmentId,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(
          e,
          'Daire bilgileri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  Future<void> _edit() async {
    final detail = _detail;
    if (detail == null) return;
    final result = await ApartmentEditDialog.show(
      context,
      scope: widget.scope,
      apartment: detail,
    );
    if (result == null || !mounted || identical(result, detail)) return;
    // Uçuştaki eski bir yükleme (yazmadan ÖNCE başlamış) bu yeni sonucu ezemesin.
    ++_token;
    setState(() {
      _detail = result;
      _loading = false;
    });
    widget.onChanged?.call();
    AppSnack.show(context, 'Daire bilgileri güncellendi.', kind: AppSnackKind.success);
  }

  Future<void> _changeAdmin() async {
    final detail = _detail;
    if (detail == null) return;
    final changed = await ChangeAdminDialog.show(
      context,
      service: ApartmentManagementService(authService: widget.scope.authService),
      siteCode: widget.scope.siteCode,
      apartmentId: detail.id,
      apartmentLabel: detail.fullLabel,
    );
    if (changed && mounted) {
      widget.onChanged?.call();
      await _load();
    }
  }

  Future<void> _suspension() {
    final detail = _detail;
    if (detail == null) return Future<void>.value();
    return AccessSuspensionDialog.show(
      context,
      service: ApartmentManagementService(authService: widget.scope.authService),
      siteCode: widget.scope.siteCode,
      apartmentId: detail.id,
      apartmentLabel: detail.fullLabel,
    );
  }

  Future<void> _showHistory() {
    final detail = _detail;
    if (detail == null) return Future<void>.value();
    return HistoryDialog.show(
      context,
      scope: widget.scope,
      targetType: 'apartment',
      targetId: detail.id,
      title: detail.fullLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final title = (detail?.fullLabel ?? widget.initialLabel).trim();
    final Widget body;
    if (detail == null) {
      body = _loading || _error == null
          ? const DialogRowsSkeleton(rows: 3, caption: 'Daire bilgileri yükleniyor...')
          : InlineNotice(message: _error!, onRetry: _load);
    } else {
      body = _buildDetail(context, detail);
    }
    return AppDialog(
      title: title.isEmpty ? 'Daire' : title,
      subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
      icon: Icons.apartment_rounded,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
      child: body,
    );
  }

  Widget _buildDetail(BuildContext context, ApartmentDetail detail) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    String valueOrDash(String? v) => v == null || v.isEmpty ? 'Belirtilmemiş' : v;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          InlineNotice(message: _error!, onRetry: _load),
          const SizedBox(height: AppSpace.md),
        ],
        DialogPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(icon: Icons.info_outline_rounded, title: 'Bilgiler'),
              const SizedBox(height: AppSpace.md),
              CrmInfoLine(
                label: 'Kat',
                value: valueOrDash(detail.floor?.toString()),
              ),
              const SizedBox(height: AppSpace.sm),
              CrmInfoLine(label: 'Kategori', value: valueOrDash(detail.category)),
              const SizedBox(height: AppSpace.sm),
              CrmInfoLine(
                label: 'Brüt alan',
                value: valueOrDash(
                  detail.grossAreaM2 == null ? null : '${formatNumber(detail.grossAreaM2!)} m²',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              CrmInfoLine(
                label: 'Net alan',
                value: valueOrDash(
                  detail.netAreaM2 == null ? null : '${formatNumber(detail.netAreaM2!)} m²',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              CrmInfoLine(
                label: 'Arsa payı',
                value: valueOrDash(detail.landShare?.label),
              ),
              const SizedBox(height: AppSpace.sm),
              CrmInfoLine(
                label: 'Borç ve bildirimler kime gitsin',
                value: detail.responsibleParty.label,
              ),
              if (widget.scope.canWrite) ...[
                const SizedBox(height: AppSpace.md),
                PrimaryActionButton(
                  label: 'Düzenle',
                  icon: Icons.edit_rounded,
                  variant: AppButtonVariant.tonal,
                  onPressed: _edit,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        DialogPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(
                icon: Icons.groups_2_rounded,
                title: 'Malik, kiracı ve sakinler',
              ),
              const SizedBox(height: AppSpace.md),
              CrmInfoLine(
                label: 'Malik',
                value: detail.owner == null
                    ? 'Kayıtlı değil'
                    : crmPersonName(detail.owner!.fullName),
              ),
              const SizedBox(height: AppSpace.sm),
              CrmInfoLine(
                label: 'Kiracı',
                value: detail.tenant == null
                    ? 'Kayıtlı değil'
                    : crmPersonName(detail.tenant!.fullName),
              ),
              const SizedBox(height: AppSpace.md),
              if (detail.currentResidents.isEmpty)
                Text('Güncel sakin kaydı yok.', style: secondary),
              for (final resident in detail.currentResidents) ...[
                _residentRow(context, resident, past: false),
                const SizedBox(height: AppSpace.sm),
              ],
            ],
          ),
        ),
        if (detail.pastResidents.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          DialogPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DialogSectionTitle(
                  icon: Icons.history_rounded,
                  title: 'Geçmiş sakinler',
                  tone: AppTone.neutral,
                ),
                const SizedBox(height: AppSpace.md),
                for (final resident in detail.pastResidents) ...[
                  _residentRow(context, resident, past: true),
                  const SizedBox(height: AppSpace.sm),
                ],
              ],
            ),
          ),
        ],
        if (widget.scope.canWrite) ...[
          // Adli kayıt: YALNIZ yönetici / süper kullanıcı (canWrite); kurul ve görevli görmez, sunucu da 403 verir.
          const SizedBox(height: AppSpace.md),
          ResidencyLogSection(
            service: _residencyService,
            siteCode: widget.scope.siteCode,
            apartmentId: detail.id,
            apartmentLabel: detail.fullLabel,
          ),
          const SizedBox(height: AppSpace.md),
          PrimaryActionButton(
            label: 'Daire adminini değiştir',
            icon: Icons.manage_accounts_rounded,
            variant: AppButtonVariant.outline,
            onPressed: _changeAdmin,
          ),
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            label: 'Kapı erişimi (askıya alma)',
            icon: Icons.lock_person_rounded,
            variant: AppButtonVariant.outline,
            onPressed: _suspension,
          ),
        ],
        const SizedBox(height: AppSpace.md),
        PrimaryActionButton(
          label: 'Geçmiş',
          icon: Icons.history_rounded,
          variant: AppButtonVariant.outline,
          onPressed: _showHistory,
        ),
      ],
    );
  }

  Widget _residentRow(
    BuildContext context,
    ApartmentResident resident, {
    required bool past,
  }) {
    final th = Theme.of(context).textTheme;
    final name = crmPersonName(resident.fullName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: th.titleSmall),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            RelationChip(resident.relation),
            InfoChip('Giriş: ${formatCrmDate(resident.moveInDate)}'),
            if (past) InfoChip('Çıkış: ${formatCrmDate(resident.moveOutDate)}'),
            if (resident.hasAccount && !past)
              const StatusChip(
                label: 'Hesabı var',
                tone: AppTone.success,
                icon: Icons.verified_user_rounded,
              ),
          ],
        ),
      ],
    );
  }
}
