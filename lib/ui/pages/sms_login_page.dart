import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Telefon + SMS koduyla giriş (063). SMS sağlayıcısı sunucuda yapılandırılmamışsa "Yakında…" gösterir.
/// WhatsApp ile giriş yalnız arayüzdür ("Yakında…").
class SmsLoginPage extends StatefulWidget {
  const SmsLoginPage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<SmsLoginPage> createState() => _SmsLoginPageState();
}

class _SmsLoginPageState extends State<SmsLoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _checking = true;
  bool _enabled = false;
  bool _busy = false;
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await widget.authService.smsLoginEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _checking = false;
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 10) {
      AppSnack.show(context, 'Telefon numaranızı yazın (ör. 0555 123 45 67).', kind: AppSnackKind.error);
      return;
    }
    setState(() => _busy = true);
    final error = await widget.authService.requestSmsCode(phone: phone);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) _codeSent = true;
    });
    if (error != null) {
      AppSnack.show(context, error, kind: AppSnackKind.error, maxLines: 6);
    } else {
      AppSnack.show(
        context,
        'Bu numara kayıtlıysa 6 haneli kod SMS ile gönderildi. Kod 5 dakika geçerlidir.',
        kind: AppSnackKind.success,
        maxLines: 6,
      );
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      AppSnack.show(context, 'Kod 6 haneli olmalıdır.', kind: AppSnackKind.error);
      return;
    }
    setState(() => _busy = true);
    final error = await widget.authService.loginWithSms(phone: _phoneController.text.trim(), code: code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      AppSnack.show(context, error, kind: AppSnackKind.error, maxLines: 6);
      return;
    }
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Telefonla Giriş')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(AppSpace.lg),
              children: [
                if (_checking)
                  const Center(child: CircularProgressIndicator())
                else if (!_enabled) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: StatusChip(label: 'Yakında…', tone: AppTone.neutral, icon: Icons.schedule_rounded),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text('SMS ile giriş şu an kullanılamıyor. E-posta ve parolanızla giriş yapabilirsiniz.', style: th.bodyMedium),
                ] else ...[
                  TextField(
                    controller: _phoneController,
                    enabled: !_codeSent && !_busy,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Telefon numarası', hintText: '0555 123 45 67'),
                  ),
                  const SizedBox(height: AppSpace.md),
                  if (!_codeSent)
                    PrimaryActionButton(label: 'Kod Gönder', onPressed: _busy ? null : _requestCode, loading: _busy)
                  else ...[
                    TextField(
                      controller: _codeController,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'SMS kodu (6 hane)'),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    PrimaryActionButton(label: 'Giriş Yap', onPressed: _busy ? null : _verify, loading: _busy),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() => _codeSent = false),
                      child: const Text('Numarayı değiştir / yeni kod iste'),
                    ),
                  ],
                ],
                const SizedBox(height: AppSpace.lg),
                const Divider(),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    const Icon(Icons.chat_rounded, size: 20),
                    const SizedBox(width: AppSpace.md),
                    Expanded(child: Text('WhatsApp ile giriş', style: th.bodyLarge)),
                    const StatusChip(label: 'Yakında…', tone: AppTone.neutral, icon: Icons.schedule_rounded),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
