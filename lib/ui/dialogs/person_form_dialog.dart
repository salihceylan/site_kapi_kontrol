import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmInt;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

/// "Kişi Ekle" ve "Düzenle" penceresi (Platform Faz 2a).
///
/// - Ekleme ([person] null): ad soyad, telefon (+90 hazır, 3-3-2-2), e-posta, isteğe bağlı daire +
///   ilişki + giriş tarihi, not.
/// - Düzenleme: yalnız DEĞİŞEN alanlar gönderilir. HESABI OLAN kişide ad / telefon / e-posta salt okunur
///   görünür (TEK bir bilgilendirme bandı: "kişinin kendi profilinden değişir") ve gönderilmez; yalnız
///   not düzenlenir. Dahili hesapta (`account_kind: internal`) iletişim e-postası da düzenlenebilir.
///
/// Sunucu reddi (aynı e-posta, dolu ilişki, ...) Türkçe mesajla pencerenin içinde gösterilir (görünür
/// konuma kaydırılır) ve pencere AÇIK kalır. Gönderim sürerken geri tuşu pencereyi kapatmaz. Başarıda
/// sunucunun döndürdüğü [PersonDetail] ile kapanır (çağıran listeyi yeniler). [onChanged]: "Kişiyi Aç"
/// ile açılan mevcut kişi kartında bir değişiklik yapılınca çağrılır (dış liste tazelensin).
class PersonFormDialog extends StatefulWidget {
  const PersonFormDialog({
    super.key,
    required this.scope,
    this.person,
    this.onChanged,
  });

  final PeopleScope scope;

  /// Düzenlenen kişi; null ise yeni kişi.
  final PersonDetail? person;

  /// İç karttaki (mevcut kişi) değişiklikleri için.
  final VoidCallback? onChanged;

  static const int maxNoteLength = 500;
  static const int maxNameLength = 100;

  static Future<PersonDetail?> show(
    BuildContext context, {
    required PeopleScope scope,
    PersonDetail? person,
    VoidCallback? onChanged,
  }) {
    return showDialog<PersonDetail>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          PersonFormDialog(scope: scope, person: person, onChanged: onChanged),
    );
  }

  @override
  State<PersonFormDialog> createState() => _PersonFormDialogState();
}

class _PersonFormDialogState extends State<PersonFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.person?.fullName ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    // Hesabı olan kişinin telefonu salt okunur alanda OLDUĞU GİBİ görünür (yabancı / serbest biçimli
    // numara bozulmaz, kişi kartıyla aynıdır); boşsa "+90 " öneki de gösterilmez.
    text: _identityLocked
        ? formatPhoneDisplay(widget.person?.phone)
        : formatPhoneField(widget.person?.phone),
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.person?.email ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.person?.note ?? '',
  );
  final TextEditingController _moveIn = TextEditingController();

  ApartmentSummary? _apartment;
  ResidencyRelation _relation = ResidencyRelation.resident;
  bool _submitting = false;
  String? _error;

  // PERSON_EXISTS yanıtındaki mevcut kişinin numarası (0 / eksik: "Kişiyi Aç" gösterilmez).
  int _existingPersonId = 0;

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  bool get _editing => widget.person != null;

  /// Hesabı olan kişide ad ve telefon CRM'den değişmez (kişinin kendi profilinden değişir).
  bool get _identityLocked => widget.person?.hasAccount == true;

  /// E-posta da kilitlidir; YALNIZ dahili (@ahbu.local) hesapta iletişim e-postası düzenlenebilir
  /// (`account_kind: internal`). Alan yoksa (eski sunucu) hesabı olan kişide e-posta da salt okunurdur.
  bool get _emailLocked =>
      widget.person?.hasAccount == true &&
      widget.person?.isInternalAccount != true;

  /// E-posta alanının altındaki durum bazlı yardım metni (yalnız ekleme). Sunucu davranışı (people_service.createPerson):
  /// e-posta + daire varsa ve dairenin sakin hesabı yoksa dahili sakin hesabı açılıp giriş bilgisi (kullanıcı adı + PIN)
  /// e-postayla gönderilir; e-posta bu sitede erişimi olan kayıtlı bir hesaba aitse kişi o hesaba bağlanır; aksi
  /// halde (e-posta yok, daire yok ya da dairenin sakin hesabı var) yalnız kayıt tutulur. Hesabın var olup
  /// olmadığı ima edilmez: yalnız kurallar anlatılır.
  static String emailHelp({required bool hasEmail, required bool hasApartment}) {
    if (!hasEmail) {
      return 'E-posta girmezseniz kişi yalnız kayıt olarak tutulur; giriş hesabı açılmaz.';
    }
    if (!hasApartment) {
      return 'Daire seçmezseniz kişi yalnız kayıt olarak tutulur; giriş hesabı açılmaz. '
          'Kişi siteye katılınca e-postası hesabıyla eşleştirilir.';
    }
    return 'Dairenin sakin hesabı yoksa bu kişiye giriş bilgileri (kullanıcı adı ve PIN) e-postayla gönderilir. '
        'Sakin hesabı varsa kişi yalnız kayıt olarak tutulur. '
        'E-posta bu sitedeki kayıtlı bir hesaba aitse kişi o hesaba bağlanır.';
  }

  /// Telefon alanının altındaki yardım metni.
  static const String phoneHelp = 'Telefon yalnız iletişim içindir; giriş telefonla yapılmaz.';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _note.dispose();
    _moveIn.dispose();
    super.dispose();
  }

  Future<void> _pickApartment() async {
    final picked = await showApartmentPicker(context, widget.scope);
    if (picked == null || !mounted) return;
    setState(() => _apartment = picked);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!validateForm(_formKey)) {
      // Özet bildirimi + ilk geçersiz alana kaydırma / odak (kaydırılmış formda hata gizli kalmasın).
      setState(() {
        _error = kFixFieldsMessage;
        _existingPersonId = 0;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
      _existingPersonId = 0;
    });
    final auth = widget.scope.authService;
    final siteCode = widget.scope.siteCode;
    try {
      final PersonDetail result;
      if (_editing) {
        final fields = _changedFields();
        if (fields.isEmpty) {
          // Değişiklik yok: sunucuya gitmeden kapanır.
          popIfCurrent(context, widget.person);
          return;
        }
        result = await auth.updatePerson(siteCode, widget.person!.id, fields);
      } else {
        final apartment = _apartment;
        result = await auth.createPerson(
          siteCode,
          fullName: _name.text,
          phone: phoneToApi(_phone.text),
          email: _email.text,
          note: _note.text,
          apartmentId: apartment?.id,
          relation: apartment == null ? null : _relation,
          moveInDate: apartment == null ? null : parseDateField(_moveIn.text),
        );
      }
      if (!mounted) return;
      popIfCurrent(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = crmMessageOf(
          e,
          'Kişi kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
        _existingPersonId = e is ApiException && e.code == 'PERSON_EXISTS'
            ? crmInt(e.payload?['person_id'])
            : 0;
        _submitting = false;
      });
    }
  }

  Future<void> _openExisting() async {
    final id = _existingPersonId;
    if (id <= 0) return;
    await PersonCardDialog.show(
      context,
      scope: widget.scope,
      personId: id,
      // Mevcut kişide yapılan değişiklik dış listeyi de tazeler.
      onChanged: widget.onChanged,
    );
  }

  /// Düzenlemede yalnız değişen alanlar (boşaltılan alan `null` gider; sunucu temizler). HESAPLI kişide
  /// `full_name` / `phone` / `email` anahtarları HİÇ gönderilmez (değişmemiş değer dahil: sunucu 409
  /// PERSON_HAS_ACCOUNT döner); dahili hesapta yalnız `email` serbesttir.
  Map<String, Object?> _changedFields() {
    final initial = widget.person!;
    final fields = <String, Object?>{};
    if (!_identityLocked) {
      final name = _name.text.trim();
      if (name != initial.fullName.trim()) fields['full_name'] = name;
      final phone = phoneToApi(_phone.text);
      if (phone != phoneToApi(initial.phone)) fields['phone'] = phone;
    }
    if (!_emailLocked) {
      final email = _email.text.trim().toLowerCase();
      if (email != (initial.email ?? '').trim().toLowerCase()) {
        fields['email'] = email.isEmpty ? null : email;
      }
    }
    final note = _note.text.trim();
    if (note != (initial.note ?? '').trim()) {
      fields['note'] = note.isEmpty ? null : note;
    }
    return fields;
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final internal = widget.person?.isInternalAccount == true;
    return PopScope(
      // Gönderim sürerken geri tuşu pencereyi kapatmaz (işlem yarıda kalmış gibi görünmesin).
      canPop: !_submitting,
      child: AppDialog(
        title: _editing ? 'Kişiyi Düzenle' : 'Kişi Ekle',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: _editing ? Icons.edit_rounded : Icons.person_add_alt_1_rounded,
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
              if (_error != null)
                CrmFormError(
                  message: _error!,
                  action: _existingPersonId > 0
                      ? PrimaryActionButton(
                          label: 'Kişiyi Aç',
                          icon: Icons.open_in_new_rounded,
                          variant: AppButtonVariant.outline,
                          onPressed: _openExisting,
                        )
                      : null,
                ),
              if (_identityLocked) ...[
                // Alanlarda yardım metni tekrarlanmaz: tek bilgilendirme bandı.
                InlineNotice(
                  tone: AppTone.info,
                  icon: Icons.lock_outline_rounded,
                  message: internal
                      ? 'Bu kişinin hesabı var. Ad ve telefon kişinin kendi profilinden değişir; iletişim e-postası buradan düzenlenebilir.'
                      : 'Bu kişinin hesabı var. Ad, telefon ve e-posta kişinin kendi profilinden değişir.',
                ),
                const SizedBox(height: AppSpace.md),
              ],
              TextFormField(
                key: const ValueKey<String>('person_name'),
                controller: _name,
                enabled: !_submitting,
                readOnly: _identityLocked,
                textCapitalization: TextCapitalization.words,
                maxLength: PersonFormDialog.maxNameLength,
                decoration: const InputDecoration(
                  labelText: 'Ad Soyad',
                  prefixIcon: Icon(Icons.person_rounded),
                  counterText: '',
                ),
                validator: (value) {
                  if (_identityLocked) return null;
                  final length = (value ?? '').trim().length;
                  if (length < 2) return 'Ad soyad en az 2 karakter olmalı.';
                  if (length > PersonFormDialog.maxNameLength) {
                    return 'Ad soyad en çok ${PersonFormDialog.maxNameLength} karakter olabilir.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('person_phone'),
                controller: _phone,
                enabled: !_submitting,
                readOnly: _identityLocked,
                keyboardType: TextInputType.phone,
                inputFormatters: _identityLocked
                    ? null
                    : const [PhoneInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Telefon (isteğe bağlı)',
                  prefixIcon: const Icon(Icons.phone_rounded),
                  helperText: _identityLocked ? null : phoneHelp,
                  helperMaxLines: 3,
                ),
                validator: (value) =>
                    _identityLocked ? null : validatePhoneField(value),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('person_email'),
                controller: _email,
                enabled: !_submitting,
                readOnly: _emailLocked,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: _editing ? null : (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'E-posta (isteğe bağlı)',
                  prefixIcon: const Icon(Icons.email_rounded),
                  // Hesap var / yok ima etmez: yalnız kurallar anlatılır (bkz. [emailHelp]).
                  helperText: _editing
                      ? null
                      : emailHelp(
                          hasEmail: _emailPattern.hasMatch(_email.text.trim()),
                          hasApartment: _apartment != null,
                        ),
                  helperMaxLines: 6,
                ),
                validator: (value) {
                  if (_emailLocked) return null;
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return null;
                  return _emailPattern.hasMatch(text)
                      ? null
                      : 'Geçerli bir e-posta girin.';
                },
              ),
              if (!_editing) ...[
                const SizedBox(height: AppSpace.md),
                CrmPickerField(
                  key: const ValueKey<String>('person_apartment'),
                  label: 'Daire (isteğe bağlı)',
                  icon: Icons.apartment_rounded,
                  value: _apartment?.fullLabel,
                  placeholder: 'Daire seçmek için dokunun',
                  enabled: !_submitting,
                  onTap: _pickApartment,
                  onClear: () => setState(() => _apartment = null),
                ),
                if (_apartment != null) ...[
                  const SizedBox(height: AppSpace.md),
                  DropdownButtonFormField<ResidencyRelation>(
                    key: const ValueKey<String>('person_relation'),
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
                            if (value != null) {
                              setState(() => _relation = value);
                            }
                          },
                  ),
                  const SizedBox(height: AppSpace.md),
                  TextFormField(
                    key: const ValueKey<String>('person_move_in'),
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
              ],
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('person_note'),
                controller: _note,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: PersonFormDialog.maxNoteLength,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
