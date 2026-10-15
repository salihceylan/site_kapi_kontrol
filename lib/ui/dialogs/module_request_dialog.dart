import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// "Modül Talep Et" penceresi (Platform Faz 1.1): site yöneticisi, tanımlı olmayan bir modül için
/// süper kullanıcıya talep gönderir; isteğe bağlı not (en çok 500 karakter) yazabilir.
///
/// Sunucu reddi (bekleyen talep var, modül zaten açık, yakında...) Türkçe mesajla pencerenin içinde
/// gösterilir ve pencere AÇIK kalır. Başarıda `true` ile kapanır (çağıran veriyi yeniden çeker).
class ModuleRequestDialog extends StatefulWidget {
  const ModuleRequestDialog({
    super.key,
    required this.authService,
    required this.siteCode,
    required this.moduleCode,
    required this.moduleName,
    this.siteName,
  });

  final AuthService authService;
  final int siteCode;
  final String moduleCode;
  final String moduleName;
  final String? siteName;

  /// Not alanı sınırı (sunucu ile aynı).
  static const int maxNoteLength = 500;

  static Future<bool?> show(
    BuildContext context, {
    required AuthService authService,
    required int siteCode,
    required String moduleCode,
    required String moduleName,
    String? siteName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ModuleRequestDialog(
        authService: authService,
        siteCode: siteCode,
        moduleCode: moduleCode,
        moduleName: moduleName,
        siteName: siteName,
      ),
    );
  }

  @override
  State<ModuleRequestDialog> createState() => _ModuleRequestDialogState();
}

class _ModuleRequestDialogState extends State<ModuleRequestDialog> {
  final TextEditingController _noteController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.authService.createModuleRequest(
        widget.siteCode,
        widget.moduleCode,
        note: _noteController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Talep gönderilemedi. Sunucuya bağlanılamadı.';
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
      title: 'Modül Talep Et',
      subtitle: siteName == null || siteName.isEmpty ? null : siteName,
      icon: Icons.send_rounded,
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Gönderiliyor...' : 'Talep Gönder'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            InlineNotice(message: _error!),
            const SizedBox(height: AppSpace.md),
          ],
          Text(
            '"${widget.moduleName}" modülü için sistem yöneticisine talep gönderilecek. '
            'Talep onaylanırsa modül siteniz için tanımlanır.',
            style: th.bodyMedium?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _noteController,
            enabled: !_submitting,
            minLines: 2,
            maxLines: 4,
            maxLength: ModuleRequestDialog.maxNoteLength,
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Not (isteğe bağlı)',
              hintText: 'Örn: Aidat takibi için gerekli',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}
