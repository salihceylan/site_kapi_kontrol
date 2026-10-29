import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/device_integrations_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart' show FinanceSubmitError;

/// Online Tahsilat ve Banka Bağlantısı (Aidat ve Finans'ın parçası): site yöneticisinin ödeme kuruluşu bağlantısını kurduğu tek yer.
///
/// Durum kartı (kurulmadı / sanal POS hazır değil / test / canlı), sağlayıcı seçimi + alan formu (alanlar sunucudan gelir; sırlar
/// maskeli, kaydedilen sır ASLA geri gösterilmez, boş bırakılırsa korunur), "Bağlantıyı sına" ve onaylı "Bağlantıyı kaldır".
/// Sınama yalnız sağlayıcı gerçekten doğruladıysa başarılı der; sürücü etkin değilse bunu açıkça yazar. Hiçbir ödeme alınmaz.
/// Yönetici ([PeopleScope.canWrite]) düzenler, kurul üyesi yalnız durumu görür.
class FinanceOnlineCollectionDialog extends StatefulWidget {
  const FinanceOnlineCollectionDialog({super.key, required this.scope, this.service});

  final PeopleScope scope;

  /// Testler içindir; null ise oturumdan kurulur.
  final DeviceIntegrationsService? service;

  static Future<void> show(BuildContext context, {required PeopleScope scope, DeviceIntegrationsService? service}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceOnlineCollectionDialog(scope: scope, service: service),
    );
  }

  @override
  State<FinanceOnlineCollectionDialog> createState() => _FinanceOnlineCollectionDialogState();
}

class _FinanceOnlineCollectionDialogState extends State<FinanceOnlineCollectionDialog> {
  late final DeviceIntegrationsService _service =
      widget.service ?? DeviceIntegrationsService(authService: widget.scope.authService);
  final Map<String, TextEditingController> _controllers = <String, TextEditingController>{};

  OnlineCollectionState? _state;
  String? _provider;
  String _mode = 'test';
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String provider, String key) =>
      _controllers.putIfAbsent('$provider/$key', () => TextEditingController());

  void _adopt(OnlineCollectionState state) {
    _state = state;
    _provider = state.provider;
    _mode = state.mode ?? 'test';
    // Sırlar forma ASLA yazılmaz; yalnız gizli olmayan alanlar doldurulur.
    for (final c in _controllers.values) {
      c.clear();
    }
    final current = state.current;
    if (current != null) {
      for (final f in current.fields) {
        if (!f.secret) _controller(current.code, f.key).text = state.values[f.key] ?? '';
      }
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final state = await _service.onlineCollection(widget.scope.siteCode);
      if (!mounted) return;
      setState(() {
        _adopt(state);
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = financeMessageOf(e, 'Bağlantı bilgisi yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String failText) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) _error = financeMessageOf(e, failText);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    final provider = _provider;
    final state = _state;
    if (provider == null || state == null) return;
    final def = state.providers.where((p) => p.code == provider).firstOrNull;
    final values = <String, String>{
      for (final f in def?.fields ?? const <CollectionField>[]) f.key: _controller(provider, f.key).text.trim(),
    };
    await _run(() async {
      final saved = await _service.saveOnlineCollection(widget.scope.siteCode, provider: provider, mode: _mode, values: values);
      if (!mounted) return;
      _adopt(saved);
      _notice = 'Bağlantı kaydedildi. Şimdi "Bağlantıyı sına" ile denetleyin.';
    }, 'Bağlantı kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
  }

  Future<void> _test() async {
    await _run(() async {
      final result = await _service.testOnlineCollection(widget.scope.siteCode);
      if (!mounted) return;
      _adopt(result.state);
      _notice = result.ok ? 'Bağlantı doğrulandı.' : result.message;
    }, 'Bağlantı sınanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bağlantıyı kaldır'),
        content: const Text('Kayıtlı anahtarlar silinir ve sakinlere online ödeme sunulmaz. Emin misiniz?'),
        actions: <Widget>[
          TextButton(onPressed: () => popIfCurrent(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            key: const ValueKey<String>('finance_online_remove_confirm'),
            onPressed: () => popIfCurrent(ctx, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await _service.removeOnlineCollection(widget.scope.siteCode);
      final fresh = await _service.onlineCollection(widget.scope.siteCode);
      if (!mounted) return;
      _adopt(fresh);
      _notice = 'Bağlantı kaldırıldı.';
    }, 'Bağlantı kaldırılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
  }

  String _statusTitle(OnlineCollectionState s) {
    switch (s.status) {
      case 'configured_live':
        return 'Kuruldu — canlı mod';
      case 'configured_test':
        return 'Kuruldu — test modu';
      case 'not_ready':
        return 'Sanal POS henüz hazır değil';
      default:
        return 'Bağlantı kurulmadı';
    }
  }

  Widget _statusCard(BuildContext context, OnlineCollectionState s) {
    final th = Theme.of(context).textTheme;
    final none = s.status == 'none';
    return AppCard(
      key: const ValueKey<String>('finance_online_status'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(_statusTitle(s), style: th.titleMedium),
          const SizedBox(height: AppSpace.xs),
          if (none) ...<Widget>[
            const Text('Kurulum adımları:'),
            const Text('1. Ödeme kuruluşuyla sözleşmenizi tamamlayın.'),
            const Text('2. Aşağıdan sağlayıcıyı seçip panelinizdeki anahtarları girin ve kaydedin.'),
            const Text('3. "Bağlantıyı sına" ile denetleyin; canlıya geçmeden önce test modunda deneyin.'),
          ] else ...<Widget>[
            if (s.current != null) Text('Sağlayıcı: ${s.current!.name}'),
            Text(s.complete ? 'Gerekli alanlar dolu.' : 'Gerekli alanlar eksik.'),
            if (s.lastTestMessage != null) Text('Son sınama: ${s.lastTestMessage}', key: const ValueKey<String>('finance_online_last_test')),
          ],
          const SizedBox(height: AppSpace.xs),
          Text(
            s.driverActive
                ? 'Sakinlere "Online Öde" yalnız canlı modda ve sınama başarılıysa görünür.'
                : 'Bu sürümde sağlayıcı sürücüsü etkin değil: kaydettiğiniz bilgiler saklanır, sakinlere online ödeme sunulmaz ve ödeme alınmaz.',
            style: th.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context, OnlineCollectionState s) {
    final provider = _provider;
    final def = s.providers.where((p) => p.code == provider).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<String>(
          key: ValueKey<String>('finance_online_provider_${provider ?? 'none'}'),
          isExpanded: true,
          initialValue: provider,
          decoration: const InputDecoration(labelText: 'Ödeme kuruluşu'),
          items: <DropdownMenuItem<String>>[
            for (final p in s.providers) DropdownMenuItem<String>(value: p.code, child: Text(p.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: _busy ? null : (v) => setState(() => _provider = v),
        ),
        if (def != null && def.fields.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.sm),
          SegmentedButton<String>(
            key: const ValueKey<String>('finance_online_mode'),
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'test', label: Text('Test')),
              ButtonSegment<String>(value: 'live', label: Text('Canlı')),
            ],
            selected: <String>{_mode},
            onSelectionChanged: _busy ? null : (v) => setState(() => _mode = v.first),
          ),
          for (final f in def.fields) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            TextField(
              key: ValueKey<String>('finance_online_field_${f.key}'),
              controller: _controller(def.code, f.key),
              obscureText: f.secret,
              enableSuggestions: !f.secret,
              autocorrect: false,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: f.required ? '${f.label} *' : f.label,
                helperText: f.secret && (s.secretsSet[f.key] ?? false) && s.provider == def.code
                    ? 'Kayıtlı (••••••••). Değiştirmek için yeni değer girin; boş bırakırsanız korunur.'
                    : f.hint,
                helperMaxLines: 3,
              ),
            ),
          ],
        ],
        const SizedBox(height: AppSpace.md),
        FilledButton(
          key: const ValueKey<String>('finance_online_save'),
          onPressed: _busy || provider == null ? null : _save,
          child: const Text('Kaydet'),
        ),
        if (s.status != 'none') ...<Widget>[
          const SizedBox(height: AppSpace.sm),
          OutlinedButton(
            key: const ValueKey<String>('finance_online_test'),
            onPressed: _busy ? null : _test,
            child: const Text('Bağlantıyı sına'),
          ),
          const SizedBox(height: AppSpace.sm),
          TextButton(
            key: const ValueKey<String>('finance_online_remove'),
            onPressed: _busy ? null : _remove,
            child: const Text('Bağlantıyı kaldır'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return AppDialog(
      title: 'Online Tahsilat',
      subtitle: widget.scope.siteName.trim().isEmpty ? null : widget.scope.siteName.trim(),
      icon: Icons.account_balance_rounded,
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('finance_online_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_error != null)
            FinanceSubmitError(
              key: const ValueKey<String>('finance_online_error'),
              message: _error!,
              action: state == null
                  ? TextButton.icon(
                      onPressed: _loading ? null : () => unawaited(_load()),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tekrar dene'),
                    )
                  : null,
            ),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: CircularProgressIndicator()))
          else if (state != null) ...<Widget>[
            _statusCard(context, state),
            if (_notice != null) ...<Widget>[
              const SizedBox(height: AppSpace.sm),
              Text(_notice!, key: const ValueKey<String>('finance_online_notice')),
            ],
            const SizedBox(height: AppSpace.md),
            if (widget.scope.canWrite) _form(context, state),
          ],
        ],
      ),
    );
  }
}
