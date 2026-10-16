import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

/// "İlişki Ekle" (kişiyi bir daireye bağla) ve ilişki düzenleme penceresi (Platform Faz 2a).
///
/// - Ekleme ([residency] null): daire seçilir (zorunlu), ilişki ve giriş tarihi girilir.
/// - Düzenleme: daire sabittir; yalnız ilişki türü ve giriş tarihi değişir.
///
/// Bir dairede aynı anda en çok BİR malik ve BİR kiracı olabilir; ikincisinde sunucu 409
/// `RELATION_TAKEN` döner ve mesaj pencerenin içinde gösterilir (görünür konuma kaydırılır; pencere açık
/// kalır). Düzenlemede yalnız DEĞİŞEN alanlar gider: ilişki yalnız değiştiyse, giriş tarihi yalnız
/// değiştiyse; tarih silindiyse sunucuya açıkça `move_in_date: null` gönderilir. Hiçbir şey değişmediyse
/// sunucuya gidilmeden kapanır (null döner: çağıran "güncellendi" demez). Gönderim sürerken geri tuşu
/// pencereyi kapatmaz. Başarıda güncel [PersonDetail] ile kapanır.
class ResidencyDialog extends StatefulWidget {
  const ResidencyDialog({
    super.key,
    required this.scope,
    required this.personId,
    this.personName = '',
    this.residency,
  });

  final PeopleScope scope;
  final int personId;
  final String personName;

  /// Düzenlenen ilişki; null ise yeni ilişki.
  final Residency? residency;

  static Future<PersonDetail?> show(
    BuildContext context, {
    required PeopleScope scope,
    required int personId,
    String personName = '',
    Residency? residency,
  }) {
    return showDialog<PersonDetail>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ResidencyDialog(
        scope: scope,
        personId: personId,
        personName: personName,
        residency: residency,
      ),
    );
  }

  @override
  State<ResidencyDialog> createState() => _ResidencyDialogState();
}

class _ResidencyDialogState extends State<ResidencyDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _moveIn = TextEditingController(
    text: formatDateField(widget.residency?.moveInDate),
  );
  late ResidencyRelation _relation =
      widget.residency?.relation ?? ResidencyRelation.resident;
  ApartmentSummary? _apartment;
  String? _apartmentError;
  bool _submitting = false;
  String? _error;

  bool get _editing => widget.residency != null;

  @override
  void dispose() {
    _moveIn.dispose();
    super.dispose();
  }

  Future<void> _pickApartment() async {
    final picked = await showApartmentPicker(context, widget.scope);
    if (picked == null || !mounted) return;
    setState(() {
      _apartment = picked;
      _apartmentError = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final valid = validateForm(_formKey);
    if (!_editing && _apartment == null) {
      setState(() {
        _apartmentError = 'Bir daire seçin.';
        _error = kFixFieldsMessage;
      });
      return;
    }
    if (!valid) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final auth = widget.scope.authService;
    final siteCode = widget.scope.siteCode;
    final moveIn = parseDateField(_moveIn.text);
    try {
      final PersonDetail result;
      if (_editing) {
        final initial = widget.residency!;
        final relationChanged = _relation != initial.relation;
        final dateChanged = moveIn != null && moveIn != initial.moveInDate;
        final clearDate =
            _moveIn.text.trim().isEmpty && initial.moveInDate != null;
        if (!relationChanged && !dateChanged && !clearDate) {
          // Değişiklik yok: sunucuya gitmeden kapanır.
          popIfCurrent(context);
          return;
        }
        result = await auth.updateResidency(
          siteCode,
          initial.id,
          relation: relationChanged ? _relation : null,
          moveInDate: dateChanged ? moveIn : null,
          clearMoveInDate: clearDate,
        );
      } else {
        result = await auth.addResidency(
          siteCode,
          widget.personId,
          apartmentId: _apartment!.id,
          relation: _relation,
          moveInDate: moveIn,
        );
      }
      if (!mounted) return;
      popIfCurrent(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = crmMessageOf(
          e,
          'İlişki kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final residency = widget.residency;
    return PopScope(
      canPop: !_submitting,
      child: AppDialog(
        title: _editing ? 'İlişkiyi Düzenle' : 'İlişki Ekle',
        subtitle: widget.personName.isEmpty ? null : widget.personName,
        icon: Icons.link_rounded,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => popIfCurrent(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Kaydediliyor...' : 'Kaydet'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) CrmFormError(message: _error!),
              if (_editing)
                DialogPanel(
                  child: Text(residency!.fullLabel, style: th.titleSmall),
                )
              else
                CrmPickerField(
                  key: const ValueKey<String>('residency_apartment'),
                  label: 'Daire',
                  icon: Icons.apartment_rounded,
                  value: _apartment?.fullLabel,
                  placeholder: 'Daire seçmek için dokunun',
                  errorText: _apartmentError,
                  enabled: !_submitting,
                  onTap: _pickApartment,
                ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<ResidencyRelation>(
                key: const ValueKey<String>('residency_relation'),
                isExpanded: true,
                initialValue: _relation,
                dropdownColor: p.surface,
                style: th.bodyLarge?.copyWith(color: p.text),
                decoration: const InputDecoration(
                  labelText: 'İlişki',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
                items: [
                  for (final relation in ResidencyRelation.values)
                    DropdownMenuItem<ResidencyRelation>(
                      value: relation,
                      child: Text(
                        relation.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value != null) setState(() => _relation = value);
                      },
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('residency_move_in'),
                controller: _moveIn,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                inputFormatters: const [DateInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Giriş tarihi (isteğe bağlı)',
                  hintText: 'GG.AA.YYYY',
                  prefixIcon: Icon(Icons.event_rounded),
                ),
                validator: validateDateField,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
