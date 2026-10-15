import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/staff_role_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/module_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/staff_role_card.dart';

/// Geçiş Kontrol kapatılırken gösterilen uyarı (sunucunun `MODULE_CONFIRM_REQUIRED` metniyle aynı).
const String doorControlOffWarning =
    'Geçiş Kontrol kapatılırsa telefondan kapı açma, QR ve misafir geçişi durur. Onaylıyor musunuz?';

/// "Modüller" ekranı (Platform modül sistemi Faz 1): site seçici, modül kartları (anahtar), Geçiş
/// Kontrol kapatılırken onay penceresi ve "Ek roller" bölümü (listele / ekle / kaldır).
///
/// Süper kullanıcıda tüm siteler, site yöneticisinde yönettiği siteler listelenir (yalnız onaylı
/// siteler: modül onaysız sitede anlamsızdır). Veriyi kendisi çeker; [ModulesViewState.reload]
/// sayfa kabuğunun aşağı çekip yenilemesinden de çağrılır. Her başarılı işlemden sonra ilgili veri
/// otomatik yeniden çekilir ve [onModulesChanged] çağrılır (menü süzgeci hemen tazelenir).
class ModulesView extends StatefulWidget {
  const ModulesView({
    super.key,
    required this.authService,
    this.onModulesChanged,
  });

  final AuthService authService;

  /// Bir modül açılıp kapatılınca (başarılı işlem sonrası) çağrılır.
  final VoidCallback? onModulesChanged;

  @override
  State<ModulesView> createState() => ModulesViewState();
}

class ModulesViewState extends State<ModulesView> {
  List<SiteRecord> _sites = const <SiteRecord>[];
  bool _loadingSites = false;
  String? _sitesError;
  int? _siteCode;

  SiteModulesState? _state;
  bool _loadingState = false;
  String? _stateError;

  List<StaffRoleRecord>? _roles;
  bool _loadingRoles = false;
  String? _rolesError;

  final Set<String> _busyModules = <String>{};
  final Set<int> _busyRoles = <int>{};

  // Yarış koruması: yalnız en son başlatılan istek sonucu uygulanır.
  int _sitesToken = 0;
  int _modulesToken = 0;
  int _rolesToken = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  String _messageOf(Object error, String fallback) {
    if (error is ApiException && error.message.trim().isNotEmpty) {
      return error.message;
    }
    return fallback;
  }

  /// Siteleri ve seçili sitenin modül + ek rol verisini yeniden çeker (mevcut ekran yenileme sürerken
  /// korunur).
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_sitesToken;
    setState(() {
      _loadingSites = true;
      _sitesError = null;
    });
    try {
      final page = await widget.authService.listSites(page: 1, pageSize: 100);
      if (!mounted || token != _sitesToken) return;
      final sites = page.sites.where((s) => s.isApproved).toList(growable: false);
      final keep = _siteCode != null && sites.any((s) => s.id == _siteCode);
      final next = keep ? _siteCode : (sites.isEmpty ? null : sites.first.id);
      setState(() {
        _sites = sites;
        _loadingSites = false;
        _siteCode = next;
        if (next == null) {
          _state = null;
          _roles = null;
        }
      });
      if (next != null) await _loadSiteData(next);
    } catch (e) {
      if (!mounted || token != _sitesToken) return;
      setState(() {
        _loadingSites = false;
        _sitesError = _messageOf(
          e,
          'Siteler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  Future<void> _selectSite(int siteCode) async {
    if (siteCode == _siteCode) return;
    setState(() {
      _siteCode = siteCode;
      _state = null;
      _roles = null;
      _stateError = null;
      _rolesError = null;
    });
    await _loadSiteData(siteCode);
  }

  /// Seçili sitenin modül durumunu ve/veya ek rollerini çeker. [silent] true iken yükleme göstergesi
  /// açılmaz (işlem sonrası arka planda tazeleme).
  Future<void> _loadSiteData(
    int siteCode, {
    bool modules = true,
    bool roles = true,
    bool silent = false,
  }) async {
    await Future.wait(<Future<void>>[
      if (modules) _loadModules(siteCode, silent: silent),
      if (roles) _loadRoles(siteCode, silent: silent),
    ]);
  }

  Future<void> _loadModules(int siteCode, {bool silent = false}) async {
    // Başka siteye geçildiyse eski sitenin (işlem sonrası) tazelemesi yeni sitenin yüklemesinin
    // jetonunu geçersiz kılıp onu iskelette bırakmasın.
    if (!mounted || _siteCode != siteCode) return;
    final token = ++_modulesToken;
    if (!silent) {
      setState(() {
        _loadingState = true;
        _stateError = null;
      });
    }
    try {
      final next = await widget.authService.getSiteModules(siteCode);
      if (!mounted || token != _modulesToken || _siteCode != siteCode) return;
      setState(() {
        _state = next;
        _loadingState = false;
        _stateError = null;
      });
    } catch (e) {
      if (!mounted || token != _modulesToken || _siteCode != siteCode) return;
      setState(() {
        _loadingState = false;
        if (!silent) {
          _stateError = _messageOf(
            e,
            'Modüller yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          );
        }
      });
    }
  }

  Future<void> _loadRoles(int siteCode, {bool silent = false}) async {
    if (!mounted || _siteCode != siteCode) return;
    final token = ++_rolesToken;
    if (!silent) {
      setState(() {
        _loadingRoles = true;
        _rolesError = null;
      });
    }
    try {
      final next = await widget.authService.listStaffRoles(siteCode);
      if (!mounted || token != _rolesToken || _siteCode != siteCode) return;
      setState(() {
        _roles = next;
        _loadingRoles = false;
        _rolesError = null;
      });
    } catch (e) {
      if (!mounted || token != _rolesToken || _siteCode != siteCode) return;
      setState(() {
        _loadingRoles = false;
        if (!silent) {
          _rolesError = _messageOf(
            e,
            'Ek roller yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          );
        }
      });
    }
  }

  // --- Modül açma / kapama ---------------------------------------------------------------

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    IconData icon = Icons.warning_amber_rounded,
    AppTone tone = AppTone.warning,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: title,
        icon: icon,
        tone: tone,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: filledToneStyle(ctx, tone: AppTone.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
        child: Text(message),
      ),
    );
    return result == true;
  }

  Future<void> _toggle(PlatformModule module, bool value) async {
    final state = _state;
    if (state == null || _busyModules.contains(module.code)) return;
    var confirmed = false;
    if (!value && module.code == PlatformModuleCodes.doorControl) {
      final ok = await _confirm(
        title: 'Geçiş Kontrol Kapatılsın mı?',
        message: doorControlOffWarning,
        confirmLabel: 'Kapat',
      );
      if (!ok || !mounted) return;
      confirmed = true;
    }
    await _applyToggle(state.siteCode, module, value, confirm: confirmed);
  }

  Future<void> _applyToggle(
    int siteCode,
    PlatformModule module,
    bool value, {
    required bool confirm,
  }) async {
    setState(() => _busyModules.add(module.code));
    var retryWithConfirm = false;
    String? serverWarning;
    // İşlem sonucu ne olursa olsun (başarı, hata, zaman aşımı - "işlem tamamlanmış olabilir" - ya da
    // ekranın kapanması) menü/panel süzgeci sunucudan yeniden okunur: geri çağrı State'ten ÖNCE alınır.
    final onChanged = widget.onModulesChanged;
    try {
      final next = await widget.authService.setSiteModule(
        siteCode,
        module.code,
        value,
        confirm: confirm,
      );
      if (!mounted) return;
      if (_siteCode == siteCode) setState(() => _state = next);
      AppSnack.show(
        context,
        value ? '${module.name} açıldı.' : '${module.name} kapatıldı.',
        kind: AppSnackKind.success,
      );
      // İşlem sonrası otomatik yeniden çekme (başka bir yöneticinin değişikliği de görünür).
      if (_siteCode == siteCode) {
        unawaited(_loadSiteData(siteCode, roles: false, silent: true));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'MODULE_CONFIRM_REQUIRED' && !confirm) {
        // Onay penceresi atlanmışsa (örn. eski sürüm akışı) sunucunun uyarısı gösterilir.
        retryWithConfirm = true;
        serverWarning = e.message;
      } else {
        AppSnack.show(context, e.message, kind: AppSnackKind.error);
      }
    } catch (_) {
      if (!mounted) return;
      AppSnack.show(
        context,
        'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        kind: AppSnackKind.error,
      );
    } finally {
      if (mounted) setState(() => _busyModules.remove(module.code));
      onChanged?.call();
    }
    if (retryWithConfirm && mounted) {
      final ok = await _confirm(
        title: 'Onay Gerekli',
        message: serverWarning ?? doorControlOffWarning,
        confirmLabel: 'Onayla',
      );
      if (ok && mounted) {
        await _applyToggle(siteCode, module, value, confirm: true);
      }
    }
  }

  // --- Ek roller ---------------------------------------------------------------------------

  Future<void> _addRole() async {
    final code = _siteCode;
    if (code == null) return;
    final site = _sites.where((s) => s.id == code).firstOrNull;
    final added = await StaffRoleDialog.show(
      context,
      authService: widget.authService,
      siteCode: code,
      siteName: site?.name,
    );
    if (added == true && mounted) {
      AppSnack.show(context, 'Ek rol atandı.', kind: AppSnackKind.success);
      unawaited(_loadRoles(code));
    }
  }

  Future<void> _removeRole(StaffRoleRecord record) async {
    final code = _siteCode;
    if (code == null || _busyRoles.contains(record.userCode)) return;
    final who = record.fullName.trim().isEmpty ? record.email : record.fullName;
    final ok = await _confirm(
      title: 'Rol Kaldırılsın mı?',
      message:
          '$who kişisinin "${record.roleLabel}" rolü kaldırılacak. Kişi dairesindeki yetkileriyle kalır.',
      confirmLabel: 'Kaldır',
      icon: Icons.person_remove_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busyRoles.add(record.userCode));
    try {
      await widget.authService.removeStaffRole(code, record.userCode);
      if (!mounted) return;
      AppSnack.show(context, 'Ek rol kaldırıldı.', kind: AppSnackKind.success);
      unawaited(_loadRoles(code));
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        _messageOf(e, 'Rol kaldırılamadı. Sunucuya bağlanılamadı.'),
        kind: AppSnackKind.error,
      );
    } finally {
      if (mounted) setState(() => _busyRoles.remove(record.userCode));
    }
  }

  // --- Görünüm -----------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final code = _siteCode;

    final Widget body;
    if (_loadingSites && _sites.isEmpty) {
      // İlk yükleme ve hata sonrası "Tekrar Dene": iskelet (boş durum / hata kutusu yanıp sönmez).
      body = const ListSkeleton(rows: 2);
    } else if (_sitesError != null && _sites.isEmpty) {
      body = InlineNotice(message: _sitesError!, onRetry: reload);
    } else if (_sites.isEmpty) {
      body = const EmptyCard(
        icon: Icons.apartment_rounded,
        title: 'Yönetilecek onaylı site bulunamadı.',
        message: 'Modülleri yönetmek için onaylanmış bir site gerekir.',
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_sitesError != null) ...[
            InlineNotice(message: _sitesError!, onRetry: reload),
            const SizedBox(height: AppSpace.md),
          ],
          _buildSiteSelector(context),
          const SizedBox(height: AppSpace.lg),
          ..._buildModulesSection(context, code!),
          const SizedBox(height: AppSpace.xl),
          ..._buildRolesSection(context, code),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Modüller', icon: Icons.extension_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Sitenizde kullanacağınız modülleri açıp kapatabilirsiniz. '
          'Kapalı bir modülün ekranları ve işlemleri o sitede çalışmaz.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        SectionHeader(
          title: 'Site',
          trailing: IconButton(
            onPressed: _loadingSites ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        body,
      ],
    );
  }

  Widget _buildSiteSelector(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final state = _state;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<int>(
            key: ValueKey<String>('modules_site_${_siteCode}_${_sites.length}'),
            isExpanded: true,
            initialValue: _siteCode,
            dropdownColor: p.surface,
            style: th.bodyMedium?.copyWith(color: p.text),
            decoration: const InputDecoration(
              labelText: 'Site Seçin',
              prefixIcon: Icon(Icons.apartment_rounded),
            ),
            items: [
              for (final site in _sites)
                DropdownMenuItem<int>(
                  value: site.id,
                  child: Text(
                    '${site.name} (${site.id})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) unawaited(_selectSite(value));
            },
          ),
          if (state != null) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                StatusChip(
                  label: state.managementTypeLabel,
                  tone: AppTone.info,
                  icon: Icons.category_rounded,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildModulesSection(BuildContext context, int siteCode) {
    final state = _state;
    return [
      const SectionHeader(title: 'Site Modülleri'),
      const SizedBox(height: AppSpace.md),
      if (_loadingState && state == null)
        const ListSkeleton(rows: 3)
      else ...[
        if (_stateError != null) ...[
          InlineNotice(
            message: _stateError!,
            onRetry: () => unawaited(_loadModules(siteCode)),
          ),
          if (state != null) const SizedBox(height: AppSpace.md),
        ],
        if (state != null)
          for (var i = 0; i < state.modules.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: StaggeredEntry(
                index: i,
                child: ModuleCard(
                  module: state.modules[i],
                  busy: _busyModules.contains(state.modules[i].code),
                  onToggle: _busyModules.contains(state.modules[i].code)
                      ? null
                      : (value) => unawaited(_toggle(state.modules[i], value)),
                ),
              ),
            ),
      ],
    ];
  }

  List<Widget> _buildRolesSection(BuildContext context, int siteCode) {
    final th = Theme.of(context).textTheme;
    final roles = _roles;
    return [
      SectionHeader(
        title: 'Ek Roller',
        trailing: TextButton.icon(
          onPressed: _addRole,
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('Rol Ekle'),
        ),
      ),
      const SizedBox(height: AppSpace.sm),
      Text(
        'Yönetim Kurulu / Denetçi ve Görevli rolleri isteğe bağlıdır. '
        'Atamazsanız bu rollerin işi site yöneticisinde kalır.',
        style: th.bodyMedium,
      ),
      const SizedBox(height: AppSpace.md),
      if (_loadingRoles && roles == null)
        const ListSkeleton(rows: 2)
      else ...[
        // Yükleme hatası HER durumda gösterilir (liste boşken "Ek rol atanmamış." diye gizlenmez).
        if (_rolesError != null) ...[
          InlineNotice(
            message: _rolesError!,
            onRetry: () => unawaited(_loadRoles(siteCode)),
          ),
          if (roles != null && roles.isNotEmpty) const SizedBox(height: AppSpace.md),
        ],
        if (roles != null && roles.isEmpty && _rolesError == null)
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
                busy: _busyRoles.contains(roles[i].userCode),
                onRemove: () => unawaited(_removeRole(roles[i])),
              ),
            ),
          ),
      ],
    ];
  }
}
