import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Ek rol atama penceresi (Platform modül sistemi Faz 1): e-posta + rol (Yönetim Kurulu / Denetçi ya da
/// Görevli). Kişinin önce uygulamada hesabı olmalıdır; olmayan/pasif hesap, zaten yönetici olan kişi
/// vb. sunucu hataları (Türkçeye çevrilmiş) pencerenin içinde gösterilir ve pencere AÇIK kalır.
/// Başarıda `true` ile kapanır (çağıran listeyi yeniden çeker).
class StaffRoleDialog extends StatefulWidget {
  const StaffRoleDialog({
    super.key,
    required this.authService,
    required this.siteCode,
    this.siteName,
  });

  final AuthService authService;
  final int siteCode;
  final String? siteName;

  /// Sunucu reddinin düz Türkçe, ne yapılacağını söyleyen karşılığı (kayıtlı olmayan / etkin olmayan hesap).
  static String messageFor(ApiException e) {
    switch (e.code) {
      case 'USER_NOT_FOUND':
        return 'Bu e-posta ile kayıtlı hesap yok. Kişinin önce uygulamaya kayıt olması gerekir; '
            'kayıt olduktan sonra rolü verebilirsiniz.';
      case 'USER_NOT_ACTIVE':
        return 'Bu hesap henüz etkin değil. Kişinin kaydını (e-posta doğrulaması dahil) '
            'tamamlaması gerekir.';
      default:
        return e.message;
    }
  }

  static Future<bool?> show(
    BuildContext context, {
    required AuthService authService,
    required int siteCode,
    String? siteName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StaffRoleDialog(
        authService: authService,
        siteCode: siteCode,
        siteName: siteName,
      ),
    );
  }

  @override
  State<StaffRoleDialog> createState() => _StaffRoleDialogState();
}

class _StaffRoleDialogState extends State<StaffRoleDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  StaffRoleType? _role;
  bool _submitting = false;
  String? _error;

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final role = _role;
    if (role == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.authService.assignStaffRole(
        widget.siteCode,
        _emailController.text.trim(),
        role.apiValue,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = StaffRoleDialog.messageFor(e);
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Rol atanamadı. Sunucuya bağlanılamadı.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final siteName = widget.siteName;
    return AppDialog(
      title: 'Ek Rol Ata',
      subtitle: siteName == null || siteName.isEmpty ? null : siteName,
      icon: Icons.person_add_alt_1_rounded,
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Atanıyor...' : 'Ata'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              InlineNotice(message: _error!),
              const SizedBox(height: AppSpace.md),
            ],
            Text(
              'Kişinin uygulamada önceden kayıtlı bir hesabı olmalıdır. '
              'Genel rolü değişmez; yalnız bu sitede ek yetki kazanır.',
              style: th.bodyMedium?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'E-posta',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'E-posta zorunludur.';
                if (!_emailPattern.hasMatch(text)) {
                  return 'Geçerli bir e-posta girin.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpace.md),
            DropdownButtonFormField<StaffRoleType>(
              isExpanded: true,
              initialValue: _role,
              borderRadius: BorderRadius.circular(AppRadius.md),
              dropdownColor: p.surface,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              decoration: const InputDecoration(
                labelText: 'Rol',
                prefixIcon: Icon(Icons.badge_rounded),
              ),
              items: [
                for (final type in StaffRoleType.values)
                  DropdownMenuItem<StaffRoleType>(
                    value: type,
                    child: Text(
                      type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _submitting ? null : (value) => setState(() => _role = value),
              validator: (value) => value == null ? 'Bir rol seçin.' : null,
            ),
          ],
        ),
      ),
    );
  }
}
