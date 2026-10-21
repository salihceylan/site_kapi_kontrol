// Ödeme ayarları penceresi (Dalga 2 / 2A): site kısa kodu (3 harf), sakinlere gösterilen banka hesabı, dekont anahtarı (2B; KVKK notlu) ve örnek kod.
// Kurul salt okunur görür (IBAN maskeli). Önek çakışmasında sunucunun önerileri gösterilir. Sürüm uyuşmazlığında yeniden yüklenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/payment_info.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/finance_payment_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

class FinancePaymentSettingsDialog extends StatefulWidget {
  const FinancePaymentSettingsDialog({super.key, required this.scope});

  final PeopleScope scope;

  /// Kaydedilirse başarı iletisi, aksi halde null.
  static Future<String?> show(BuildContext context, {required PeopleScope scope}) {
    return showDialog<String>(context: context, barrierDismissible: false, builder: (_) => FinancePaymentSettingsDialog(scope: scope));
  }

  @override
  State<FinancePaymentSettingsDialog> createState() => _FinancePaymentSettingsDialogState();
}

class _FinancePaymentSettingsDialogState extends State<FinancePaymentSettingsDialog> {
  PaymentSettings? _settings;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<String> _suggestions = const <String>[];
  final TextEditingController _prefix = TextEditingController();
  int? _accountId;
  bool _notices = false;

  bool get _canWrite => widget.scope.canWrite;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _prefix.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await FinancePaymentService.of(widget.scope.authService).run(
        (api, token) => api.getSettings(token: token, siteCode: widget.scope.siteCode),
      );
      if (!mounted) return;
      setState(() {
        _settings = s;
        _prefix.text = s.prefix ?? s.suggestedPrefix ?? '';
        _accountId = s.residentAccountId;
        _notices = s.noticesEnabled;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = financeMessageOf(e, 'Ödeme ayarları yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  bool get _prefixValid => RegExp(r'^[A-Za-zÇĞİÖŞÜçğıöşü]{3}$').hasMatch(_prefix.text.trim());

  Future<void> _save() async {
    final s = _settings;
    if (s == null || _submitting || !_prefixValid) return;
    final prefix = _prefix.text.trim();
    final changedPrefix = s.prefix == null || prefix.toUpperCase() != s.prefix;
    final changedAccount = _accountId != s.residentAccountId;
    final changedNotices = _notices != s.noticesEnabled;
    if (!changedPrefix && !changedAccount && !changedNotices) {
      setState(() => _error = 'Değişiklik yapmadınız.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _suggestions = const <String>[];
    });
    try {
      await FinancePaymentService.of(widget.scope.authService).run(
        (api, token) => api.putSettings(
          token: token,
          siteCode: widget.scope.siteCode,
          expectedVersion: s.settingsVersion,
          prefix: changedPrefix ? prefix : null,
          residentAccountId: changedAccount ? _accountId : null,
          clearResidentAccount: changedAccount && _accountId == null,
          noticesEnabled: changedNotices ? _notices : null,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop('Ödeme ayarları kaydedildi.');
    } catch (e) {
      if (!mounted) return;
      final suggestions = e is ApiException && e.code == 'PREFIX_TAKEN' ? _suggestionsOf(e) : const <String>[];
      final conflict = e is ApiException && e.code == 'SETTINGS_VERSION_CONFLICT';
      setState(() {
        _submitting = false;
        _suggestions = suggestions;
        _error = financeWriteMessage(e, 'Ayarlar kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.', hint: 'Kayıt oluşmuş olabilir; ekranı yenileyip kontrol edin.');
      });
      if (conflict) unawaited(_load());
    }
  }

  static List<String> _suggestionsOf(ApiException e) {
    final raw = e.payload?['suggestions'];
    return raw is List ? [for (final v in raw) if (v is String) v] : const <String>[];
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final s = _settings;
    final eligible = s == null ? const <PaymentBankAccount>[] : [for (final a in s.bankAccounts) if (a.isActive && a.hasIban) a];
    final Widget body;
    if (_loading) {
      body = const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Center(child: CircularProgressIndicator()));
    } else if (s == null) {
      body = InlineNotice(message: _error ?? 'Ödeme ayarları yüklenemedi.', onRetry: _load);
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sakinler havale açıklamasına dairelerinin kodunu yazar. Kod: site kısa kodu + daire kodu + ay (örn. ${s.sampleReference ?? 'GUL-A2-1026'}).',
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const ValueKey<String>('pay_settings_prefix'),
            controller: _prefix,
            enabled: _canWrite && !_submitting,
            maxLength: 3,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]'))],
            decoration: InputDecoration(
              labelText: 'Site kısa kodu (3 harf)',
              helperText: s.prefix == null ? 'Önerilen: ${s.suggestedPrefix ?? '-'}. Türkçe harfler karşılığına çevrilir.' : 'Değişirse eski kod da geçerli kalır.',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (s.aliases.isNotEmpty) Text('Eski kodlar: ${s.aliases.join(', ')}', style: th.bodySmall),
          if (_suggestions.isNotEmpty)
            Wrap(
              spacing: AppSpace.sm,
              children: [
                for (final v in _suggestions)
                  ActionChip(label: Text(v), onPressed: () => setState(() => _prefix.text = v)),
              ],
            ),
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<int?>(
            key: const ValueKey<String>('pay_settings_account'),
            initialValue: eligible.any((a) => a.id == _accountId) ? _accountId : null,
            decoration: const InputDecoration(labelText: 'Sakinlere gösterilen banka hesabı'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Seçilmedi')),
              for (final a in eligible) DropdownMenuItem<int?>(value: a.id, child: Text('${a.name} (${a.ibanDisplay})', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _canWrite && !_submitting ? (v) => setState(() => _accountId = v) : null,
          ),
          if (eligible.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text('Önce Kasa sekmesinde bir banka hesabına IBAN ve alıcı adı girin.', style: th.bodySmall),
            ),
          const SizedBox(height: AppSpace.sm),
          SwitchListTile(
            key: const ValueKey<String>('pay_settings_notices'),
            contentPadding: EdgeInsets.zero,
            value: _notices,
            onChanged: _canWrite && !_submitting ? (v) => setState(() => _notices = v) : null,
            title: const Text('Sakinler dekont yükleyebilsin'),
            subtitle: const Text('Dekontlar kişisel veri içerebilir (ad, IBAN); yalnız ödeme eşleştirme için kullanılır. Varsayılan kapalı.'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            InlineNotice(key: const ValueKey<String>('pay_settings_error'), message: _error!),
          ],
        ],
      );
    }
    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        title: const Text('Ödeme bilgisi'),
        content: SingleChildScrollView(child: body),
        actions: [
          TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: Text(_canWrite ? 'Vazgeç' : 'Kapat')),
          if (_canWrite && s != null)
            FilledButton(
              key: const ValueKey<String>('pay_settings_save'),
              onPressed: _prefixValid && !_submitting ? () => unawaited(_save()) : null,
              child: Text(_submitting ? 'Kaydediliyor…' : 'Kaydet'),
            ),
        ],
      ),
    );
  }
}
