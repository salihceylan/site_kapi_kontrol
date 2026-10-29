import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/finance_4b_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show filledToneStyle;

/// Süper kullanıcının site detayındaki "Hukuk onayı" anahtarı (gecikme tazminatı / borç hatırlatma).
///
/// Bayrak SİTE başınadır (sunucu: GET/PUT `/admin/sites/:siteCode/finance-legal-gate`, yalnız süper kullanıcı,
/// işlem izli). Anahtar yalnız sunucu "tamam" deyince döner: değişiklik önce onay penceresinden geçer
/// ("Avukat onayı alındı mı?"), vazgeçilirse ya da kayıt başarısız olursa eski durum kalır. Çağıran bu parçayı
/// yalnız süper kullanıcıya gösterir; yetki asıl olarak sunucuda denetlenir.
class SiteLegalGateTile extends StatefulWidget {
  const SiteLegalGateTile({super.key, required this.siteCode, required this.service});

  final int siteCode;
  final Finance4bService service;

  static const String title = 'Hukuk onayı (gecikme tazminatı/borç hatırlatma)';

  @override
  State<SiteLegalGateTile> createState() => _SiteLegalGateTileState();
}

class _SiteLegalGateTileState extends State<SiteLegalGateTile> {
  bool? _value;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.service.run(
        (api, token) => api.getSiteLegalGate(token: token, siteCode: widget.siteCode),
      );
      if (!mounted) return;
      setState(() {
        _value = value;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = financeMessageOf(
          error,
          'Hukuk onayı durumu yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  /// Yazma sonucu belirsizse (zaman aşımı vb.) gerçek durumu sessizce yeniden okur.
  Future<void> _refreshQuietly() async {
    try {
      final value = await widget.service.run(
        (api, token) => api.getSiteLegalGate(token: token, siteCode: widget.siteCode),
      );
      if (mounted) setState(() => _value = value);
    } catch (_) {
      // Okuma da başarısızsa mevcut gösterim kalır; kullanıcıya hata bildirimi zaten verildi.
    }
  }

  Future<void> _toggle(bool next) async {
    if (_saving || _loading || _value == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _LegalGateConfirmDialog(enable: next),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.service.run(
        (api, token) => api.setSiteLegalGate(token: token, siteCode: widget.siteCode, enabled: next),
      );
      if (!mounted) return;
      setState(() {
        _value = saved;
        _saving = false;
      });
      AppSnack.show(
        context,
        saved ? 'Hukuk onayı açıldı.' : 'Hukuk onayı kapatıldı.',
        kind: AppSnackKind.success,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnack.show(
        context,
        financeOutcomeUncertain(error)
            ? 'Hukuk onayı kaydedilemedi ya da sonucu belirsiz. Güncel durum yeniden okunuyor.'
            : financeMessageOf(error, 'Hukuk onayı kaydedilemedi. Biraz sonra tekrar deneyin.'),
        kind: AppSnackKind.error,
      );
      if (financeOutcomeUncertain(error)) await _refreshQuietly();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final error = _error;
    if (error != null) {
      return InlineNotice(message: error, onRetry: _load);
    }
    final value = _value;
    final String status;
    if (_loading) {
      status = 'Durum yükleniyor...';
    } else if (value == true) {
      status = 'Açık: site yöneticisi gecikme tazminatı ve borç hatırlatmayı Ayarlar bölümünden açabilir.';
    } else {
      status = 'Kapalı: avukat onayı alınana kadar bu sitede gecikme tazminatı ve borç hatırlatma çalışmaz.';
    }
    return Material(
      type: MaterialType.transparency,
      child: SwitchListTile(
        key: const ValueKey<String>('site_hukuk_onayi_anahtari'),
        value: value ?? false,
        onChanged: (_loading || _saving || value == null) ? null : _toggle,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        contentPadding: EdgeInsets.zero,
        secondary: _saving
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Icon(Icons.gavel_rounded, size: 24, color: p.textSecondary),
        title: Text(SiteLegalGateTile.title, style: th.titleSmall),
        subtitle: Text(status, style: th.bodyMedium),
      ),
    );
  }
}

class _LegalGateConfirmDialog extends StatelessWidget {
  const _LegalGateConfirmDialog({required this.enable});

  final bool enable;

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.gavel_rounded,
      tone: enable ? AppTone.warning : AppTone.primary,
      title: enable ? 'Hukuk onayı açılsın mı?' : 'Hukuk onayı kapatılsın mı?',
      actions: [
        TextButton(
          onPressed: () => popIfCurrent(context, false),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          style: filledToneStyle(context, tone: enable ? AppTone.warning : AppTone.primary),
          onPressed: () => popIfCurrent(context, true),
          child: Text(enable ? 'Evet, onay alındı' : 'Kapat'),
        ),
      ],
      child: Text(
        enable
            ? 'Avukat onayı alındı mı? Gecikme tazminatı ve borç hatırlatma yalnızca avukat onayı alındıktan sonra '
                  'açılmalıdır. Onaylarsanız bu sitenin yöneticisi bu özellikleri açabilir. İşlem kayda geçer.'
            : 'Bu sitede gecikme tazminatı ve borç hatırlatma yeniden açılana kadar çalışmaz. İşlem kayda geçer.',
      ),
    );
  }
}
