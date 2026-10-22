// "Dairem" ekranı (modül gerektirmez; daire sakini ve bireysel sakin): daire yönetimi kimde, malik / kiracı / aile, vekalet,
// bekleyen davet ve talepler, "Bu daireden ayrıl" ve gizli "Güvenlik ve destek" bölümü.
// Sözleşme: docs/PLATFORM_DAIRE_YONETIMI.md, docs/PLATFORM_DAIRE_GUVENLIK_POLITIKASI.md.
// Ana sayfa gövdesinde sınırsız yükseklik hatası vermesin diye liste yok: Column + kartlar (kaydırmayı üst sayfa yapar).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_management.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_mgmt_dialogs.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;

class MyApartmentView extends StatefulWidget {
  const MyApartmentView({super.key, required this.authService, this.service, this.onChanged});

  final AuthService authService;

  /// Testlerde sahte servis; verilmezse [AuthService] oturumundan kurulur.
  final ApartmentManagementService? service;

  /// Bağlar değişti (ayrılma, çıkış, kabul): çağıran modül / kapı verisini tazeleyebilir.
  final VoidCallback? onChanged;

  @override
  State<MyApartmentView> createState() => MyApartmentViewState();
}

class MyApartmentViewState extends State<MyApartmentView> {
  late final ApartmentManagementService _service =
      widget.service ?? ApartmentManagementService(authService: widget.authService);
  MyApartmentsData? _data;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> reload() async {
    final token = ++_token;
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final data = await _service.mine();
      if (!mounted || token != _token) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Daire bilgileri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  /// Bir işlemi çalıştırır: çift dokunuşu engeller, hatayı gösterir, başarıda yeniler.
  Future<bool> _run(Future<void> Function() action, {String? success, bool notifyParent = false}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return true;
      if (success != null) AppSnack.show(context, success, kind: AppSnackKind.success);
      if (notifyParent) widget.onChanged?.call();
      await reload();
      return true;
    } catch (e) {
      if (mounted) AppSnack.show(context, crmMessageOf(e, 'İşlem yapılamadı. Tekrar deneyin.'), kind: AppSnackKind.error);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ----------------------------------------------------------------- eylemler

  Future<void> _addTenant(MyApartment apt, bool canSearch) async {
    final input = await AddPersonDialog.show(
      context,
      service: _service,
      title: 'Kiracı ekle',
      tenantMode: true,
      canSearch: canSearch,
    );
    if (input == null) return;
    await _run(
      () => _service.addTenant(apt.apartmentId, input.toBody(tenant: true)),
      success: input.candidate != null ? 'Davet gönderildi. Kişi kabul edince kiracı olur.' : 'Kiracı eklendi.',
    );
  }

  Future<void> _addFamily(MyApartment apt, bool canSearch) async {
    final input = await AddPersonDialog.show(
      context,
      service: _service,
      title: 'Aile üyesi ekle',
      tenantMode: false,
      canSearch: canSearch,
    );
    if (input == null) return;
    await _run(
      () => _service.addFamily(apt.apartmentId, input.toBody()),
      success: input.candidate != null ? 'Davet gönderildi. Kişi kabul edince eklenir.' : 'Aile üyesi eklendi.',
    );
  }

  Future<void> _removeFamily(MyApartment apt, AptFamilyMember m) async {
    final consent = m.removalNeedsConsent;
    final ok = await confirmCrmAction(
      context,
      title: consent ? 'Çıkarma isteği gönder' : 'Aile üyesini çıkar',
      message: consent
          ? '${m.name} yetişkin bir üye olduğu için tek başınıza çıkaramazsınız. Kendisine onay isteği gider; onaylarsa bağı sona erer, onaylamazsa ya da 7 gün yanıtlamazsa hiçbir şey değişmez.'
          : '${m.name} daireden çıkarılacak ve kapı erişimi kapanacak.',
      confirmLabel: consent ? 'İstek gönder' : 'Çıkar',
    );
    if (!ok || !mounted) return;
    String mode = 'removed';
    await _run(() async => mode = await _service.removeFamily(apt.apartmentId, m.residencyId), notifyParent: true);
    if (mounted && mode == 'consent_requested') {
      AppSnack.show(context, 'Onay isteği gönderildi.', kind: AppSnackKind.info);
    }
  }

  Future<void> _delegate(MyApartment apt) async {
    final ok = await confirmCrmAction(
      context,
      title: 'Yönetimi kiracıya devret',
      message:
          'Daire yönetimi kiracıya geçer ve kiracı çıkana kadar sürer; tek başınıza geri alamazsınız (bağlantıyı kesme talebi ya da site yöneticisi gerekir). Siz dairede kalırsınız.',
      confirmLabel: 'Devret',
    );
    if (!ok || !mounted) return;
    await _run(() => _service.delegateManagement(apt.apartmentId), success: 'Yönetim kiracıya devredildi.');
  }

  Future<void> _exit(MyApartment apt) async {
    ExitPreview? preview;
    try {
      preview = await _service.exitPreview(apt.apartmentId);
    } catch (e) {
      if (mounted) AppSnack.show(context, crmMessageOf(e, 'Çıkış özeti alınamadı.'), kind: AppSnackKind.error);
      return;
    }
    if (!mounted) return;
    final debt = preview.hasDebt
        ? '\n\nUyarı: Hesabınızda ${preview.debtText} açık borç var. Çıkışı engellemez; borç sizin hesabınızda kalır.'
        : '';
    final family = preview.familyCount > 0 ? '\nEklediğiniz ${preview.familyCount} aile üyesinin bağı da sona erer.' : '';
    final ok = await confirmCrmAction(
      context,
      title: 'Daireyi devret / çıkış',
      message: 'Bu dairedeki kiracılığınız sona erer, daire yönetimi malike döner. Hesabınız silinmez.$family$debt',
      confirmLabel: 'Çıkış yap',
      tone: AppTone.danger,
    );
    if (!ok || !mounted) return;
    await _run(() => _service.exitTenancy(apt.apartmentId), success: 'Daireden çıkış yapıldı.', notifyParent: true);
  }

  Future<void> _disconnect(MyApartment apt) async {
    final ok = await confirmCrmAction(
      context,
      title: 'Bağlantıyı kes talebi',
      message: 'Karşı tarafa bir talep gider. Onaylarsa kiracılık sona erer ve yönetim malike döner; reddederse ya da 14 gün yanıtlamazsa talep kapanır (otomatik kesme yok).',
      confirmLabel: 'Talep gönder',
    );
    if (!ok || !mounted) return;
    await _run(() => _service.requestDisconnect(apt.apartmentId), success: 'Talep gönderildi.');
  }

  Future<void> _leave(MyApartment apt) async {
    final ok = await confirmCrmAction(
      context,
      title: 'Bu daireden ayrıl',
      message:
          'Bu dairedeki bağınız ve kapı erişiminiz sona erer. Onay gerekmez. Diğer üyelere bildirim gitmez. Hesabınız silinmez; sonra yeniden katılmak isterseniz davet gerekir.',
      confirmLabel: 'Ayrıl',
      tone: AppTone.danger,
    );
    if (!ok || !mounted) return;
    await _run(() => _service.leave(apt.apartmentId), success: 'Daireden ayrıldınız.', notifyParent: true);
  }

  Future<void> _giveProxy(MyApartment apt) async {
    final result = await ProxyDialog.show(context, tenantName: apt.tenant?.name ?? 'kiracı');
    if (result == null) return;
    await _run(
      () => _service.createProxy(apt.apartmentId, scope: result.scope, validFrom: result.validFrom, validUntil: result.validUntil),
      success: 'Vekalet verildi.',
    );
  }

  Future<void> _revokeProxy(MyApartment apt, AptProxy p, {required bool asOwner}) async {
    final ok = await confirmCrmAction(
      context,
      title: asOwner ? 'Vekaleti iptal et' : 'Vekaletten çekil',
      message: asOwner ? '${p.scopeLabel} vekaleti iptal edilecek.' : '${p.scopeLabel} vekaleti sona erecek; imza hakkı malike döner.',
      confirmLabel: asOwner ? 'İptal et' : 'Çekil',
    );
    if (!ok || !mounted) return;
    await _run(() => _service.revokeProxy(apt.apartmentId, p.id), success: 'Vekalet kaldırıldı.');
  }

  Future<void> _answer(IncomingAptRequest r, bool accept) async {
    final okDone = await _run(
      () => _service.respond(r.id, accept: accept),
      success: accept ? 'Kabul ettiniz.' : 'Reddettiniz.',
      notifyParent: accept,
    );
    if (okDone && accept) widget.onChanged?.call();
  }

  Future<void> _safety(MyApartment apt) async {
    final input = await SafetyRequestDialog.show(context);
    if (input == null) return;
    await _run(
      () => _service.sendSafetyRequest(apt.apartmentId, message: input.message, contactPref: input.contactPref),
      success: 'Talebiniz site yönetimine iletildi. Başka kimseye bildirim gitmedi.',
    );
  }

  // ----------------------------------------------------------------- görünüm

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: context.palette.textSecondary);
    if (_loading) {
      return Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text('Daire bilgileri yükleniyor...', style: secondary));
    }
    if (_error != null && _data == null) return InlineNotice(message: _error!, onRetry: reload);
    final data = _data ?? const MyApartmentsData();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[InlineNotice(message: _error!, onRetry: reload), const SizedBox(height: AppSpace.md)],
        for (final n in data.notices) _noticeCard(n),
        for (final r in data.incoming) _incomingCard(r),
        if (data.apartments.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Text('Henüz bağlı olduğunuz bir daire yok. "Daireye Katıl" ekranından başvurabilirsiniz.', style: secondary),
          ),
        for (final apt in data.apartments) _apartmentCard(apt, data.canSearch),
      ],
    );
  }

  Widget _noticeCard(AptNotice n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        key: ValueKey<String>('apt_notice_${n.id}'),
        child: Row(
          children: [
            const Icon(Icons.notifications_active_outlined),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text(n.message)),
            TextButton(
              onPressed: _busy ? null : () => unawaited(_run(() => _service.markNoticesRead(<int>[n.id]))),
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _incomingCard(IncomingAptRequest r) {
    final th = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        key: ValueKey<String>('apt_incoming_${r.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(r.title, style: th.titleMedium),
            const SizedBox(height: AppSpace.xs),
            Text(r.explanation, style: th.bodyMedium?.copyWith(color: context.palette.textSecondary)),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                FilledButton(onPressed: _busy ? null : () => unawaited(_answer(r, true)), child: const Text('Kabul et')),
                OutlinedButton(onPressed: _busy ? null : () => unawaited(_answer(r, false)), child: const Text('Reddet')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _apartmentCard(MyApartment apt, bool canSearch) {
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: context.palette.textSecondary);
    final adminText = (apt.adminName ?? '').isEmpty
        ? 'Daire yönetimi: henüz belirlenmemiş'
        : 'Daire yönetimi: ${apt.adminName}${apt.adminSideLabel.isEmpty ? '' : ' (${apt.adminSideLabel})'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: AppCard(
        key: ValueKey<String>('apt_card_${apt.apartmentId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(apt.label, style: th.titleLarge),
            if (apt.siteName.isNotEmpty) Text(apt.siteName, style: secondary),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                StatusChip(label: apt.roleLabel, tone: AppTone.primary),
                if (apt.isAdmin) const StatusChip(label: 'Daire yöneticisi', tone: AppTone.success),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Text(adminText, style: th.titleSmall),
            if (apt.delegated) Text('Yönetim kiracıdadır ve kiracı çıkana kadar sürer.', style: secondary),
            if (apt.delegationPending)
              Text('Kiracı uygulamaya katılınca yönetim ona geçecek.', style: secondary),
            const SizedBox(height: AppSpace.sm),
            _personLine('Malik', apt.owner?.name),
            _personLine('Kiracı', apt.tenant?.name),
            if (apt.can.manageProxy || apt.myRole == 'tenant' || apt.isAdmin)
              _personLine(
                'Toplantı imza hakkı',
                apt.signingKind == 'proxy' ? 'Vekil: ${apt.signingName ?? ''}' : (apt.signingName == null ? null : 'Malik: ${apt.signingName}'),
              ),
            if (apt.myRole == 'family_member')
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Text('Aile üyesi olarak yalnızca görüntüleyebilirsiniz. Daire yönetimi daire yöneticisindedir.', style: secondary),
              ),
            ..._ownerSection(apt, canSearch),
            ..._requestsSection(apt),
            ..._proxySection(apt),
            ..._familySection(apt, canSearch),
            ..._tenantSection(apt),
            const SizedBox(height: AppSpace.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => unawaited(_leave(apt)),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Bu daireden ayrıl'),
              ),
            ),
            _safetySection(apt),
          ],
        ),
      ),
    );
  }

  Widget _personLine(String label, String? value) {
    final th = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: th.bodyMedium?.copyWith(color: context.palette.textSecondary))),
          Expanded(child: Text(value == null || value.isEmpty ? 'Kayıtlı değil' : value, style: th.bodyMedium)),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Text(title, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: AppSpace.sm), ...children],
      ),
    );
  }

  List<Widget> _ownerSection(MyApartment apt, bool canSearch) {
    if (!apt.can.addTenant && !apt.can.delegateManagement) return const <Widget>[];
    return [
      _section('Kiracı', [
        if (apt.can.addTenant)
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_addTenant(apt, canSearch && apt.can.searchPeople)),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Kiracı ekle'),
          ),
        if (apt.can.delegateManagement)
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_delegate(apt)),
            icon: const Icon(Icons.swap_horiz_rounded),
            label: const Text('Yönetimi kiracıya devret'),
          ),
      ]),
    ];
  }

  List<Widget> _requestsSection(MyApartment apt) {
    final list = apt.requests.where((r) => r.direction == 'outgoing').toList();
    if (list.isEmpty) return const <Widget>[];
    final th = Theme.of(context).textTheme;
    return [
      _section('Yanıt bekleyen talepler', [
        for (final r in list)
          Row(
            children: [
              Expanded(child: Text('${r.kindLabel}${r.targetName == null ? '' : ' - ${r.targetName}'}', style: th.bodyMedium)),
              TextButton(
                onPressed: _busy ? null : () => unawaited(_run(() => _service.cancelRequest(r.id), success: 'Talep geri çekildi.')),
                child: const Text('Geri çek'),
              ),
            ],
          ),
      ]),
    ];
  }

  List<Widget> _proxySection(MyApartment apt) {
    final holdsProxy = apt.myRole == 'tenant';
    if (!apt.can.manageProxy && !(holdsProxy && apt.proxies.isNotEmpty)) return const <Widget>[];
    final th = Theme.of(context).textTheme;
    final visible = apt.proxies.where((p) => !p.revoked).toList();
    return [
      _section('Vekalet', [
        if (visible.isEmpty) Text('Vekalet yok; toplantıda imza hakkı maliktedir.', style: th.bodyMedium),
        for (final p in visible)
          Row(
            children: [
              Expanded(
                child: Text('${p.scopeLabel}: ${p.proxyName ?? ''}\n${p.validFrom} - ${p.validUntil}${p.active ? '' : ' (geçerli değil)'}', style: th.bodyMedium),
              ),
              TextButton(
                onPressed: _busy ? null : () => unawaited(_revokeProxy(apt, p, asOwner: apt.can.manageProxy)),
                child: Text(apt.can.manageProxy ? 'İptal et' : 'Çekil'),
              ),
            ],
          ),
        if (apt.can.manageProxy)
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_giveProxy(apt)),
            icon: const Icon(Icons.assignment_ind_rounded),
            label: const Text('Vekalet ver'),
          ),
      ]),
    ];
  }

  List<Widget> _familySection(MyApartment apt, bool canSearch) {
    if (!apt.can.manageFamily && apt.family.isEmpty) return const <Widget>[];
    final th = Theme.of(context).textTheme;
    return [
      _section('Aile üyeleri', [
        if (apt.family.isEmpty) Text('Kayıtlı aile üyesi yok.', style: th.bodyMedium),
        for (final m in apt.family)
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpace.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(m.name, style: th.bodyMedium),
                    if (m.isMinor) const StatusChip(label: '18 yaş altı', tone: AppTone.info),
                  ],
                ),
              ),
              if (m.canRemove)
                TextButton(
                  onPressed: _busy ? null : () => unawaited(_removeFamily(apt, m)),
                  child: Text(m.removalNeedsConsent ? 'Çıkarma isteği' : 'Çıkar'),
                ),
            ],
          ),
        if (apt.can.manageFamily)
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_addFamily(apt, canSearch && apt.can.searchPeople)),
            icon: const Icon(Icons.group_add_rounded),
            label: const Text('Aile üyesi ekle'),
          ),
      ]),
    ];
  }

  List<Widget> _tenantSection(MyApartment apt) {
    if (!apt.can.exit && !apt.can.requestDisconnect) return const <Widget>[];
    return [
      _section('Kiracılık', [
        if (apt.can.exit)
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_exit(apt)),
            icon: const Icon(Icons.exit_to_app_rounded),
            label: const Text('Daireyi devret / Çıkış'),
          ),
        if (apt.can.requestDisconnect)
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_disconnect(apt)),
            icon: const Icon(Icons.link_off_rounded),
            label: const Text('Bağlantıyı kes talebi'),
          ),
      ]),
    ];
  }

  /// Gizli "Güvenlik ve destek": varsayılan kapalı, sade başlık. Yardım hatları + site yönetimine gizli talep.
  Widget _safetySection(MyApartment apt) {
    final th = Theme.of(context).textTheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey<String>('apt_safety_${apt.apartmentId}'),
        tilePadding: EdgeInsets.zero,
        title: const Text('Güvenlik ve destek'),
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Acil tehlikede 112\'yi arayın.', style: th.titleSmall),
          const SizedBox(height: AppSpace.sm),
          const _HelplineLine(name: '112 Acil Çağrı Merkezi', detail: 'Acil tehlike durumunda'),
          const _HelplineLine(name: 'ALO 183 Sosyal Destek Hattı', detail: 'Ücretsiz, 7 gün 24 saat destek ve yönlendirme'),
          const _HelplineLine(name: 'KADES uygulaması', detail: 'Emniyetin Kadın Acil Destek uygulaması'),
          const _HelplineLine(name: 'ŞÖNİM', detail: 'Şiddet Önleme ve İzleme Merkezi: danışmanlık ve barınma desteği'),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Bu uygulama polisin ya da mahkemenin yerine geçmez. Uzaklaştırma ya da koruma kararınız varsa belgeyi site yönetimine bildirin.',
            style: th.bodySmall?.copyWith(color: context.palette.textSecondary),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_safety(apt)),
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Site yönetimine gizli talep gönder'),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
      ),
    );
  }
}

class _HelplineLine extends StatelessWidget {
  const _HelplineLine({required this.name, required this.detail});

  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: name, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            TextSpan(text: ' - $detail', style: th.bodyMedium),
          ],
        ),
      ),
    );
  }
}
