import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/license_plate.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/history_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/residency_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/end_residency_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/vehicle_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/person_roles_panel.dart';

/// Kişi kartı penceresi (Platform Faz 2a): bilgiler, roller ([PersonRolesPanel], yalnız yönetimde), daireler ve
/// ilişki geçmişi, araçlar, not.
///
/// Kişi ayrıntısı açılışta çekilir (liste satırında not / ilişki geçmişi / araçlar yoktur): yüklenirken
/// iskelet, hata olursa "Tekrar Dene" gösterilir (boş kart ASLA çizilmez). Yazma düğmeleri ("Düzenle",
/// "Taşındı", "İlişki Ekle", "Araç Ekle", araç kaldırma) YALNIZ [PeopleScope.canWrite] iken vardır; kurul
/// üyesi salt okur (yalnız "Geçmiş" kalır). Her başarılı işlemden sonra kart güncel veriyle yenilenir ve
/// [onChanged] çağrılır (liste otomatik yenilenir).
///
/// Hesabı olan kişide ad / telefon / e-posta kişinin kendi profilinden değişir ("Düzenle"de salt okunur).
class PersonCardDialog extends StatefulWidget {
  const PersonCardDialog({
    super.key,
    required this.scope,
    required this.personId,
    this.initialName = '',
    this.onChanged,
  });

  final PeopleScope scope;
  final int personId;

  /// Ayrıntı gelene kadar başlıkta görünen ad (liste satırından).
  final String initialName;

  /// Başarılı her yazmadan sonra çağrılır.
  final VoidCallback? onChanged;

  static Future<void> show(
    BuildContext context, {
    required PeopleScope scope,
    required int personId,
    String initialName = '',
    VoidCallback? onChanged,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => PersonCardDialog(
        scope: scope,
        personId: personId,
        initialName: initialName,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<PersonCardDialog> createState() => _PersonCardDialogState();
}

class _PersonCardDialogState extends State<PersonCardDialog> {
  PersonDetail? _detail;
  bool _loading = false;
  String? _error;
  String? _actionError;
  final Set<int> _busyVehicles = <int>{};
  int _token = 0;

  bool get _canWrite => widget.scope.canWrite;

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
      final detail = await widget.scope.authService.getPerson(
        widget.scope.siteCode,
        widget.personId,
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
          'Kişi bilgileri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  /// Sunucudan dönen güncel kişiyi uygular ve listeye haber verir.
  void _apply(PersonDetail detail, String message) {
    if (!mounted) return;
    // Uçuştaki eski bir yükleme (yazmadan ÖNCE başlamış) bu yeni sonucu ezemesin.
    ++_token;
    setState(() {
      _detail = detail;
      _loading = false;
      _actionError = null;
    });
    widget.onChanged?.call();
    AppSnack.show(context, message, kind: AppSnackKind.success);
  }

  Future<void> _edit() async {
    final detail = _detail;
    if (detail == null) return;
    final result = await PersonFormDialog.show(
      context,
      scope: widget.scope,
      person: detail,
      onChanged: widget.onChanged,
    );
    if (result == null || !mounted) return;
    // Değişiklik yoksa (aynı nesne) mesaj gösterilmez.
    if (identical(result, detail)) return;
    _apply(result, 'Kişi bilgileri güncellendi.');
  }

  Future<void> _addResidency() async {
    final detail = _detail;
    if (detail == null) return;
    final result = await ResidencyDialog.show(
      context,
      scope: widget.scope,
      personId: detail.id,
      personName: detail.fullName,
    );
    if (result == null || !mounted) return;
    _apply(result, 'İlişki eklendi.');
  }

  /// Dairenin kartını (kat, tip, m², arsa payı, borç sorumlusu, sakinler) açar; yazma yetkisi yoksa salt okunur.
  Future<void> _openApartment(Residency residency) {
    return ApartmentCardDialog.show(
      context,
      scope: widget.scope,
      apartmentId: residency.apartmentId,
      initialLabel: residency.fullLabel,
      onChanged: widget.onChanged,
    );
  }

  Future<void> _editResidency(Residency residency) async {
    final detail = _detail;
    if (detail == null) return;
    final result = await ResidencyDialog.show(
      context,
      scope: widget.scope,
      personId: detail.id,
      personName: detail.fullName,
      residency: residency,
    );
    if (result == null || !mounted) return;
    _apply(result, 'İlişki güncellendi.');
  }

  Future<void> _endResidency(Residency residency) async {
    final detail = _detail;
    if (detail == null) return;
    final result = await EndResidencyDialog.show(
      context,
      scope: widget.scope,
      residency: residency,
      personName: detail.fullName,
      hasAccount: detail.hasAccount,
    );
    if (result == null || !mounted) return;
    _apply(result, 'Taşınma kaydedildi.');
  }

  Future<void> _addVehicle() async {
    final detail = _detail;
    if (detail == null) return;
    final vehicle = await VehicleDialog.show(
      context,
      scope: widget.scope,
      person: detail,
    );
    if (vehicle == null || !mounted) return;
    widget.onChanged?.call();
    AppSnack.show(context, 'Araç eklendi.', kind: AppSnackKind.success);
    await _load();
  }

  Future<void> _removeVehicle(VehicleRecord vehicle) async {
    final confirmed = await confirmCrmAction(
      context,
      title: 'Aracı kaldır',
      message: '${vehicle.displayPlate} plakalı araç kaldırılsın mı? Kayıt silinmez, pasifleşir.',
      confirmLabel: 'Kaldır',
      icon: Icons.delete_outline_rounded,
      tone: AppTone.danger,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busyVehicles.add(vehicle.id);
      _actionError = null;
    });
    try {
      await widget.scope.authService.removeVehicle(widget.scope.siteCode, vehicle.id);
      if (!mounted) return;
      _busyVehicles.remove(vehicle.id);
      widget.onChanged?.call();
      AppSnack.show(context, 'Araç kaldırıldı.', kind: AppSnackKind.success);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyVehicles.remove(vehicle.id);
        _actionError = crmMessageOf(
          e,
          'Araç kaldırılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  Future<void> _showHistory() {
    final detail = _detail;
    if (detail == null) return Future<void>.value();
    return HistoryDialog.show(
      context,
      scope: widget.scope,
      targetType: 'person',
      targetId: detail.id,
      title: detail.fullName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final title = (detail?.fullName ?? widget.initialName).trim();
    final Widget body;
    if (detail == null) {
      body = _loading || _error == null
          ? const DialogRowsSkeleton(rows: 3, caption: 'Kişi bilgileri yükleniyor...')
          : InlineNotice(message: _error!, onRetry: _load);
    } else {
      body = _buildDetail(context, detail);
    }
    return AppDialog(
      title: title.isEmpty ? 'Kişi' : title,
      subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
      icon: Icons.person_rounded,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
      child: body,
    );
  }

  Widget _buildDetail(BuildContext context, PersonDetail detail) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    final phone = formatPhoneDisplay(detail.phone);
    final current = detail.currentResidencies;
    final past = detail.pastResidencies;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          InlineNotice(message: _error!, onRetry: _load),
          const SizedBox(height: AppSpace.md),
        ],
        if (_actionError != null) ...[
          InlineNotice(message: _actionError!),
          const SizedBox(height: AppSpace.md),
        ],
        if (detail.hasAccount || !detail.isActive) ...[
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              if (detail.hasAccount)
                const StatusChip(
                  label: 'Hesabı var',
                  tone: AppTone.success,
                  icon: Icons.verified_user_rounded,
                ),
              if (!detail.isActive)
                const StatusChip(
                  label: 'Eski sakin',
                  tone: AppTone.neutral,
                  icon: Icons.history_rounded,
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        DialogPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(icon: Icons.badge_rounded, title: 'Bilgiler'),
              const SizedBox(height: AppSpace.md),
              CrmInfoLine(
                label: 'Telefon',
                value: phone.isEmpty ? 'Kayıtlı değil' : phone,
              ),
              const SizedBox(height: AppSpace.sm),
              CrmInfoLine(
                label: 'E-posta',
                value: (detail.email ?? '').isEmpty ? 'Kayıtlı değil' : detail.email!,
              ),
              // Notlar yönetime özeldir: salt okunur kurul üyesi görmez (sunucu da göndermez; savunmacı).
              if (_canWrite && (detail.note ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                CrmInfoLine(label: 'Not', value: detail.note!),
              ],
              if (detail.hasAccount) ...[
                const SizedBox(height: AppSpace.sm),
                Text(
                  detail.isInternalAccount
                      ? (_canWrite
                            ? 'Ad ve telefon kişinin kendi profilinden değişir. İletişim e-postası Düzenle ile değiştirilebilir.'
                            : 'Ad ve telefon kişinin kendi profilinden değişir.')
                      : 'Kişinin kendi profilinden değişir',
                  style: th.bodySmall,
                ),
              ],
              if (_canWrite) ...[
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
        // Roller (tanıtımdaki beş rol tek yerde): yalnız yönetim yetkisi olana; kurul üyesi salt okur.
        if (_canWrite) ...[
          PersonRolesPanel(
            key: ValueKey<int>(detail.id),
            scope: widget.scope,
            detail: detail,
            onAddResidency: _addResidency,
            onChanged: widget.onChanged,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        DialogPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(
                icon: Icons.apartment_rounded,
                title: 'Daireler ve ilişki geçmişi',
              ),
              const SizedBox(height: AppSpace.md),
              if (current.isEmpty && past.isEmpty)
                Text('Bu kişinin bağlı olduğu daire yok.', style: secondary),
              for (final residency in current) ...[
                _residencyRow(context, residency, isCurrent: true),
                const SizedBox(height: AppSpace.md),
              ],
              if (past.isNotEmpty) ...[
                Text('Eski ilişkiler', style: th.titleSmall),
                const SizedBox(height: AppSpace.sm),
                for (final residency in past) ...[
                  _residencyRow(context, residency, isCurrent: false),
                  const SizedBox(height: AppSpace.sm),
                ],
              ],
              if (_canWrite)
                PrimaryActionButton(
                  label: 'İlişki Ekle',
                  icon: Icons.add_link_rounded,
                  variant: AppButtonVariant.tonal,
                  onPressed: _addResidency,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        DialogPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(
                icon: Icons.directions_car_rounded,
                title: 'Araçlar',
                tone: AppTone.info,
              ),
              const SizedBox(height: AppSpace.md),
              if (detail.vehicles.isEmpty) Text('Kayıtlı araç yok.', style: secondary),
              for (final vehicle in detail.vehicles)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LicensePlateBadge(plate: vehicle.displayPlate, compact: true),
                          const SizedBox(height: AppSpace.xs),
                          if (_canWrite && (vehicle.note ?? '').isNotEmpty)
                            Text(vehicle.note!, style: th.bodySmall),
                        ],
                      ),
                    ),
                    if (_canWrite)
                      _busyVehicles.contains(vehicle.id)
                          ? const Padding(
                              padding: EdgeInsets.all(AppSpace.md),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              tooltip: '${vehicle.displayPlate} plakalı aracı kaldır',
                              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _removeVehicle(vehicle),
                            ),
                  ],
                ),
              if (_canWrite) ...[
                const SizedBox(height: AppSpace.sm),
                PrimaryActionButton(
                  label: 'Araç Ekle',
                  icon: Icons.add_rounded,
                  variant: AppButtonVariant.tonal,
                  onPressed: _addVehicle,
                ),
              ],
            ],
          ),
        ),
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

  Widget _residencyRow(
    BuildContext context,
    Residency residency, {
    required bool isCurrent,
  }) {
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(residency.fullLabel, style: th.titleSmall),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            RelationChip(residency.relation),
            InfoChip('Giriş: ${formatCrmDate(residency.moveInDate)}'),
            if (!isCurrent) InfoChip('Çıkış: ${formatCrmDate(residency.moveOutDate)}'),
          ],
        ),
        if (isCurrent) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              // Dairenin kat, tip, m², arsa payı ve borç sorumlusu bilgileri (kurul üyesi de salt okunur görür).
              PrimaryActionButton(
                label: 'Daire Bilgileri',
                icon: Icons.home_work_rounded,
                variant: AppButtonVariant.outline,
                expand: false,
                onPressed: () => _openApartment(residency),
              ),
              if (_canWrite) ...[
                PrimaryActionButton(
                  label: 'İlişkiyi Düzenle',
                  icon: Icons.edit_rounded,
                  variant: AppButtonVariant.outline,
                  expand: false,
                  onPressed: () => _editResidency(residency),
                ),
                PrimaryActionButton(
                  label: 'Taşındı',
                  icon: Icons.logout_rounded,
                  variant: AppButtonVariant.tonal,
                  tone: AppTone.warning,
                  expand: false,
                  onPressed: () => _endResidency(residency),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
