import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/staff_role_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/staff_role_card.dart';

/// Rol bölümünün başındaki düz Türkçe açıklama (Modüller ve Kişiler ekranlarında aynı metin).
const String staffRolesIntro =
    'İsterseniz bir kişiye Yönetim Kurulu / Denetçi (yalnız görüntüler) ya da Görevli rolü '
    'verebilirsiniz. Rol vermezseniz bu işlerin hepsi sizde kalır.';

/// Yönetim Kurulu / Denetçi ve Görevli rolleri bölümü: açıklama, rol listesi, "Rol Ekle" ([StaffRoleDialog]) ve
/// "Rolü Kaldır" ([StaffRoleCard]). Modüller ekranı ve Kişiler ekranındaki "Yönetim Kurulu ve Görevliler" penceresi
/// AYNI bileşeni kullanır. Veriyi kendisi çeker; [StaffRolesSectionState.reload] dışarıdan da çağrılır. [siteCode]
/// değişince liste atılır ve yeni site yüklenir; eski sitenin geç gelen yanıtı yok sayılır.
class StaffRolesSection extends StatefulWidget {
  const StaffRolesSection({
    super.key,
    required this.authService,
    required this.siteCode,
    this.siteName,
    this.title = 'Ek Roller',
  });

  final AuthService authService;
  final int siteCode;
  final String? siteName;

  /// Bölüm başlığı.
  final String title;

  @override
  State<StaffRolesSection> createState() => StaffRolesSectionState();
}

class StaffRolesSectionState extends State<StaffRolesSection> {
  List<StaffRoleRecord>? _roles;
  bool _loading = true;
  String? _error;
  final Set<int> _busy = <int>{};
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void didUpdateWidget(StaffRolesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteCode != widget.siteCode) {
      _roles = null;
      _error = null;
      _busy.clear();
      unawaited(reload());
    }
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  String _messageOf(Object error, String fallback) {
    if (error is ApiException && error.message.trim().isNotEmpty) return error.message;
    return fallback;
  }

  /// Rolleri yeniden çeker. [silent]: yükleme göstergesi ve hata kutusu açılmaz (arka planda tazeleme).
  Future<void> reload({bool silent = false}) async {
    if (!mounted) return;
    final siteCode = widget.siteCode;
    final token = ++_token;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final next = await widget.authService.listStaffRoles(siteCode);
      if (!mounted || token != _token || widget.siteCode != siteCode) return;
      setState(() {
        _roles = next;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || token != _token || widget.siteCode != siteCode) return;
      setState(() {
        _loading = false;
        if (!silent) {
          _error = _messageOf(
            e,
            'Ek roller yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          );
        }
      });
    }
  }

  Future<void> _add() async {
    final added = await StaffRoleDialog.show(
      context,
      authService: widget.authService,
      siteCode: widget.siteCode,
      siteName: widget.siteName,
    );
    if (added == true && mounted) {
      AppSnack.show(context, 'Ek rol atandı.', kind: AppSnackKind.success);
      unawaited(reload());
    }
  }

  Future<bool> _confirmRemove(String who, StaffRoleRecord record) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Rol Kaldırılsın mı?',
        icon: Icons.person_remove_rounded,
        tone: AppTone.warning,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: filledToneStyle(ctx, tone: AppTone.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Kaldır'),
          ),
        ],
        child: Text(
          '$who kişisinin "${record.roleLabel}" rolü kaldırılacak. Kişi dairesindeki yetkileriyle kalır.',
        ),
      ),
    );
    return result == true;
  }

  Future<void> _remove(StaffRoleRecord record) async {
    if (_busy.contains(record.userCode)) return;
    final who = record.fullName.trim().isEmpty ? record.email : record.fullName;
    final ok = await _confirmRemove(who, record);
    if (!ok || !mounted) return;
    setState(() => _busy.add(record.userCode));
    try {
      await widget.authService.removeStaffRole(widget.siteCode, record.userCode);
      if (!mounted) return;
      AppSnack.show(context, 'Ek rol kaldırıldı.', kind: AppSnackKind.success);
      unawaited(reload());
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        _messageOf(e, 'Rol kaldırılamadı. Sunucuya bağlanılamadı.'),
        kind: AppSnackKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy.remove(record.userCode));
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final roles = _roles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: widget.title,
          trailing: TextButton.icon(
            key: const ValueKey<String>('staff_roles_add'),
            onPressed: _add,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Rol Ekle'),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(staffRolesIntro, style: th.bodyMedium),
        const SizedBox(height: AppSpace.md),
        if (_loading && roles == null)
          const ListSkeleton(rows: 2)
        else ...[
          // Yükleme hatası HER durumda gösterilir (liste boşken "Ek rol atanmamış." diye gizlenmez).
          if (_error != null) ...[
            InlineNotice(message: _error!, onRetry: () => unawaited(reload())),
            if (roles != null && roles.isNotEmpty) const SizedBox(height: AppSpace.md),
          ],
          if (roles != null && roles.isEmpty && _error == null)
            const EmptyCard(
              icon: Icons.groups_rounded,
              title: 'Ek rol atanmamış.',
              message:
                  'İsterseniz bir kişiye Yönetim Kurulu / Denetçi ya da Görevli rolü verebilirsiniz.',
            ),
          for (var i = 0; i < (roles?.length ?? 0); i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: StaggeredEntry(
                index: i,
                child: StaffRoleCard(
                  record: roles![i],
                  busy: _busy.contains(roles[i].userCode),
                  onRemove: () => unawaited(_remove(roles[i])),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Kişiler ekranındaki "Yönetim Kurulu ve Görevliler" penceresi: [StaffRolesSection]'ı bir pencerede açar.
class StaffRolesDialog {
  const StaffRolesDialog._();

  static Future<void> show(
    BuildContext context, {
    required AuthService authService,
    required int siteCode,
    String? siteName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Yönetim Kurulu ve Görevliler',
        subtitle: siteName == null || siteName.trim().isEmpty ? null : siteName.trim(),
        icon: Icons.badge_rounded,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Kapat'),
          ),
        ],
        child: StaffRolesSection(
          authService: authService,
          siteCode: siteCode,
          siteName: siteName,
          title: 'Atanmış kişiler',
        ),
      ),
    );
  }
}
