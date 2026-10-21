import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/management_company_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Biçim yardımcıları (testler için açık).
String companyMoney(num minor) {
  final negative = minor < 0;
  final abs = minor.abs().round();
  final lira = (abs ~/ 100).toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  final kurus = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$lira,$kurus TL';
}

/// Baz puan -> "%87,5"; null -> "Henüz borç yok".
String companyRate(int? bp) {
  if (bp == null) return 'Borçlandırma yok';
  final whole = bp ~/ 100;
  final frac = bp % 100;
  return frac == 0 ? '%$whole' : '%$whole,${frac.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '')}';
}

/// Yönetim firması sayfası (Y1/Y2): firma sahibine "Tüm siteler" tablosu (en düşük tahsilat oranı üstte), personel, aylık pay dökümü
/// (bilgi amaçlı); süper kullanıcıya firma kaydı, ortaklık payı, site bağlama ve deneme süresi ayarı.
class ManagementCompanyScreen extends StatefulWidget {
  const ManagementCompanyScreen({super.key, required this.authService, this.service});

  final AuthService authService;
  final ManagementCompanyService? service;

  static Future<void> open(BuildContext context, {required AuthService authService}) =>
      Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => ManagementCompanyScreen(authService: authService)));

  @override
  State<ManagementCompanyScreen> createState() => _ManagementCompanyScreenState();
}

class _ManagementCompanyScreenState extends State<ManagementCompanyScreen> {
  late final ManagementCompanyService _service = widget.service ?? ManagementCompanyService(authService: widget.authService);
  bool get _isSuper => widget.authService.session?.role.apiValue == 'super_user';

  List<Map<String, dynamic>> _companies = const [];
  int? _trialDays;
  bool _loading = true;
  String? _error;

  int? _selectedId;
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _table = const [];
  Map<String, dynamic>? _share;
  late String _month = _currentMonth();
  bool _detailLoading = false;

  static String _currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadList());
  }

  String _msg(Object e) => e is ApiException ? e.message : 'Beklenmeyen bir hata oluştu.';

  Future<void> _loadList() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.companies();
      final days = _isSuper ? await _service.trialDays() : null;
      if (!mounted) return;
      setState(() {
        _companies = list;
        _trialDays = days;
        _loading = false;
      });
      if (!_isSuper && list.length == 1 && _selectedId == null) unawaited(_openCompany(list.first['id'] as int));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(e);
        _loading = false;
      });
    }
  }

  Future<void> _openCompany(int id) async {
    setState(() {
      _selectedId = id;
      _detailLoading = true;
      _error = null;
    });
    try {
      final detail = await _service.company(id);
      final role = (detail['company'] as Map<String, dynamic>)['my_role'];
      var table = const <Map<String, dynamic>>[];
      Map<String, dynamic>? share;
      if (role != 'staff') {
        table = await _service.sitesTable(id);
        share = await _service.shareStatement(id, _month);
      }
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _table = table;
        _share = share;
        _detailLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(e);
        _detailLoading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, {String? ok}) async {
    try {
      await action();
      if (!mounted) return;
      if (ok != null) AppSnack.show(context, ok, kind: AppSnackKind.success);
      if (_selectedId != null) {
        await _openCompany(_selectedId!);
      } else {
        await _loadList();
      }
    } catch (e) {
      if (mounted) AppSnack.show(context, _msg(e), kind: AppSnackKind.error);
    }
  }

  Future<List<String>?> _ask(String title, List<String> labels, {List<String>? initial}) {
    final controllers = [for (var i = 0; i < labels.length; i++) TextEditingController(text: initial?[i] ?? '')];
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < labels.length; i++)
              TextField(controller: controllers[i], decoration: InputDecoration(labelText: labels[i])),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, [for (final c in controllers) c.text.trim()]), child: const Text('Kaydet')),
        ],
      ),
    );
  }

  /// "12,5" ya da "12.5" (yüzde) -> baz puan; geçersizse null.
  int? _percentToBp(String text) {
    final v = double.tryParse(text.replaceAll(',', '.'));
    if (v == null || v < 0 || v > 100) return null;
    return (v * 100).round();
  }

  /// "1500" / "1500,50" (TL) -> kuruş; boş -> null (bedel yok); geçersizse -1.
  int? _tlToMinor(String text) {
    if (text.isEmpty) return null;
    final v = double.tryParse(text.replaceAll('.', '').replaceAll(',', '.'));
    if (v == null || v < 0) return -1;
    return (v * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final Widget body;
    if (_loading || _detailLoading) {
      body = const Center(child: Padding(padding: EdgeInsets.all(AppSpace.xl), child: CircularProgressIndicator()));
    } else if (_error != null) {
      body = InlineNotice(message: _error!, onRetry: _selectedId == null ? _loadList : () => _openCompany(_selectedId!));
    } else if (_selectedId != null && _detail != null) {
      body = _detailBody(th);
    } else {
      body = _listBody(th);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedId == null ? 'Yönetim Firması' : 'Firma'),
        leading: _selectedId != null && (_isSuper || _companies.length > 1)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() {
                  _selectedId = null;
                  _detail = null;
                  _error = null;
                }),
              )
            : null,
      ),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpace.lg), children: [body])),
    );
  }

  Widget _listBody(TextTheme th) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_isSuper) ...[
        AppCard(
          key: const ValueKey<String>('company_trial_card'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Deneme süresi', style: th.titleMedium),
            const SizedBox(height: AppSpace.sm),
            Text('Yeni açılan sitelere ${_trialDays ?? 60} gün deneme tanınır (0 = deneme yok). Mevcut sitelere dokunulmaz.', style: th.bodyMedium),
            const SizedBox(height: AppSpace.sm),
            OutlinedButton(
              key: const ValueKey<String>('company_trial_edit'),
              onPressed: () async {
                final r = await _ask('Deneme süresi (gün)', ['Gün (0-365)'], initial: ['${_trialDays ?? 60}']);
                final days = int.tryParse(r?.first ?? '');
                if (r == null) return;
                if (days == null || days < 0 || days > 365) {
                  if (mounted) AppSnack.show(context, 'Gün 0-365 arasında olmalı.', kind: AppSnackKind.error);
                  return;
                }
                await _run(() => _service.setTrialDays(days), ok: 'Deneme süresi kaydedildi.');
              },
              child: const Text('Süreyi Değiştir'),
            ),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
        FilledButton.icon(
          key: const ValueKey<String>('company_create'),
          icon: const Icon(Icons.add_business_rounded),
          label: const Text('Yeni Yönetim Firması'),
          onPressed: () async {
            final r = await _ask('Yeni yönetim firması', ['Firma adı', 'Sahibin e-postası (kayıtlı kullanıcı)', 'Ortaklık payı (%)'], initial: ['', '', '0']);
            if (r == null) return;
            final bp = _percentToBp(r[2]);
            if (bp == null) {
              if (mounted) AppSnack.show(context, 'Ortaklık payı 0-100 arasında olmalı.', kind: AppSnackKind.error);
              return;
            }
            await _run(() => _service.createCompany(name: r[0], ownerEmail: r[1], shareBp: bp), ok: 'Firma oluşturuldu.');
          },
        ),
        const SizedBox(height: AppSpace.md),
      ],
      if (_companies.isEmpty)
        Text(_isSuper ? 'Henüz yönetim firması yok.' : 'Bir yönetim firmasına bağlı değilsiniz.', style: th.bodyMedium),
      for (final c in _companies)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppCard(
            child: ListTile(
              key: ValueKey<String>('company_${c['id']}'),
              contentPadding: EdgeInsets.zero,
              title: Text('${c['name']}'),
              subtitle: Text(c['is_active'] == false ? 'Pasif' : 'Ortaklık payı ${companyRate(c['partner_share_bp'] as int?)}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openCompany(c['id'] as int),
            ),
          ),
        ),
    ]);
  }

  Widget _detailBody(TextTheme th) {
    final detail = _detail!;
    final company = detail['company'] as Map<String, dynamic>;
    final id = company['id'] as int;
    final role = company['my_role'] as String;
    final canSeeAll = role != 'staff';
    final members = (detail['members'] as List<dynamic>).whereType<Map<String, dynamic>>().toList();
    final sites = (detail['sites'] as List<dynamic>).whereType<Map<String, dynamic>>().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${company['name']}', style: th.headlineSmall),
      const SizedBox(height: AppSpace.xs),
      if (canSeeAll) Text('Ortaklık payı: ${companyRate(company['partner_share_bp'] as int?)}', style: th.bodyMedium),
      const SizedBox(height: AppSpace.lg),
      Text('Tüm siteler', style: th.titleLarge),
      const SizedBox(height: AppSpace.xs),
      if (!canSeeAll)
        Text('Tüm siteler tablosunu yalnızca firma sahibi görür.', style: th.bodyMedium)
      else if (_table.isEmpty)
        Text('Firmaya bağlı site yok.', style: th.bodyMedium)
      else ...[
        Text('En düşük tahsilat oranı en üstte. Oran bu ayın tahsilatının bu ayın borçlandırmasına bölümüdür.', style: th.bodySmall),
        const SizedBox(height: AppSpace.sm),
        for (final s in _table) _siteCard(th, s),
      ],
      if (canSeeAll) ...[
        const SizedBox(height: AppSpace.lg),
        _shareSection(th, id),
      ],
      const SizedBox(height: AppSpace.lg),
      _membersSection(th, id, role, members),
      if (_isSuper) ...[const SizedBox(height: AppSpace.lg), _adminSection(th, id, company, sites)],
    ]);
  }

  Widget _siteCard(TextTheme th, Map<String, dynamic> s) {
    final trialEnd = s['trial_ends_at'] as String?;
    Widget stat(String label, String value) => Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: th.titleSmall),
        Text(label, style: th.bodySmall),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        key: ValueKey<String>('company_site_${s['site_code']}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s['name']}', style: th.titleMedium),
          if (s['subscription_status'] == 'trial' && trialEnd != null) Text('Deneme bitişi: ${trialEnd.substring(0, 10)}', style: th.bodySmall),
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            stat('Daire', '${s['apartment_count']}'),
            stat('Bu ay tahsilat', companyRate(s['collection_rate_bp'] as int?)),
          ]),
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            stat('Açık borç', companyMoney(s['open_debt_minor'] as num)),
            stat('Borçlu daire', '${s['debtor_count']}'),
          ]),
        ]),
      ),
    );
  }

  Widget _shareSection(TextTheme th, int id) {
    final share = _share;
    final rows = (share?['sites'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    return AppCard(
      key: const ValueKey<String>('company_share_card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Aylık ortaklık payı', style: th.titleMedium),
        Text('Yalnızca bilgi amaçlıdır; fatura ya da ödeme oluşturmaz.', style: th.bodySmall),
        const SizedBox(height: AppSpace.sm),
        Row(children: [
          IconButton(tooltip: 'Önceki ay', icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _shiftMonth(id, -1)),
          Expanded(child: Center(child: Text(_month, style: th.titleSmall))),
          IconButton(tooltip: 'Sonraki ay', icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _shiftMonth(id, 1)),
        ]),
        for (final r in rows)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${r['name']}'),
            subtitle: Text(r['monthly_fee_minor'] == null
                ? 'Aylık bedel girilmemiş'
                : (r['in_trial'] == true ? 'Deneme süresinde: pay yok' : 'Bedel ${companyMoney(r['monthly_fee_minor'] as num)}')),
            trailing: Text(companyMoney((r['share_minor'] as num?) ?? 0)),
          ),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Toplam pay', style: th.titleSmall),
          Text(companyMoney((share?['total_share_minor'] as num?) ?? 0), style: th.titleSmall),
        ]),
      ]),
    );
  }

  void _shiftMonth(int id, int delta) {
    final parts = _month.split('-');
    final d = DateTime(int.parse(parts[0]), int.parse(parts[1]) + delta);
    _month = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    unawaited(_openCompany(id));
  }

  Widget _membersSection(TextTheme th, int id, String role, List<Map<String, dynamic>> members) {
    final canEdit = role != 'staff';
    return AppCard(
      key: const ValueKey<String>('company_members_card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Personel', style: th.titleMedium),
        for (final m in members)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${m['full_name']}'),
            subtitle: Text('${m['email']} · ${m['role'] == 'owner' ? 'Sahip' : 'Personel'}'),
            trailing: canEdit && (m['role'] != 'owner' || _isSuper)
                ? IconButton(
                    tooltip: 'Çıkar',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () => _run(() => _service.removeMember(id, m['user_code'] as int), ok: 'Üye çıkarıldı.'),
                  )
                : null,
          ),
        if (canEdit)
          OutlinedButton.icon(
            key: const ValueKey<String>('company_add_member'),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Personel Ekle'),
            onPressed: () async {
              final r = await _ask('Personel ekle', ['Kayıtlı e-posta adresi']);
              if (r == null || r.first.isEmpty) return;
              await _run(() => _service.addMember(id, r.first), ok: 'Personel eklendi.');
            },
          ),
      ]),
    );
  }

  Widget _adminSection(TextTheme th, int id, Map<String, dynamic> company, List<Map<String, dynamic>> sites) {
    return AppCard(
      key: const ValueKey<String>('company_admin_card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Firma yönetimi (süper kullanıcı)', style: th.titleMedium),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton(
          key: const ValueKey<String>('company_share_edit'),
          onPressed: () async {
            final r = await _ask('Ortaklık payı', ['Pay (%)'], initial: ['${(company['partner_share_bp'] as int) / 100}']);
            if (r == null) return;
            final bp = _percentToBp(r.first);
            if (bp == null) {
              if (mounted) AppSnack.show(context, 'Pay 0-100 arasında olmalı.', kind: AppSnackKind.error);
              return;
            }
            await _run(() => _service.updateCompany(id, {'partner_share_bp': bp}), ok: 'Ortaklık payı kaydedildi.');
          },
          child: const Text('Ortaklık Payını Değiştir'),
        ),
        const SizedBox(height: AppSpace.sm),
        Text('Bağlı siteler', style: th.titleSmall),
        for (final s in sites)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${s['name']}'),
            subtitle: Text('Kod ${s['site_code']} · aylık bedel ${s['monthly_fee_minor'] == null ? 'yok' : companyMoney(s['monthly_fee_minor'] as num)}'),
            trailing: Wrap(children: [
              IconButton(
                tooltip: 'Deneme süresi',
                icon: const Icon(Icons.hourglass_bottom_rounded),
                onPressed: () async {
                  final r = await _ask('Deneme süresi', ['Bugünden itibaren gün (boş = denemeyi kaldır)']);
                  if (r == null) return;
                  final days = r.first.isEmpty ? null : int.tryParse(r.first);
                  if (r.first.isNotEmpty && days == null) return;
                  await _run(() => _service.setSiteTrial(s['site_code'] as int, days), ok: 'Deneme süresi kaydedildi.');
                },
              ),
              IconButton(
                tooltip: 'Firmadan çıkar',
                icon: const Icon(Icons.link_off_rounded),
                onPressed: () => _run(() => _service.unlinkSite(id, s['site_code'] as int), ok: 'Site firmadan çıkarıldı.'),
              ),
            ]),
          ),
        OutlinedButton.icon(
          key: const ValueKey<String>('company_link_site'),
          icon: const Icon(Icons.add_link_rounded),
          label: const Text('Site Bağla'),
          onPressed: () async {
            final r = await _ask('Site bağla', ['Site kodu', 'Aylık bedel (TL, boş olabilir)']);
            if (r == null) return;
            final code = int.tryParse(r[0]);
            final fee = _tlToMinor(r[1]);
            if (code == null || fee == -1) {
              if (mounted) AppSnack.show(context, 'Site kodu ya da bedel geçersiz.', kind: AppSnackKind.error);
              return;
            }
            await _run(() => _service.linkSite(id, code, fee), ok: 'Site bağlandı.');
          },
        ),
      ]),
    );
  }
}
