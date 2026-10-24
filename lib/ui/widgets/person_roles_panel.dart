import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/create_guest_pass_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/duty_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/dialogs/staff_role_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart' show RelationChip;

/// Kişi kartındaki "Roller" bölümü: tanıtımdaki beş rolün hepsi tek yerde (yalnız yönetim yetkisi olana).
///
/// - Site yöneticisi: kişinin e-postasına ortak yönetici daveti (`inviteSiteManager`).
/// - Yönetim kurulu ve denetçi / Görevli: ek rol ver / kaldır (`assignStaffRole` / `removeStaffRole`); kişinin
///   kendi e-postasıyla açılmış hesabı olmalıdır (daire hesabı ve hesapsız kişi için nedeni yazılır).
/// - Daire sakini: kartın "İlişki Ekle" akışı ([onAddResidency]).
/// - Misafir ve kurye: sitenin kapısından süreli geçiş bağlantısı ([CreateGuestPassDialog]).
///
/// Mevcut roller açılışta yönetici ve ek rol listelerinden çekilir; her işlemden sonra yeniden çekilir ve
/// [onChanged] çağrılır.
class PersonRolesPanel extends StatefulWidget {
  const PersonRolesPanel({
    super.key,
    required this.scope,
    required this.detail,
    required this.onAddResidency,
    this.onChanged,
  });

  final PeopleScope scope;
  final PersonDetail detail;
  final Future<void> Function() onAddResidency;
  final VoidCallback? onChanged;

  @override
  State<PersonRolesPanel> createState() => _PersonRolesPanelState();
}

class _PersonRolesPanelState extends State<PersonRolesPanel> {
  List<StaffRoleRecord> _staff = const <StaffRoleRecord>[];
  SiteManagersData? _managers;
  TeamData? _team;
  PersonInvitationState? _invite;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _token = 0;

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
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = widget.scope.authService;
    try {
      final results = await Future.wait<Object?>(<Future<Object?>>[
        auth.listStaffRoles(widget.scope.siteCode),
        auth.getSiteManagers(widget.scope.siteCode),
      ]);
      if (!mounted || token != _token) return;
      final managers = results[1] as SiteManagersData?;
      // Kadro ve davet durumu ek bilgidir: yüklenemezse bölüm yine açılır, ilgili satır dürüst not gösterir.
      TeamData? team;
      PersonInvitationState? invite;
      try {
        team = await auth.getTeam(widget.scope.siteCode);
      } catch (_) {
        team = null;
      }
      if (!_person.hasAccount) {
        try {
          invite = await auth.getPersonInvitation(widget.scope.siteCode, _person.id);
        } catch (_) {
          invite = null;
        }
      }
      if (!mounted || token != _token) return;
      setState(() {
        _team = team;
        _invite = invite;
        _staff = results[0]! as List<StaffRoleRecord>;
        _managers = managers;
        _loading = false;
        _error = managers == null ? 'Roller yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.' : null;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Roller yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  PersonDetail get _person => widget.detail;
  String get _email => (_person.email ?? '').trim();
  String get _name => _person.fullName.trim();

  bool get _isManager {
    final code = _person.userCode;
    return code != null && (_managers?.managers.any((m) => m.userCode == code) ?? false);
  }

  bool get _invitePending {
    final email = _email.toLowerCase();
    if (email.isEmpty) return false;
    return _managers?.invitations.any((i) => i.email.trim().toLowerCase() == email && i.status == 'pending') ??
        false;
  }

  StaffRoleRecord? get _staffRole {
    final code = _person.userCode;
    if (code == null) return null;
    for (final record in _staff) {
      if (record.userCode == code) return record;
    }
    return null;
  }

  TeamDuty? get _duty => _team?.dutyOf(_person.id);

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      AppSnack.show(context, success, kind: AppSnackKind.success);
      widget.onChanged?.call();
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnack.show(context, StaffRoleDialog.messageFor(e), kind: AppSnackKind.error);
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        crmMessageOf(e, 'İşlem yapılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'),
        kind: AppSnackKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inviteManager() async {
    final confirmed = await confirmCrmAction(
      context,
      title: 'Site yöneticisi olarak davet et',
      message: '$_name ($_email) adresine ortak yönetici daveti gönderilsin mi? Daveti kabul edince siteyi '
          'sizinle birlikte yönetir.',
      confirmLabel: 'Davet Gönder',
      icon: Icons.manage_accounts_rounded,
    );
    if (!confirmed || !mounted) return;
    await _run(() async {
      final (ok, error) = await widget.scope.authService.inviteSiteManager(
        widget.scope.siteCode,
        email: _email,
        fullName: _name.isEmpty ? null : _name,
      );
      if (!ok) throw StateError(error ?? 'Davet gönderilemedi.');
    }, 'Yönetici daveti gönderildi.');
  }

  Future<void> _setDuty() async {
    final choice = await DutyDialog.show(context, personName: _name, current: _duty);
    if (choice == null || !mounted) return;
    await _run(
      () => widget.scope.authService.setTeamDuty(
        widget.scope.siteCode,
        _person.id,
        duty: choice.duty,
        title: choice.title,
        publicPhone: choice.publicPhone,
        showInDirectory: choice.showInDirectory,
      ),
      'Görev kaydedildi.',
    );
  }

  Future<void> _endDuty() async {
    final confirmed = await confirmCrmAction(
      context,
      title: 'Görev kaldırılsın mı?',
      message: '$_name kişisinin görevi kaldırılsın mı? Kişi kaydı ve daire bilgileri değişmez; görevden gelen '
          'uygulama yetkisi kapanır.',
      confirmLabel: 'Görevi Kaldır',
      icon: Icons.person_remove_rounded,
      tone: AppTone.danger,
    );
    if (!confirmed || !mounted) return;
    await _run(() => widget.scope.authService.endTeamDuty(widget.scope.siteCode, _person.id), 'Görev kaldırıldı.');
  }

  Future<void> _sendInvite() async {
    await _run(() async {
      final state = await widget.scope.authService.sendPersonInvitation(widget.scope.siteCode, _person.id);
      if (state.sent == false) {
        throw StateError('Davet kaydedildi ama e-posta gönderilemedi. Biraz sonra "Yeniden Gönder" deyin.');
      }
    }, 'Davet e-postası gönderildi.');
  }

  Future<void> _revokeInvite() async {
    await _run(
      () => widget.scope.authService.revokePersonInvitation(widget.scope.siteCode, _person.id),
      'Davet iptal edildi.',
    );
  }

  Future<void> _removeStaff(StaffRoleRecord record) async {
    final confirmed = await confirmCrmAction(
      context,
      title: 'Rol kaldırılsın mı?',
      message: '$_name kişisinin "${record.roleLabel}" rolü kaldırılsın mı? Kişinin hesabı ve daire kayıtları '
          'değişmez.',
      confirmLabel: 'Rolü Kaldır',
      icon: Icons.person_remove_rounded,
      tone: AppTone.danger,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => widget.scope.authService.removeStaffRole(widget.scope.siteCode, record.userCode),
      'Rol kaldırıldı.',
    );
  }

  Future<void> _guestPass() async {
    setState(() => _busy = true);
    final (doors, error) = await widget.scope.authService.listMyDoors();
    if (!mounted) return;
    setState(() => _busy = false);
    final siteDoors = (doors ?? const <DoorRecord>[])
        .where((d) => d.siteCode == widget.scope.siteCode && d.isActive)
        .toList();
    if (siteDoors.isEmpty) {
      AppSnack.show(
        context,
        error ??
            'Bu sitede geçiş bağlantısı oluşturulabilecek kapı yok. Geçiş Kontrol modülünün açık ve kapının '
                'tanımlı olması gerekir.',
        kind: AppSnackKind.error,
      );
      return;
    }
    final door = siteDoors.length == 1 ? siteDoors.first : await _pickDoor(siteDoors);
    if (door == null || !mounted) return;
    await CreateGuestPassDialog.show(
      context,
      door: door,
      authService: widget.scope.authService,
      showMessage: (message) => AppSnack.show(context, message),
    );
  }

  Future<DoorRecord?> _pickDoor(List<DoorRecord> doors) {
    return showDialog<DoorRecord>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Hangi kapı için?'),
        children: [
          for (final door in doors)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(door),
              child: Text(door.doorName),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: context.palette.textSecondary);
    final staffRole = _staffRole;
    final isResident = _person.currentResidencies.isNotEmpty;
    final chips = <Widget>[
      if (_isManager)
        const StatusChip(label: 'Site yöneticisi', tone: AppTone.primary, icon: Icons.manage_accounts_rounded),
      if (_invitePending)
        const StatusChip(label: 'Yönetici daveti bekliyor', tone: AppTone.warning, icon: Icons.schedule_rounded),
      if (_duty != null) StatusChip(label: _duty!.label, tone: AppTone.info, icon: Icons.badge_rounded),
      if (staffRole != null && _duty == null) StatusChip(label: staffRole.roleLabel, tone: AppTone.info, icon: Icons.badge_rounded),
      if (_person.isAdmin)
        const StatusChip(label: 'Daire Admini', tone: AppTone.warning, icon: Icons.shield_rounded),
      for (final rel in _person.relations)
        RelationChip(rel),
      if (isResident && _person.relations.isEmpty)
        const StatusChip(label: 'Daire sakini', tone: AppTone.success, icon: Icons.home_rounded),
    ];

    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DialogSectionTitle(icon: Icons.admin_panel_settings_rounded, title: 'Roller'),
          const SizedBox(height: AppSpace.md),
          if (_loading)
            Text('Roller yükleniyor...', style: secondary)
          else if (_error != null)
            InlineNotice(message: _error!, onRetry: _load)
          else ...[
            if (chips.isEmpty)
              Text('Bu kişinin bu sitede bir rolü yok. Aşağıdan rol verebilirsiniz.', style: secondary)
            else
              Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: chips),
            const SizedBox(height: AppSpace.lg),
            _RoleRow(
              title: 'Site yöneticisi',
              description: 'Siteyi, daireleri, sakinleri ve modülleri sizinle birlikte yönetir.',
              note: _isManager
                  ? 'Kişi bu sitenin yöneticisi.'
                  : _invitePending
                  ? 'Davet gönderildi; kişinin kabul etmesi bekleniyor.'
                  : _email.isEmpty
                  ? 'Davet için kişinin e-posta adresi olmalı (Düzenle ile ekleyebilirsiniz).'
                  : null,
              actionLabel: _isManager || _invitePending || _email.isEmpty ? null : 'Yönetici Olarak Davet Et',
              actionIcon: Icons.manage_accounts_rounded,
              onAction: _busy ? null : _inviteManager,
            ),
            _dutyRow(),
            if (staffRole != null && _duty == null)
              _RoleRow(
                title: 'Eski ek rol',
                description: 'Kişi kaydına bağlı olmayan eski rol; Görev ver ile kadroya alabilirsiniz.',
                note: 'Kişide "${staffRole.roleLabel}" rolü var.',
                actionLabel: 'Rolü Kaldır',
                actionIcon: Icons.person_remove_rounded,
                danger: true,
                onAction: _busy ? null : () => _removeStaff(staffRole),
              ),
            if (!(_person.hasAccount && !_person.isInternalAccount)) _inviteRow(),
            _RoleRow(
              title: 'Daire sakini',
              description: 'Kapıyı açar; duyurularını, borcunu ve kendi kayıtlarını görür.',
              actionLabel: isResident ? 'Başka Bir Daireye Bağla' : 'Daireye Bağla',
              actionIcon: Icons.add_home_rounded,
              onAction: _busy ? null : widget.onAddResidency,
            ),
            _RoleRow(
              title: 'Misafir ve kurye',
              description: 'Kendisine gönderilen süreli bağlantıyla kapıdan geçer.',
              actionLabel: 'Geçiş Bağlantısı Oluştur',
              actionIcon: Icons.qr_code_2_rounded,
              onAction: _busy ? null : _guestPass,
              last: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _dutyRow() {
    const description = 'Yönetim kurulu, denetçi, kapıcı, teknik görevli, danışma ya da başka görev. Görev kişi '
        'kaydına bağlıdır; hesabı olmasa da kadroda görünür.';
    final duty = _duty;
    if (_isManager) {
      return const _RoleRow(
        title: 'Görev',
        description: description,
        note: 'Kişi zaten site yöneticisi; görev gerekmez.',
        actionIcon: Icons.badge_rounded,
      );
    }
    if (_team == null) {
      return const _RoleRow(
        title: 'Görev',
        description: description,
        note: 'Kadro bilgisi yüklenemedi. Kartı kapatıp tekrar açın.',
        actionIcon: Icons.badge_rounded,
      );
    }
    if (duty == null) {
      return _RoleRow(
        title: 'Görev',
        description: description,
        actionLabel: 'Görev Ver',
        actionIcon: Icons.badge_rounded,
        onAction: _busy ? null : _setDuty,
      );
    }
    return _RoleRow(
      title: 'Görev',
      description: description,
      note: '${duty.label}. ${teamAccessText(duty.access)}',
      actionLabel: 'Görevi Düzenle',
      actionIcon: Icons.edit_rounded,
      onAction: _busy ? null : _setDuty,
      secondaryLabel: 'Görevi Kaldır',
      secondaryIcon: Icons.person_remove_rounded,
      onSecondary: _busy ? null : _endDuty,
    );
  }

  Widget _inviteRow() {
    const description = 'E-postası olan ama uygulamada hesabı olmayan kişiye 7 gün geçerli, tek kullanımlık '
        'davet gönderilir.';
    final invite = _invite;
    final blockText = invitationBlockText(
      _person.isInternalAccount ? 'PERSON_INTERNAL_ACCOUNT' : (_email.isEmpty ? 'PERSON_NO_EMAIL' : invite?.blockReason),
    );
    if (blockText.isNotEmpty) {
      return _RoleRow(title: 'Uygulamaya davet', description: description, note: blockText, actionIcon: Icons.mail_rounded);
    }
    if (invite == null) {
      return const _RoleRow(
        title: 'Uygulamaya davet',
        description: description,
        note: 'Davet durumu yüklenemedi. Kartı kapatıp tekrar açın.',
        actionIcon: Icons.mail_rounded,
      );
    }
    if (invite.isPending) {
      return _RoleRow(
        title: 'Uygulamaya davet',
        description: description,
        note: 'Davet gönderildi (${invite.sendCount}/5); kişinin kabul etmesi bekleniyor.',
        actionLabel: 'Yeniden Gönder',
        actionIcon: Icons.send_rounded,
        onAction: _busy ? null : _sendInvite,
        secondaryLabel: 'Daveti İptal Et',
        secondaryIcon: Icons.close_rounded,
        onSecondary: _busy ? null : _revokeInvite,
      );
    }
    return _RoleRow(
      title: 'Uygulamaya davet',
      description: description,
      note: invite.status == 'expired' ? 'Önceki davetin süresi doldu.' : null,
      actionLabel: 'Uygulamaya Davet Et',
      actionIcon: Icons.mail_rounded,
      onAction: _busy ? null : _sendInvite,
    );
  }
}

/// Tek rol satırı: ad, kısa açıklama, (varsa) durum notu ve işlem düğmesi alt alta (dar ekranda taşmaz).
class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.title,
    required this.description,
    required this.actionIcon,
    this.actionLabel,
    this.note,
    this.onAction,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
    this.danger = false,
    this.last = false,
  });

  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final Future<void> Function()? onSecondary;

  final String title;
  final String description;
  final String? note;
  final String? actionLabel;
  final IconData actionIcon;
  final Future<void> Function()? onAction;
  final bool danger;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final action = onAction;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: th.titleSmall),
          const SizedBox(height: AppSpace.xs),
          Text(description, style: th.bodySmall),
          if (note != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text(note!, style: th.bodySmall?.copyWith(color: context.palette.textSecondary)),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpace.sm),
            PrimaryActionButton(
              label: actionLabel!,
              icon: actionIcon,
              tone: danger ? AppTone.danger : AppTone.primary,
              variant: AppButtonVariant.tonal,
              onPressed: action == null ? null : () => unawaited(action()),
            ),
          ],
          if (secondaryLabel != null) ...[
            const SizedBox(height: AppSpace.sm),
            PrimaryActionButton(
              label: secondaryLabel!,
              icon: secondaryIcon ?? Icons.close_rounded,
              tone: AppTone.danger,
              variant: AppButtonVariant.tonal,
              onPressed: onSecondary == null ? null : () => unawaited(onSecondary!()),
            ),
          ],
        ],
      ),
    );
  }
}
