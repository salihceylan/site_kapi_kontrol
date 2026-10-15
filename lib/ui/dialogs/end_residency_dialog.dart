import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Taşındı" onay penceresi (Platform Faz 2a): kişinin bir dairedeki güncel ilişkisini bitirir.
///
/// Kayıt SİLİNMEZ; kişi dairenin geçmişinde kalır. Kişinin hesabı varsa o dairedeki kapı yetkisi
/// KAPANIR (başka dairelerdeki yetkileri etkilenmez) ve pencerede bu açıkça yazılır. Taşınma tarihi
/// bugün gelir, değiştirilebilir. Başarıda güncel [PersonDetail] ile kapanır.
class EndResidencyDialog extends StatefulWidget {
  const EndResidencyDialog({
    super.key,
    required this.scope,
    required this.residency,
    required this.personName,
    required this.hasAccount,
  });

  final PeopleScope scope;
  final Residency residency;
  final String personName;
  final bool hasAccount;

  static Future<PersonDetail?> show(
    BuildContext context, {
    required PeopleScope scope,
    required Residency residency,
    required String personName,
    required bool hasAccount,
  }) {
    return showDialog<PersonDetail>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EndResidencyDialog(
        scope: scope,
        residency: residency,
        personName: personName,
        hasAccount: hasAccount,
      ),
    );
  }

  @override
  State<EndResidencyDialog> createState() => _EndResidencyDialogState();
}

class _EndResidencyDialogState extends State<EndResidencyDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _date = TextEditingController(
    text: formatDateField(DateTime.now()),
  );
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.scope.authService.endResidency(
        widget.scope.siteCode,
        widget.residency.id,
        moveOutDate: parseDateField(_date.text),
      );
      if (!mounted) return;
      popIfCurrent(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = crmMessageOf(
          e,
          'Taşınma kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final name = widget.personName.trim().isEmpty
        ? 'Bu kişi'
        : widget.personName.trim();
    return PopScope(
      canPop: !_submitting,
      child: AppDialog(
        title: 'Taşındı',
        subtitle: widget.residency.fullLabel,
        icon: Icons.logout_rounded,
        tone: AppTone.warning,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => popIfCurrent(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: filledToneStyle(context, tone: AppTone.warning),
            onPressed: _submitting ? null : _submit,
            child: Text(
              _submitting ? 'Kaydediliyor...' : 'Taşındı Olarak İşaretle',
            ),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) CrmFormError(message: _error!),
              Text(
                '$name bu daireden taşındı olarak işaretlensin mi? Kayıt silinmez; kişi dairenin geçmişinde kalır.',
                style: th.bodyMedium,
              ),
              if (widget.hasAccount) ...[
                const SizedBox(height: AppSpace.md),
                const InlineNotice(
                  tone: AppTone.warning,
                  message:
                      'Kişinin hesabı var: bu dairedeki kapı yetkisi kapanır. Başka dairelerdeki yetkileri etkilenmez.',
                ),
              ],
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('end_residency_date'),
                controller: _date,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                inputFormatters: const [DateInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Taşınma tarihi',
                  hintText: 'GG.AA.YYYY',
                  prefixIcon: Icon(Icons.event_rounded),
                ),
                validator: _validateMoveOut,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sunucu gelecek tarihli taşınmayı kabul etmez (bugünden ilerisi reddedilir; "bugün" yerel saate
  /// göredir) ve giriş tarihinden ÖNCEKİ taşınma tarihi tutarsızdır.
  String? _validateMoveOut(String? value) {
    final error = validateDateField(value);
    if (error != null) return error;
    final date = parseDateField(value);
    if (date == null) return null;
    final now = DateTime.now();
    if (date.isAfter(DateTime(now.year, now.month, now.day))) {
      return 'Taşınma tarihi bugünden ileri olamaz.';
    }
    final moveIn = widget.residency.moveInDate;
    if (moveIn != null &&
        date.isBefore(DateTime(moveIn.year, moveIn.month, moveIn.day))) {
      return 'Taşınma tarihi giriş tarihinden önce olamaz.';
    }
    return null;
  }
}
