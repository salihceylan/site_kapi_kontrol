// Site yöneticisi / süper kullanıcı araçları (Daire kartı ve Kişiler ekranı): daire adminini değiştirme, kapı erişimini askıya alma /
// geri açma, gizli güvenlik talepleri. Sözleşme: docs/PLATFORM_DAIRE_YONETIMI.md, docs/PLATFORM_DAIRE_GUVENLIK_POLITIKASI.md.
// Yetkinin tek kaynağı sunucudur (kurul ve görevli 403); bu pencereler yalnız yazma yetkisi olan kapsamda açılır.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_management.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;

/// "Daire adminini değiştir": aktif sakinlerden birini seç, onayla. Eski admin dairede KALIR (yalnız yönetim yetkisi geçer).
class ChangeAdminDialog extends StatefulWidget {
  const ChangeAdminDialog({super.key, required this.service, required this.siteCode, required this.apartmentId, required this.apartmentLabel});

  final ApartmentManagementService service;
  final int siteCode;
  final int apartmentId;
  final String apartmentLabel;

  /// Değişiklik yapıldıysa true.
  static Future<bool> show(
    BuildContext context, {
    required ApartmentManagementService service,
    required int siteCode,
    required int apartmentId,
    required String apartmentLabel,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => ChangeAdminDialog(service: service, siteCode: siteCode, apartmentId: apartmentId, apartmentLabel: apartmentLabel),
    );
    return changed ?? false;
  }

  @override
  State<ChangeAdminDialog> createState() => _ChangeAdminDialogState();
}

class _ChangeAdminDialogState extends State<ChangeAdminDialog> {
  AdminCandidates? _data;
  int? _selected;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.adminCandidates(widget.siteCode, widget.apartmentId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Sakin listesi yüklenemedi.');
      });
    }
  }

  Future<void> _apply() async {
    final data = _data;
    final target = data?.items.where((c) => c.userCode == _selected).firstOrNull;
    if (data == null || target == null) return;
    final from = data.currentAdmin?.name ?? 'mevcut admin';
    final ok = await confirmCrmAction(
      context,
      title: 'Daire adminini değiştir',
      message:
          'Daire admini $from yerine ${target.name} olacak. $from dairede kalmaya devam eder; yalnızca yönetim yetkisi geçer. Her iki kişiye de uygulama içi bildirim gider.',
      confirmLabel: 'Değiştir',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.service.changeAdmin(widget.siteCode, widget.apartmentId, target.userCode);
      if (!mounted) return;
      AppSnack.show(context, 'Daire admini değiştirildi.', kind: AppSnackKind.success);
      popIfCurrent(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = crmMessageOf(e, 'Daire admini değiştirilemedi.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final th = Theme.of(context).textTheme;
    return AppDialog(
      title: 'Daire adminini değiştir',
      subtitle: widget.apartmentLabel,
      icon: Icons.manage_accounts_rounded,
      actions: [
        TextButton(onPressed: () => popIfCurrent(context, false), child: const Text('Vazgeç')),
        ElevatedButton(onPressed: _saving || _selected == null ? null : () => unawaited(_apply()), child: const Text('Devam')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const Padding(padding: EdgeInsets.all(AppSpace.md), child: LinearProgressIndicator()),
          if (_error != null) InlineNotice(message: _error!, onRetry: data == null ? _load : null),
          if (data != null) ...[
            Text('Mevcut admin: ${data.currentAdmin?.name ?? 'belirlenmemiş'}', style: th.titleSmall),
            const SizedBox(height: AppSpace.sm),
            if (data.items.isEmpty)
              Text('Dairede aktif bağı olan sakin yok.', style: th.bodyMedium)
            else
              RadioGroup<int>(
                groupValue: _selected,
                onChanged: (v) => setState(() => _selected = v),
                child: Column(
                  children: [
                    for (final c in data.items)
                      RadioListTile<int>(
                        value: c.userCode,
                        enabled: !c.isAdmin,
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.name),
                        subtitle: Text(c.isAdmin ? '${c.relationLabel} - şu an admin' : c.relationLabel),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Malik ile kiracı arasındaki "tek taraflı geri alınamaz" kuralı site yönetimini bağlamaz; bu araç acil durum ve anlaşmazlık müdahalesi içindir.',
              style: th.bodySmall?.copyWith(color: context.palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Kapı erişimini askıya alma / geri açma (güvenlik kararı). Neden kodu + zorunlu not; kişiye bildirim GİTMEZ.
class AccessSuspensionDialog extends StatefulWidget {
  const AccessSuspensionDialog({super.key, required this.service, required this.siteCode, required this.apartmentId, required this.apartmentLabel});

  final ApartmentManagementService service;
  final int siteCode;
  final int apartmentId;
  final String apartmentLabel;

  static Future<void> show(
    BuildContext context, {
    required ApartmentManagementService service,
    required int siteCode,
    required int apartmentId,
    required String apartmentLabel,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => AccessSuspensionDialog(service: service, siteCode: siteCode, apartmentId: apartmentId, apartmentLabel: apartmentLabel),
    );
  }

  @override
  State<AccessSuspensionDialog> createState() => _AccessSuspensionDialogState();
}

class _AccessSuspensionDialogState extends State<AccessSuspensionDialog> {
  AdminCandidates? _members;
  List<SuspensionItem> _items = const <SuspensionItem>[];
  int? _selected;
  String _reason = 'safety';
  final _note = TextEditingController();
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await widget.service.adminCandidates(widget.siteCode, widget.apartmentId);
      final items = await widget.service.suspensions(widget.siteCode, widget.apartmentId);
      if (!mounted) return;
      setState(() {
        _members = members;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Kayıtlar yüklenemedi.');
      });
    }
  }

  Future<void> _suspend() async {
    final target = _members?.items.where((c) => c.userCode == _selected).firstOrNull;
    final note = _note.text.trim();
    if (target == null) {
      setState(() => _error = 'Askıya alınacak kişiyi seçin.');
      return;
    }
    if (note.isEmpty) {
      setState(() => _error = 'Not zorunludur (karar gerekçesi).');
      return;
    }
    final ok = await confirmCrmAction(
      context,
      title: 'Kapı erişimini askıya al',
      message:
          '${target.name} bu daire için kapı erişimini kaybeder; bağları ve kayıtları korunur. Kişiye bildirim gitmez; isterseniz kendiniz bilgilendirirsiniz. Sistem iddiayı doğrulayamaz, karar sizindir ve kayda geçer.',
      confirmLabel: 'Askıya al',
      tone: AppTone.danger,
    );
    if (!ok || !mounted) return;
    await _act(() => widget.service.suspend(widget.siteCode, widget.apartmentId, target.userCode, reasonCode: _reason, note: note), 'Erişim askıya alındı.');
  }

  Future<void> _lift(SuspensionItem item) async {
    final ok = await confirmCrmAction(
      context,
      title: 'Erişimi geri aç',
      message: '${item.name} için kapı erişimi yeniden açılacak.',
      confirmLabel: 'Geri aç',
    );
    if (!ok || !mounted) return;
    await _act(() => widget.service.lift(widget.siteCode, widget.apartmentId, item.userCode), 'Erişim geri açıldı.');
  }

  Future<void> _act(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      AppSnack.show(context, success, kind: AppSnackKind.success);
      _note.clear();
      _selected = null;
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = crmMessageOf(e, 'İşlem yapılamadı.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final active = _items.where((i) => i.active).toList();
    final suspendedCodes = active.map((i) => i.userCode).toSet();
    return AppDialog(
      title: 'Kapı erişimi (askıya alma)',
      subtitle: widget.apartmentLabel,
      icon: Icons.lock_person_rounded,
      actions: [TextButton(onPressed: () => popIfCurrent(context), child: const Text('Kapat'))],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const Padding(padding: EdgeInsets.all(AppSpace.md), child: LinearProgressIndicator()),
          if (_error != null) ...[InlineNotice(message: _error!), const SizedBox(height: AppSpace.sm)],
          if (active.isNotEmpty) ...[
            Text('Askıdaki kişiler', style: th.titleSmall),
            for (final i in active)
              Row(
                children: [
                  Expanded(child: Text('${i.name} - ${i.reasonLabel}', style: th.bodyMedium)),
                  TextButton(onPressed: _busy ? null : () => unawaited(_lift(i)), child: const Text('Geri aç')),
                ],
              ),
            const Divider(),
          ],
          if (_members != null) ...[
            Text('Erişimi askıya al', style: th.titleSmall),
            RadioGroup<int>(
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v),
              child: Column(
                children: [
                  for (final c in _members!.items.where((c) => !suspendedCodes.contains(c.userCode)))
                    RadioListTile<int>(value: c.userCode, contentPadding: EdgeInsets.zero, title: Text(c.name), subtitle: Text(c.relationLabel)),
                ],
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Neden'),
              items: const [
                DropdownMenuItem(value: 'court_order', child: Text('Mahkeme / koruma kararı')),
                DropdownMenuItem(value: 'safety', child: Text('Güvenlik')),
                DropdownMenuItem(value: 'other', child: Text('Diğer')),
              ],
              onChanged: (v) => setState(() => _reason = v ?? _reason),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(controller: _note, maxLines: 3, maxLength: 500, decoration: const InputDecoration(labelText: 'Not (zorunlu)')),
            ElevatedButton(onPressed: _busy ? null : () => unawaited(_suspend()), child: const Text('Askıya al')),
          ],
        ],
      ),
    );
  }
}

/// Site düzeyi gizli güvenlik talepleri (yalnız site yöneticisi / süper). Durum değiştirme ve not ekleme.
class SafetyRequestsDialog extends StatefulWidget {
  const SafetyRequestsDialog({super.key, required this.service, required this.siteCode, required this.siteName});

  final ApartmentManagementService service;
  final int siteCode;
  final String siteName;

  static Future<void> show(BuildContext context, {required ApartmentManagementService service, required int siteCode, required String siteName}) {
    return showDialog<void>(
      context: context,
      builder: (_) => SafetyRequestsDialog(service: service, siteCode: siteCode, siteName: siteName),
    );
  }

  @override
  State<SafetyRequestsDialog> createState() => _SafetyRequestsDialogState();
}

class _SafetyRequestsDialogState extends State<SafetyRequestsDialog> {
  List<SafetyRequestItem>? _items;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await widget.service.safetyRequests(widget.siteCode);
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = crmMessageOf(e, 'Talepler yüklenemedi.'));
    }
  }

  Future<void> _update(SafetyRequestItem item, {String? status, String? note}) async {
    setState(() => _busy = true);
    try {
      await widget.service.updateSafetyRequest(widget.siteCode, item.id, status: status, note: note);
      await _load();
    } catch (e) {
      if (mounted) AppSnack.show(context, crmMessageOf(e, 'Talep güncellenemedi.'), kind: AppSnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addNote(SafetyRequestItem item) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Not ekle',
        actions: [
          TextButton(onPressed: () => popIfCurrent(ctx), child: const Text('Vazgeç')),
          ElevatedButton(onPressed: () => popIfCurrent(ctx, controller.text.trim()), child: const Text('Kaydet')),
        ],
        child: TextField(controller: controller, maxLines: 4, maxLength: 1000, decoration: const InputDecoration(labelText: 'Not')),
      ),
    );
    controller.dispose();
    if (note != null && note.isNotEmpty && mounted) await _update(item, note: note);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final items = _items;
    return AppDialog(
      title: 'Güvenlik talepleri',
      subtitle: widget.siteName,
      icon: Icons.shield_outlined,
      actions: [TextButton(onPressed: () => popIfCurrent(context), child: const Text('Kapat'))],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Bu talepleri yalnızca siz görürsünüz (kurul, görevli ve daire sakinleri göremez). Sistem iddiayı doğrulayamaz; karar sizindir.',
            style: th.bodySmall?.copyWith(color: context.palette.textSecondary),
          ),
          const SizedBox(height: AppSpace.sm),
          if (_error != null) InlineNotice(message: _error!, onRetry: _load),
          if (items == null && _error == null) const LinearProgressIndicator(),
          if (items != null && items.isEmpty) Text('Açık talep yok.', style: th.bodyMedium),
          if (items != null)
            for (final r in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: AppCard(
                  key: ValueKey<String>('safety_request_${r.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${r.label} - ${r.statusLabel}', style: th.titleSmall),
                      const SizedBox(height: AppSpace.xs),
                      Text(r.message, style: th.bodyMedium),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        'Talep eden: ${r.requesterName ?? '-'}  |  Tercih: ${r.contactLabel}'
                        '${(r.requesterPhone ?? '').isEmpty ? '' : '  |  ${r.requesterPhone}'}'
                        '${(r.requesterEmail ?? '').isEmpty ? '' : '  |  ${r.requesterEmail}'}',
                        style: th.bodySmall,
                      ),
                      for (final n in r.notes) Text('Not: $n', style: th.bodySmall),
                      Wrap(
                        spacing: AppSpace.sm,
                        children: [
                          if (r.status != 'in_review') TextButton(onPressed: _busy ? null : () => unawaited(_update(r, status: 'in_review')), child: const Text('İncelemeye al')),
                          if (r.status != 'resolved') TextButton(onPressed: _busy ? null : () => unawaited(_update(r, status: 'resolved')), child: const Text('Kapat')),
                          TextButton(onPressed: _busy ? null : () => unawaited(_addNote(r)), child: const Text('Not ekle')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
