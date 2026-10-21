import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/module_request.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/module_request_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/module_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/module_request_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/platform_rules_entry_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/staff_roles_section.dart';

/// Geçiş Kontrol kapatılırken gösterilen uyarı (sunucunun `MODULE_CONFIRM_REQUIRED` metniyle aynı).
const String doorControlOffWarning =
    'Geçiş Kontrol kapatılırsa telefondan kapı açma, QR ve misafir geçişi durur. Onaylıyor musunuz?';

/// "Modüller" ekranı (Platform modül sistemi Faz 1): site seçici, modül kartları (anahtar), Geçiş
/// Kontrol kapatılırken onay penceresi ve "Ek roller" bölümü (listele / ekle / kaldır).
///
/// Faz 1.1: ANAHTAR yalnız süper kullanıcıdadır. Site yöneticisi modülü kendi açıp kapatmaz; kartlarda
/// durum çipi ("Tanımlı" / "Tanımlı değil" / "Talep gönderildi"), "Modül Talep Et" (not alanlı pencere)
/// ve "Talebi Geri Çek" vardır; altında "Modül Taleplerim" listesi gösterilir.
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

  // Ek roller bölümü kendi verisini çeker; sayfa yenilemesinde bu anahtarla tazelenir.
  final GlobalKey<StaffRolesSectionState> _rolesKey = GlobalKey<StaffRolesSectionState>();

  // Site yöneticisinin modül talepleri (süper kullanıcıda yüklenmez).
  List<ModuleRequest>? _requests;
  bool _loadingRequests = false;
  String? _requestsError;

  final Set<String> _busyModules = <String>{};

  // Yarış koruması: yalnız en son başlatılan istek sonucu uygulanır.
  int _sitesToken = 0;
  int _modulesToken = 0;
  int _requestsToken = 0;

  /// Anahtar yalnız süper kullanıcıdadır; site yöneticisi talep eder (Faz 1.1).
  bool get _isSuper => widget.authService.session?.role == UserRole.superUser;

  /// Son gösterilen en çok bu kadar talep listelenir.
  static const int _maxListedRequests = 10;

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
          _requests = null;
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
      _requests = null;
      _stateError = null;
      _requestsError = null;
    });
    await _loadSiteData(siteCode);
  }

  /// Seçili sitenin modül durumunu ve/veya ek rollerini çeker. [silent] true iken yükleme göstergesi
  /// açılmaz (işlem sonrası arka planda tazeleme).
  Future<void> _loadSiteData(
    int siteCode, {
    bool modules = true,
    bool roles = true,
    bool requests = true,
    bool silent = false,
  }) async {
    await Future.wait(<Future<void>>[
      if (modules) _loadModules(siteCode, silent: silent),
      // Ek roller bölümü kendi verisini çeker; aynı siteyi gösteriyorsa yeniden okutulur (site değişiminde bölüm
      // kendi `didUpdateWidget`ında yükler: eski siteye boşuna istek atılmaz).
      if (roles && _rolesKey.currentState?.widget.siteCode == siteCode)
        _rolesKey.currentState!.reload(silent: silent),
      if (requests && !_isSuper) _loadRequests(siteCode, silent: silent),
    ]);
  }

  Future<void> _loadRequests(int siteCode, {bool silent = false}) async {
    if (!mounted || _siteCode != siteCode) return;
    final token = ++_requestsToken;
    if (!silent) {
      setState(() {
        _loadingRequests = true;
        _requestsError = null;
      });
    }
    try {
      final next = await widget.authService.listModuleRequests(siteCode);
      if (!mounted || token != _requestsToken || _siteCode != siteCode) return;
      setState(() {
        _requests = next;
        _loadingRequests = false;
        _requestsError = null;
      });
    } catch (e) {
      if (!mounted || token != _requestsToken || _siteCode != siteCode) return;
      setState(() {
        _loadingRequests = false;
        if (!silent) {
          _requestsError = _messageOf(
            e,
            'Modül talepleri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          );
        }
      });
    }
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

  // --- Modül talebi (site yöneticisi) -------------------------------------------------------

  Future<void> _requestModule(PlatformModule module) async {
    final code = _siteCode;
    if (code == null || _busyModules.contains(module.code)) return;
    final site = _sites.where((s) => s.id == code).firstOrNull;
    final sent = await ModuleRequestDialog.show(
      context,
      authService: widget.authService,
      siteCode: code,
      moduleCode: module.code,
      moduleName: module.name,
      siteName: site?.name,
    );
    if (!mounted) return;
    if (sent == true) {
      AppSnack.show(context, 'Modül talebiniz gönderildi.', kind: AppSnackKind.success);
    }
    // Gönderilse de reddedilse de (örn. aynı anda başkası talep etmiş) durum sunucudan okunur.
    if (_siteCode == code) {
      unawaited(_loadSiteData(code, roles: false, silent: true));
    }
  }

  Future<void> _cancelRequest(PlatformModule module) async {
    final code = _siteCode;
    if (code == null || _busyModules.contains(module.code)) return;
    final ok = await _confirm(
      title: 'Talep Geri Çekilsin mi?',
      message: '"${module.name}" modülü için gönderdiğiniz talep geri çekilecek.',
      confirmLabel: 'Geri Çek',
      icon: Icons.undo_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busyModules.add(module.code));
    try {
      var pending = _pendingRequestFor(module.code);
      if (pending == null) {
        // Liste henüz yüklenmediyse ya da bayatsa sunucudan okunur.
        final fresh = await widget.authService.listModuleRequests(code);
        if (!mounted) return;
        if (_siteCode == code) setState(() => _requests = fresh);
        pending = _pendingRequestFor(module.code);
      }
      if (pending == null) {
        AppSnack.show(context, 'Talep bulunamadı.', kind: AppSnackKind.error);
      } else {
        await widget.authService.cancelModuleRequest(code, pending.id);
        if (!mounted) return;
        AppSnack.show(context, 'Talep geri çekildi.', kind: AppSnackKind.success);
      }
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        _messageOf(e, 'Talep geri çekilemedi. Sunucuya bağlanılamadı.'),
        kind: AppSnackKind.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busyModules.remove(module.code));
        // Sonuç ne olursa olsun (örn. 409 REQUEST_NOT_PENDING) durum yeniden okunur.
        if (_siteCode == code) {
          unawaited(_loadSiteData(code, roles: false, silent: true));
        }
      }
    }
  }

  ModuleRequest? _pendingRequestFor(String moduleCode) {
    for (final r in _requests ?? const <ModuleRequest>[]) {
      if (r.isPending && r.moduleCode == moduleCode) return r;
    }
    return null;
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
          if (!_isSuper) ...[
            const SizedBox(height: AppSpace.xl),
            ..._buildRequestsSection(context, code),
          ],
          const SizedBox(height: AppSpace.xl),
          StaffRolesSection(
            key: _rolesKey,
            authService: widget.authService,
            siteCode: code,
            siteName: _sites.where((s) => s.id == code).firstOrNull?.name,
          ),
          // Kurallar tablosu (G11): seçili sitede geçerli kurallar; yönetici salt okunur, süper kullanıcı siteye özel değer verir.
          const SizedBox(height: AppSpace.xl),
          PlatformRulesEntryCard(
            authService: widget.authService,
            canEdit: _isSuper,
            siteCode: code,
            siteName: _sites.where((s) => s.id == code).firstOrNull?.name,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Modüller', icon: Icons.extension_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          _isSuper
              ? 'Sitenizde kullanacağınız modülleri açıp kapatabilirsiniz. '
                  'Kapalı bir modülün ekranları ve işlemleri o sitede çalışmaz.'
              : 'Sitenizde tanımlı modüller aşağıda görünür. Tanımlı olmayan bir modülü kullanmak '
                  'için talep gönderebilirsiniz; talebiniz sistem yöneticisine iletilir.',
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
                  requestMode: !_isSuper,
                  onToggle: _busyModules.contains(state.modules[i].code)
                      ? null
                      : (value) => unawaited(_toggle(state.modules[i], value)),
                  onRequest: () => unawaited(_requestModule(state.modules[i])),
                  onCancelRequest: () => unawaited(_cancelRequest(state.modules[i])),
                ),
              ),
            ),
      ],
    ];
  }

  /// "Modül Taleplerim" (site yöneticisi): son talepler, durumları ve kararın gerekçesi.
  List<Widget> _buildRequestsSection(BuildContext context, int siteCode) {
    final requests = _requests;
    final shown = (requests ?? const <ModuleRequest>[])
        .take(_maxListedRequests)
        .toList(growable: false);
    return [
      const SectionHeader(title: 'Modül Taleplerim'),
      const SizedBox(height: AppSpace.md),
      if (_loadingRequests && requests == null)
        const ListSkeleton(rows: 2)
      else ...[
        if (_requestsError != null) ...[
          InlineNotice(
            message: _requestsError!,
            onRetry: () => unawaited(_loadRequests(siteCode)),
          ),
          if (shown.isNotEmpty) const SizedBox(height: AppSpace.md),
        ],
        if (requests != null && requests.isEmpty && _requestsError == null)
          const EmptyCard(
            icon: Icons.inbox_rounded,
            title: 'Henüz modül talebiniz yok.',
            message: 'Tanımlı olmayan bir modül için "Modül Talep Et" düğmesini kullanın.',
          ),
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: StaggeredEntry(
              index: i,
              child: ModuleRequestCard(request: shown[i]),
            ),
          ),
      ],
    ];
  }
}
