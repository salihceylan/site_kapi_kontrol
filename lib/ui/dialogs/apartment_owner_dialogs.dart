import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Bir dairedeki en çok malik sayısı (sunucudaki `OWNER_LIMIT` ile aynı; aşılırsa sunucu 409 `OWNER_LIMIT` döner, "Malik ekle" gizlenir).
const int kApartmentOwnerLimit = 10;

/// Çoklu malik (104) açıklaması: hesap muhatabı nedir. İki pencerede ve kartta aynı metin kullanılır.
const String kAccountHolderExplain =
    'Hesap muhatabı: borç, ekstre, makbuz ve hatırlatmaların hitap ettiği TEK malik. '
    'Diğer malikler kayıtlı kalır ama borç görmez ve malik yetkisi kullanamaz.';

/// "Malik Ekle" penceresi (çoklu malik, 104): dairenin maliklerine kayıtlı bir kişiyi ya da yeni bir kişiyi ekler.
///
/// - Kayıtlı kişi: seçiciyle (kişi arama) seçilir. Kişi bu dairede zaten aile üyesi / sakin ise ilişkisi malike çevrilir.
/// - Yeni kişi: ad soyad zorunlu, telefon / e-posta isteğe bağlı; HESAPSIZ kayıt olarak açılır.
/// - "Hesap muhatabı olsun": açıksa borç / ekstre / hatırlatma bu kişiye döner (eski muhatap malik olarak kalır). Dairede başka malik yoksa
///   eklenen kişi zaten muhatap olur.
///
/// Sunucu reddi (aynı e-posta, zaten malik, malik sınırı, ...) Türkçe mesajla pencerenin içinde gösterilir; pencere AÇIK kalır.
/// Başarıda sunucunun döndürdüğü [ApartmentOwnersView] ile kapanır (çağıran kartı yeniler).
class AddOwnerDialog extends StatefulWidget {
  const AddOwnerDialog({
    super.key,
    required this.scope,
    required this.service,
    required this.apartmentId,
    required this.apartmentLabel,
    required this.hasOwners,
  });

  final PeopleScope scope;
  final ApartmentManagementService service;
  final int apartmentId;
  final String apartmentLabel;

  /// Dairede şu an en az bir malik var mı (yoksa eklenen ilk malik zaten hesap muhatabı olur).
  final bool hasOwners;

  static const int maxNameLength = 100;

  static Future<ApartmentOwnersView?> show(
    BuildContext context, {
    required PeopleScope scope,
    required ApartmentManagementService service,
    required int apartmentId,
    required String apartmentLabel,
    required bool hasOwners,
  }) {
    return showDialog<ApartmentOwnersView>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddOwnerDialog(
        scope: scope,
        service: service,
        apartmentId: apartmentId,
        apartmentLabel: apartmentLabel,
        hasOwners: hasOwners,
      ),
    );
  }

  @override
  State<AddOwnerDialog> createState() => _AddOwnerDialogState();
}

class _AddOwnerDialogState extends State<AddOwnerDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController(text: phoneFieldInitial(null));
  final TextEditingController _email = TextEditingController();
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  bool _existing = true;
  PersonSummary? _person;
  bool _personMissing = false;
  bool _makeHolder = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _pickPerson() async {
    final picked = await showPersonPicker(context, widget.scope, title: 'Malik olacak kişi');
    if (picked == null || !mounted) return;
    setState(() {
      _person = picked;
      _personMissing = false;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final fieldsOk = validateForm(
      _formKey,
      validateExtra: () => !_existing || _person != null,
    );
    if (_existing && _person == null) {
      setState(() {
        _personMissing = true;
        _error = kFixFieldsMessage;
      });
      return;
    }
    if (!fieldsOk) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.service.addApartmentOwner(
        widget.scope.siteCode,
        widget.apartmentId,
        personId: _existing ? _person!.id : null,
        fullName: _existing ? null : _name.text.trim(),
        phone: _existing ? null : phoneToApi(_phone.text),
        email: _existing ? null : _email.text.trim().toLowerCase(),
        makeAccountHolder: _makeHolder,
      );
      if (!mounted) return;
      popIfCurrent(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = crmMessageOf(e, 'Malik eklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      child: AppDialog(
        title: 'Malik Ekle',
        subtitle: widget.apartmentLabel.isEmpty ? null : widget.apartmentLabel,
        icon: Icons.person_add_alt_1_rounded,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => popIfCurrent(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('owner_add_submit'),
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Ekleniyor...' : 'Ekle'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) CrmFormError(message: _error!),
              const InlineNotice(
                tone: AppTone.info,
                icon: Icons.info_outline_rounded,
                message: kAccountHolderExplain,
              ),
              const SizedBox(height: AppSpace.md),
              SegmentedButton<bool>(
                key: const ValueKey<String>('owner_add_mode'),
                showSelectedIcon: false,
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: true, label: Text('Kayıtlı kişi')),
                  ButtonSegment<bool>(value: false, label: Text('Yeni kişi')),
                ],
                selected: <bool>{_existing},
                onSelectionChanged: _submitting
                    ? null
                    : (value) => setState(() {
                        _existing = value.first;
                        _error = null;
                      }),
              ),
              const SizedBox(height: AppSpace.md),
              if (_existing)
                CrmPickerField(
                  key: const ValueKey<String>('owner_add_person'),
                  label: 'Kişi *',
                  icon: Icons.person_search_rounded,
                  value: _person == null ? null : crmPersonName(_person!.fullName),
                  placeholder: 'Kişi seçmek için dokunun',
                  errorText: _personMissing && _person == null ? 'Malik olacak kişiyi seçin.' : null,
                  enabled: !_submitting,
                  onTap: _pickPerson,
                  onClear: () => setState(() => _person = null),
                )
              else ...[
                TextFormField(
                  key: const ValueKey<String>('owner_add_name'),
                  controller: _name,
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.words,
                  maxLength: AddOwnerDialog.maxNameLength,
                  decoration: const InputDecoration(
                    labelText: 'Ad Soyad *',
                    prefixIcon: Icon(Icons.person_rounded),
                    counterText: '',
                  ),
                  validator: (value) {
                    final length = (value ?? '').trim().length;
                    if (length < 2) return 'Ad soyad en az 2 karakter olmalı.';
                    if (length > AddOwnerDialog.maxNameLength) {
                      return 'Ad soyad en çok ${AddOwnerDialog.maxNameLength} karakter olabilir.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  key: const ValueKey<String>('owner_add_phone'),
                  controller: _phone,
                  enabled: !_submitting,
                  keyboardType: TextInputType.phone,
                  inputFormatters: const [PhoneInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Telefon (isteğe bağlı)',
                    prefixIcon: Icon(Icons.phone_rounded),
                    hintText: phoneFieldHint,
                  ),
                  validator: validatePhoneField,
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  key: const ValueKey<String>('owner_add_email'),
                  controller: _email,
                  enabled: !_submitting,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'E-posta (isteğe bağlı)',
                    prefixIcon: Icon(Icons.email_rounded),
                    helperText: 'Yeni kişi yalnız kayıt olarak tutulur; giriş hesabı açılmaz.',
                    helperMaxLines: 2,
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    return _emailPattern.hasMatch(text) ? null : 'Geçerli bir e-posta girin.';
                  },
                ),
              ],
              const SizedBox(height: AppSpace.md),
              if (widget.hasOwners)
                SwitchListTile(
                  key: const ValueKey<String>('owner_add_holder'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hesap muhatabı olsun'),
                  subtitle: const Text('Açılırsa borç ve hatırlatmalar bu kişiye döner; mevcut muhatap malik olarak kalır.'),
                  value: _makeHolder,
                  onChanged: _submitting ? null : (value) => setState(() => _makeHolder = value),
                )
              else
                const InlineNotice(
                  tone: AppTone.info,
                  icon: Icons.check_circle_outline_rounded,
                  message: 'Dairede başka malik kayıtlı değil: eklenen kişi hesap muhatabı olur.',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Maliki Çıkar" penceresi (çoklu malik, 104): maliki dairenin maliklerinden çıkarır ("Taşındı" olarak kaydedilir; kişinin hesabı varsa
/// bu dairedeki erişimi kapanır). Çıkarılan hesap muhatabıysa yeni muhatap gerekir: tek kalan malik otomatik, birden çok kaldıysa listeden seçilir.
/// Başarıda sunucunun döndürdüğü [ApartmentOwnersView] ile kapanır.
class RemoveOwnerDialog extends StatefulWidget {
  const RemoveOwnerDialog({
    super.key,
    required this.scope,
    required this.service,
    required this.apartmentId,
    required this.owner,
    required this.owners,
  });

  final PeopleScope scope;
  final ApartmentManagementService service;
  final int apartmentId;
  final ApartmentOwner owner;

  /// Dairenin tüm güncel malikleri (çıkarılan dahil).
  final List<ApartmentOwner> owners;

  static Future<ApartmentOwnersView?> show(
    BuildContext context, {
    required PeopleScope scope,
    required ApartmentManagementService service,
    required int apartmentId,
    required ApartmentOwner owner,
    required List<ApartmentOwner> owners,
  }) {
    return showDialog<ApartmentOwnersView>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RemoveOwnerDialog(
        scope: scope,
        service: service,
        apartmentId: apartmentId,
        owner: owner,
        owners: owners,
      ),
    );
  }

  @override
  State<RemoveOwnerDialog> createState() => _RemoveOwnerDialogState();
}

class _RemoveOwnerDialogState extends State<RemoveOwnerDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  int? _newHolder;
  bool _submitting = false;
  String? _error;

  List<ApartmentOwner> get _others => [
    for (final o in widget.owners)
      if (o.residencyId != widget.owner.residencyId) o,
  ];

  /// Çıkarılan muhatapsa ve ikiden çok malik kalıyorsa seçim zorunlu.
  bool get _needsChoice => widget.owner.isAccountHolder && _others.length > 1;

  Future<void> _submit() async {
    if (_submitting) return;
    if (_needsChoice && _newHolder == null) {
      setState(() => _error = 'Yeni hesap muhatabını seçin.');
      validateForm(_formKey);
      return;
    }
    if (!validateForm(_formKey)) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.service.removeApartmentOwner(
        widget.scope.siteCode,
        widget.apartmentId,
        widget.owner.residencyId,
        newAccountHolderResidencyId: _needsChoice ? _newHolder : null,
      );
      if (!mounted) return;
      popIfCurrent(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = crmMessageOf(e, 'Malik çıkarılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final others = _others;
    final name = crmPersonName(widget.owner.fullName);
    return PopScope(
      canPop: !_submitting,
      child: AppDialog(
        title: 'Maliki Çıkar',
        icon: Icons.person_remove_rounded,
        tone: AppTone.warning,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => popIfCurrent(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('owner_remove_submit'),
            style: filledToneStyle(context, tone: AppTone.warning),
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Çıkarılıyor...' : 'Çıkar'),
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
                '$name maliklerden çıkarılacak ("Taşındı" olarak kaydedilir; kişi daire geçmişinde kalır).',
                style: th.bodyMedium,
              ),
              if (widget.owner.hasAccount) ...[
                const SizedBox(height: AppSpace.sm),
                Text('Kişinin hesabı var: bu daireye erişimi (kapı yetkisi) kapanır; başka dairelerdeki yetkileri etkilenmez.', style: th.bodyMedium),
              ],
              if (widget.owner.isAccountHolder) ...[
                const SizedBox(height: AppSpace.md),
                if (!_needsChoice && others.length == 1)
                  InlineNotice(
                    tone: AppTone.info,
                    icon: Icons.swap_horiz_rounded,
                    message: 'Hesap muhatabı ${crmPersonName(others.single.fullName)} olacak.',
                  )
                else ...[
                  const InlineNotice(
                    tone: AppTone.info,
                    icon: Icons.swap_horiz_rounded,
                    message: 'Bu kişi hesap muhatabı. Çıkarmadan önce yeni hesap muhatabını seçin; borç ve hatırlatmalar ona döner.',
                  ),
                  const SizedBox(height: AppSpace.md),
                  DropdownButtonFormField<int>(
                    key: const ValueKey<String>('owner_new_holder'),
                    isExpanded: true,
                    initialValue: _newHolder,
                    hint: const Text('Seçin'),
                    decoration: const InputDecoration(
                      labelText: 'Yeni hesap muhatabı *',
                      prefixIcon: Icon(Icons.verified_user_rounded),
                    ),
                    items: [
                      for (final o in others)
                        DropdownMenuItem<int>(
                          value: o.residencyId,
                          child: Text(crmPersonName(o.fullName), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    validator: (value) => value == null ? 'Yeni hesap muhatabını seçin.' : null,
                    onChanged: _submitting ? null : (value) => setState(() => _newHolder = value),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
