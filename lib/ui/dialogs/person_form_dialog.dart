import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart'
    show VehicleRecord, crmInt;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_edit_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_info_section.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/vehicle_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

/// "Kişi Ekle" ve "Düzenle" penceresi (Platform Faz 2a).
///
/// - Ekleme ([person] null): ad soyad, telefon (+90 hazır, 5XX XXX XX XX biçimine zorlanır), e-posta, isteğe bağlı
///   daire + ilişki + taşınma (giriş) tarihi, plaka(lar), not ve (daire seçilince) genişletilebilir "Daire bilgileri".
/// - Düzenleme: yalnız DEĞİŞEN alanlar gönderilir. Hesabı OLMAYAN kişide ve SİTENİN YÖNETTİĞİ hesapta
///   ([PersonDetail.identityEditable]: yönetimce / toplu yüklemeyle açılmış sakin hesabı) ad ve telefon düzenlenir;
///   sunucu hesabın kendisine yazar (kişinin hesabı o adı / telefonu zaten oradan okur). Kişinin KENDİ kaydolduğu /
///   sahiplendiği hesapta ad / telefon / e-posta salt okunur görünür (TEK bir bilgilendirme bandı: "kişinin kendi
///   profilinden değişir") ve gönderilmez. Dahili hesapta (`account_kind: internal`) iletişim e-postası da
///   düzenlenebilir; gerçek hesapta e-posta giriş adresidir, kilitli kalır. Plaka, not ve daire bilgileri her zaman düzenlenir.
///
/// ZORUNLU alanlar etikette "*" ile işaretlidir: ad soyad; telefon ya da e-postadan en az biri (kişinin tüm
/// ilişkisi "Aile Üyesi" ise ikisi de boş olabilir); daire seçildiyse ilişki (varsayılan seçili gelmez: borcun
/// hangi hesaba yazılacağını belirler) ve taşınma (giriş) tarihi (bugünle dolu gelir; Borcum görünürlüğü buna
/// bağlıdır). Plaka, not ve "Daire bilgileri"nin tümü isteğe bağlıdır.
///
/// Kayıt ADIM ADIM yapılır: kişi (oluştur / güncelle) -> daire bilgileri (yalnız değişenler,
/// [ApartmentFieldsDraft] ile "Daireyi Düzenle" ile AYNI doğrulama ve uç) -> plakalar (araç ekle / kaldır).
/// Bir sonraki adım düşerse pencere AÇIK kalır, hangi adımın başarısız olduğu yazılır ("Kişi kaydedildi, plaka
/// eklenemedi: ...") ve yeniden "Kaydet" yalnız kalan adımları dener (kişi iki kez oluşturulmaz). Vazgeç / geri,
/// kişi kaydedilmişse onu döndürür (çağıran liste tazelensin).
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

  /// Telefon ve e-posta alanlarında ikisi de boşken gösterilen hata.
  static const String contactRequiredMessage =
      'Telefon ya da e-postadan en az biri girilmeli.';

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
    // Salt okunur alanda (kişinin kendi hesabı) telefon OLDUĞU GİBİ görünür (yabancı / serbest biçimli numara
    // bozulmaz, kişi kartıyla aynıdır); boşsa "+90 " öneki de gösterilmez. Düzenlenebilir alanda boşsa "+90 " hazır
    // gelir, ayrıştırılabilen numara gruplanır, ayrıştırılamayan eski kayıt olduğu gibi kalır (dokunulmazsa değişmez).
    text: _identityLocked
        ? formatPhoneDisplay(widget.person?.phone)
        : phoneFieldInitial(widget.person?.phone),
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.person?.email ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.person?.note ?? '',
  );
  final TextEditingController _moveIn = TextEditingController();

  /// Kişinin mevcut (aktif) plakaları: düzenlemede "34 ABC 123, 06 XY 789" olarak dolu gelir.
  late final TextEditingController _plates = TextEditingController(
    text: _activeVehicles.map((v) => v.displayPlate).join(', '),
  );

  /// Daire bilgileri taslağı ("Daireyi Düzenle" ile ortak doğrulama / fark).
  final ApartmentFieldsDraft _aptDraft = ApartmentFieldsDraft();

  ApartmentSummary? _apartment;

  /// Varsayılan YOK: kullanıcı seçmek zorundadır (borcun hangi hesaba yazılacağını belirler).
  ResidencyRelation? _relation;
  bool _submitting = false;
  String? _error;

  bool _aptExpanded = false;
  bool _aptLoading = false;
  String? _aptLoadError;
  int _aptToken = 0;

  // Kayıt ilerlemesi (adım adım kayıt; hata sonrası yeniden denemede yapılanlar tekrarlanmaz).
  bool _personDone = false;
  bool _created = false;
  bool _personChanged = false;
  bool _aptUpdated = false;
  bool _extrasChanged = false;
  bool _dirty = false;
  PersonDetail? _savedPerson;

  /// Kişide kayıtlı aktif plakalar: normalize plaka -> araç numarası (düzenlemede açılışta; sonra adımlarla güncellenir).
  late final Map<String, int> _plateIds = <String, int>{
    for (final v in _activeVehicles)
      if (v.plate.isNotEmpty) v.plate: v.id,
  };

  /// Açılışta kişide kayıtlı plakalar (normalize). Türk plakası kuralına UYMAYAN eski kayıtlar da burada: alan bunlara dokunmaz,
  /// değişmemişlerse kaydı engellemez ve alandan silinmedikçe pasife alınmaz.
  late final Set<String> _storedPlates = <String>{
    for (final v in _activeVehicles)
      if (v.plate.isNotEmpty) v.plate,
  };

  // PERSON_EXISTS yanıtındaki mevcut kişinin numarası (0 / eksik: "Kişiyi Aç" gösterilmez).
  int _existingPersonId = 0;

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  bool get _editing => widget.person != null;

  Iterable<VehicleRecord> get _activeVehicles =>
      (widget.person?.vehicles ?? const <VehicleRecord>[]).where(
        (v) => v.isActive,
      );

  bool get _hasAccount => widget.person?.hasAccount == true;

  /// Kişinin KENDİ hesabında (kendi kaydolan / sahiplenen) ad ve telefon CRM'den değişmez (kişinin kendi profilinden
  /// değişir). Hesapsız kişi ve sitenin yönettiği hesap (`identity_editable`) düzenlenir. Alan yoksa (eski sunucu)
  /// hesabı olan kişi kilitli kalır.
  bool get _identityLocked => _hasAccount && widget.person?.identityEditable != true;

  /// E-posta da kilitlidir; YALNIZ dahili (@ahbu.local) hesapta iletişim e-postası düzenlenebilir
  /// (`account_kind: internal`). Alan yoksa (eski sunucu) hesabı olan kişide e-posta da salt okunurdur.
  bool get _emailLocked =>
      widget.person?.hasAccount == true &&
      widget.person?.isInternalAccount != true;

  /// Kişi kaydı bitti: kişi alanları artık değişmez (yeniden denemede yalnız daire bilgileri ve plaka işlenir).
  bool get _fieldsLocked => _submitting || _personDone;

  /// Telefon ya da e-postadan en az biri zorunlu mu? Kişinin tek ilişkisi "Aile Üyesi" ise (ya da hesaplı kişide,
  /// iletişim bilgisi hesaptan geldiği için) değil.
  bool get _contactRequired {
    if (_hasAccount) return false;
    if (_editing) {
      final relations = widget.person!.relations;
      final onlyFamily =
          relations.isNotEmpty &&
          relations.every((r) => r == ResidencyRelation.familyMember);
      return !onlyFamily;
    }
    return !(_apartment != null && _relation == ResidencyRelation.familyMember);
  }

  /// Düzenlemede "Daire bilgileri" bölümü için kişinin güncel daireleri (tekrarsız).
  late final List<Residency> _editResidencies = () {
    final seen = <int>{};
    return <Residency>[
      for (final r in widget.person?.currentResidencies ?? const <Residency>[])
        if (seen.add(r.apartmentId)) r,
    ];
  }();

  /// "Daire bilgileri"nin ait olduğu daire: ekleme -> seçilen daire; düzenleme -> kişinin TEK güncel dairesi.
  int? get _aptId {
    if (_editing) {
      return _editResidencies.length == 1
          ? _editResidencies.single.apartmentId
          : null;
    }
    return _apartment?.id;
  }

  String get _aptLabel => _editing
      ? _editResidencies.single.fullLabel
      : (_apartment?.fullLabel ?? '');

  /// Daire alanlarını düzenleme yetkisi yalnız yönetimde (kurul üyesi salt okur: bölüm gösterilmez).
  bool get _showAptSection => widget.scope.canWrite && _aptId != null;

  bool get _showMultiAptNote =>
      widget.scope.canWrite && _editing && _editResidencies.length > 1;

  /// Bölüm gösteriliyor ve dairenin mevcut değerleri yüklendi: kayıtta daire güncellemesi değerlendirilir.
  bool get _aptActive =>
      _showAptSection &&
      _aptDraft.initial != null &&
      _aptDraft.initial!.id == _aptId;

  /// E-posta alanının altındaki durum bazlı yardım metni (yalnız ekleme). Sunucu davranışı (people_service.createPerson):
  /// e-posta + daire varsa ve dairenin sakin hesabı yoksa dahili sakin hesabı açılıp giriş bilgisi (kullanıcı adı + PIN)
  /// e-postayla gönderilir; e-posta bu sitede erişimi olan kayıtlı bir hesaba aitse kişi o hesaba bağlanır; aksi
  /// halde (e-posta yok, daire yok ya da dairenin sakin hesabı var) yalnız kayıt tutulur. Hesabın var olup
  /// olmadığı ima edilmez: yalnız kurallar anlatılır.
  static String emailHelp({
    required bool hasEmail,
    required bool hasApartment,
  }) {
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
  static const String phoneHelp =
      'Cep telefonu +90 5XX XXX XX XX biçiminde yazılır. Telefon yalnız iletişim içindir; giriş telefonla yapılmaz.';

  /// Telefon / e-posta zorunluluğunu anlatan kısa not (telefon alanının altında).
  static const String contactRule =
      'Telefon ya da e-postadan en az biri zorunlu (yalnız Aile Üyesi ise ikisi de boş olabilir).';

  @override
  void dispose() {
    ++_aptToken;
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _note.dispose();
    _moveIn.dispose();
    _plates.dispose();
    _aptDraft.dispose();
    super.dispose();
  }

  Future<void> _pickApartment() async {
    final picked = await showApartmentPicker(context, widget.scope);
    if (picked == null || !mounted) return;
    setState(() {
      final changed = _apartment?.id != picked.id;
      _apartment = picked;
      // Bugünle dolu gelir (Borcum görünürlüğü taşınma tarihine bağlıdır); kullanıcı değiştirebilir.
      if (_moveIn.text.trim().isEmpty) {
        _moveIn.text = formatDateField(DateTime.now());
      }
      if (changed) _resetApartmentInfo();
    });
    if (_aptExpanded && _aptDraft.initial == null) unawaited(_loadApartment());
  }

  void _clearApartment() {
    setState(() {
      _apartment = null;
      _resetApartmentInfo();
    });
  }

  /// Başka daire seçildi / seçim kalktı: önceki dairenin taslağı atılır.
  void _resetApartmentInfo() {
    ++_aptToken;
    _aptDraft.clear();
    _aptLoading = false;
    _aptLoadError = null;
    if (_apartment == null) _aptExpanded = false;
  }

  void _toggleApartmentInfo() {
    setState(() => _aptExpanded = !_aptExpanded);
    if (_aptExpanded && _aptDraft.initial == null && !_aptLoading) {
      unawaited(_loadApartment());
    }
  }

  /// Dairenin mevcut değerlerini sunucudan alıp alanlara yazar (bölüm ilk açıldığında).
  Future<void> _loadApartment() async {
    final id = _aptId;
    if (id == null || !mounted) return;
    final token = ++_aptToken;
    setState(() {
      _aptLoading = true;
      _aptLoadError = null;
    });
    try {
      final detail = await widget.scope.authService.getApartment(
        widget.scope.siteCode,
        id,
      );
      if (!mounted || token != _aptToken) return;
      setState(() {
        _aptDraft.load(detail);
        _aptLoading = false;
      });
    } catch (e) {
      if (!mounted || token != _aptToken) return;
      setState(() {
        _aptLoading = false;
        _aptLoadError = crmMessageOf(
          e,
          'Daire bilgileri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  /// Hata iletisini parantez içinde kullanmak için sondaki noktayı atar.
  static String _inline(String message) {
    final text = message.trim();
    return text.endsWith('.') ? text.substring(0, text.length - 1) : text;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    // Daire bilgileri alanları kapalı bölümde çizilmez: doğrulama alan widget'larına değil taslağa dayanır.
    final fieldsOk = validateForm(_formKey);
    final aptMessage = _aptActive ? _aptDraft.validateAll() : null;
    if (!fieldsOk || aptMessage != null) {
      final reveal = aptMessage != null && !_aptExpanded;
      // Özet bildirimi + ilk geçersiz alana kaydırma / odak (kaydırılmış formda hata gizli kalmasın).
      setState(() {
        _error = fieldsOk ? aptMessage : kFixFieldsMessage;
        _existingPersonId = 0;
        if (aptMessage != null) _aptExpanded = true;
      });
      if (reveal) {
        // Bölüm yeni açıldı: alan hataları çizildikten sonra görünür kılınır.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) validateForm(_formKey);
        });
      }
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

    // 1) Kişi
    if (!_personDone) {
      try {
        if (_editing) {
          final fields = _changedFields();
          if (fields.isEmpty) {
            _savedPerson = widget.person;
          } else {
            _savedPerson = await auth.updatePerson(
              siteCode,
              widget.person!.id,
              fields,
            );
            _personChanged = true;
            _dirty = true;
          }
        } else {
          final apartment = _apartment;
          _savedPerson = await auth.createPerson(
            siteCode,
            fullName: _name.text,
            phone: phoneToApi(_phone.text),
            email: _email.text,
            note: _note.text,
            apartmentId: apartment?.id,
            relation: apartment == null ? null : _relation,
            moveInDate: apartment == null ? null : parseDateField(_moveIn.text),
          );
          _created = true;
          _dirty = true;
        }
        _personDone = true;
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
        return;
      }
      if (!mounted) return;
    }

    final person = _savedPerson!;
    final failures = <String>[];

    // 2) Daire bilgileri (yalnız değişen alanlar; "Daireyi Düzenle" ile aynı uç)
    if (_aptActive) {
      final fields = _aptDraft.changedFields();
      if (fields.isNotEmpty) {
        try {
          final result = await auth.updateApartment(
            siteCode,
            _aptDraft.initial!.id,
            fields,
          );
          if (!mounted) return;
          _aptDraft.load(result);
          _aptUpdated = true;
          _extrasChanged = true;
          _dirty = true;
        } catch (e) {
          if (!mounted) return;
          failures.add(
            'daire bilgileri güncellenemedi: ${_inline(crmMessageOf(e, 'İnternet bağlantınızı kontrol edip tekrar deneyin.'))}',
          );
        }
      }
    }

    // 3) Plakalar (eklenen yeni araç olur, çıkarılan pasife alınır)
    if (!await _syncPlates(person.id, failures)) return;

    // Düzenlemede plaka / daire değiştiyse kişi kartı güncel veriyle yenilensin.
    if (_editing && _extrasChanged) {
      try {
        _savedPerson = await auth.getPerson(siteCode, person.id);
        _extrasChanged = false;
      } catch (_) {
        // Yenileme düşerse eldeki kişi döner; kart bir sonraki açılışta güncellenir.
      }
    }

    if (!mounted) return;
    if (failures.isEmpty) {
      popIfCurrent(context, _savedPerson);
      return;
    }
    setState(() {
      _error = _partialMessage(failures);
      _submitting = false;
    });
  }

  /// Plaka alanını kişinin kayıtlı plakalarıyla eşitler. Dönüş false: pencere kapandı (işlem bırakıldı).
  Future<bool> _syncPlates(int personId, List<String> failures) async {
    final auth = widget.scope.authService;
    final siteCode = widget.scope.siteCode;
    final parsed = parsePlateList(_plates.text, preserved: _storedPlates);
    // Ayrıştırılamayan alan (doğrulama zaten engeller; yalnız eski kayıtta 5'ten çok plaka varken DEĞİŞMEMİŞ alan geçer): boş sayılıp
    // kayıtlı plakaların hepsi pasife alınmasın.
    if (!parsed.isValid) return true;
    final desired = <String, PlateEntry>{
      for (final entry in parsed.plates) entry.plate: entry,
    };
    final addFailed = <String>[];
    final removeFailed = <String>[];
    for (final entry in desired.values) {
      if (_plateIds.containsKey(entry.plate)) continue;
      try {
        final vehicle = await auth.createVehicle(
          siteCode,
          personId,
          entry.display,
        );
        if (!mounted) return false;
        _plateIds[entry.plate] = vehicle.id;
        _extrasChanged = true;
        _dirty = true;
      } catch (e) {
        if (!mounted) return false;
        addFailed.add(
          '${entry.display} (${_inline(crmMessageOf(e, 'İnternet bağlantınızı kontrol edip tekrar deneyin.'))})',
        );
      }
    }
    for (final existing in _plateIds.entries.toList()) {
      if (desired.containsKey(existing.key)) continue;
      try {
        await auth.removeVehicle(siteCode, existing.value);
        if (!mounted) return false;
        _plateIds.remove(existing.key);
        _extrasChanged = true;
        _dirty = true;
      } catch (e) {
        if (!mounted) return false;
        removeFailed.add(
          '${existing.key} (${_inline(crmMessageOf(e, 'İnternet bağlantınızı kontrol edip tekrar deneyin.'))})',
        );
      }
    }
    if (addFailed.isNotEmpty) {
      failures.add('plaka eklenemedi: ${addFailed.join(', ')}');
    }
    if (removeFailed.isNotEmpty) {
      failures.add('plaka kaldırılamadı: ${removeFailed.join(', ')}');
    }
    return true;
  }

  /// "Kişi kaydedildi, plaka eklenemedi: 34 ABC 123 (...)." biçiminde adım adım durum iletisi.
  String _partialMessage(List<String> failures) {
    final done = <String>[
      if (_created)
        'kişi kaydedildi'
      else if (_personChanged)
        'kişi bilgileri kaydedildi',
      if (_aptUpdated) 'daire bilgileri güncellendi',
    ];
    final text = [...done, failures.join('; ')].join(', ');
    final sentence = '${text[0].toUpperCase()}${text.substring(1)}.';
    return '$sentence Düzeltip yeniden Kaydet\'e basabilir ya da Vazgeç ile kapatabilirsiniz.';
  }

  /// Vazgeç: kişi (ya da başka bir adım) kaydedildiyse onu döndürür; çağıran listeyi / kartı tazeler.
  void _cancel() {
    if (_submitting) return;
    popIfCurrent(context, _dirty ? _savedPerson : null);
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

  /// Düzenlemede yalnız değişen alanlar (boşaltılan alan `null` gider; sunucu temizler). Kişinin KENDİ hesabında
  /// `full_name` / `phone` / `email` anahtarları HİÇ gönderilmez (değişmemiş değer dahil: sunucu 409
  /// PERSON_HAS_ACCOUNT döner); sitenin yönettiği hesapta ad / telefon gönderilir (sunucu hesaba yazar), dahili hesapta
  /// `email` de serbesttir. Telefon alanına DOKUNULMADIYSA (eski sabit hat / serbest biçimli kayıt dahil) hiç
  /// gönderilmez; değiştiyse `+905061234567` biçiminde gider.
  Map<String, Object?> _changedFields() {
    final initial = widget.person!;
    final fields = <String, Object?>{};
    if (!_identityLocked) {
      final name = _name.text.trim();
      if (name != initial.fullName.trim()) fields['full_name'] = name;
      if (_phone.text.trim() != phoneFieldInitial(initial.phone).trim()) {
        final phone = phoneForSave(_phone.text, stored: initial.phone);
        if (phone != phoneToApi(initial.phone)) fields['phone'] = phone;
      }
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

  /// Plaka alanı doğrulaması: en çok 5 plaka, her biri Türk plakası (il kodu 01-81 + 1-3 harf + 2-4 rakam). Kayıtlı eski plakalar ve
  /// değişmemiş alan engellenmez ([validatePlateList]).
  String? _validatePlates(String? value) => validatePlateList(
    value,
    preserved: _storedPlates,
    initial: _editing ? _activeVehicles.map((v) => v.displayPlate).join(', ') : null,
  );

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final internal = widget.person?.isInternalAccount == true;
    final contactRequired = _contactRequired;
    return PopScope(
      // Gönderim sürerken geri tuşu pencereyi kapatmaz (işlem yarıda kalmış gibi görünmesin). Kişi kaydedildiyse
      // geri tuşu da Vazgeç gibi kaydedilen kişiyle kapanır (çağıran liste tazelensin).
      canPop: !_submitting && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AppDialog(
        title: _editing ? 'Kişiyi Düzenle' : 'Kişi Ekle',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: _editing ? Icons.edit_rounded : Icons.person_add_alt_1_rounded,
        actions: [
          TextButton(
            onPressed: _submitting ? null : _cancel,
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
              ] else if (_hasAccount) ...[
                // Sitenin yönettiği hesap: ad / telefon buradan değişir ve kişinin hesabına yazılır.
                InlineNotice(
                  tone: AppTone.info,
                  icon: Icons.info_outline_rounded,
                  message: internal
                      ? 'Bu kişinin hesabı var. Ad ve telefonu değiştirirseniz kişinin hesabında da güncellenir.'
                      : 'Bu kişinin hesabı var. Ad ve telefonu değiştirirseniz kişinin hesabında da güncellenir. E-posta kişinin giriş adresidir; kişinin kendi profilinden değişir.',
                ),
                const SizedBox(height: AppSpace.md),
              ],
              TextFormField(
                key: const ValueKey<String>('person_name'),
                controller: _name,
                enabled: !_fieldsLocked,
                readOnly: _identityLocked,
                textCapitalization: TextCapitalization.words,
                maxLength: PersonFormDialog.maxNameLength,
                decoration: const InputDecoration(
                  labelText: 'Ad Soyad *',
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
                enabled: !_fieldsLocked,
                readOnly: _identityLocked,
                keyboardType: TextInputType.phone,
                inputFormatters: _identityLocked
                    ? null
                    : const [PhoneInputFormatter()],
                decoration: InputDecoration(
                  labelText: contactRequired
                      ? 'Telefon *'
                      : 'Telefon (isteğe bağlı)',
                  prefixIcon: const Icon(Icons.phone_rounded),
                  hintText: _identityLocked ? null : phoneFieldHint,
                  helperText: _identityLocked
                      ? null
                      : (contactRequired
                            ? '$contactRule $phoneHelp'
                            : phoneHelp),
                  helperMaxLines: 4,
                ),
                validator: (value) {
                  if (_identityLocked) return null;
                  // Düzenlemede dokunulmamış eski kayıt (sabit hat / serbest biçim) kaydetmeyi engellemez.
                  final format = _editing
                      ? validatePhoneInput(value, stored: widget.person?.phone)
                      : validatePhoneField(value);
                  if (format != null) return format;
                  if (_contactRequired &&
                      phoneToApi(value) == null &&
                      _email.text.trim().isEmpty) {
                    return PersonFormDialog.contactRequiredMessage;
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('person_email'),
                controller: _email,
                enabled: !_fieldsLocked,
                readOnly: _emailLocked,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: _editing ? null : (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: contactRequired
                      ? 'E-posta *'
                      : 'E-posta (isteğe bağlı)',
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
                  if (text.isEmpty) {
                    return _contactRequired && phoneToApi(_phone.text) == null
                        ? PersonFormDialog.contactRequiredMessage
                        : null;
                  }
                  return _emailPattern.hasMatch(text)
                      ? null
                      : 'Geçerli bir e-posta girin.';
                },
              ),
              if (!_editing) ...[
                const SizedBox(height: AppSpace.md),
                CrmPickerField(
                  key: const ValueKey<String>('person_apartment'),
                  label: 'Daire (blok + daire no, isteğe bağlı)',
                  icon: Icons.apartment_rounded,
                  value: _apartment?.fullLabel,
                  placeholder: 'Daire seçmek için dokunun',
                  enabled: !_fieldsLocked,
                  onTap: _pickApartment,
                  onClear: _clearApartment,
                ),
                if (_apartment != null) ...[
                  const SizedBox(height: AppSpace.md),
                  DropdownButtonFormField<ResidencyRelation>(
                    key: const ValueKey<String>('person_relation'),
                    isExpanded: true,
                    initialValue: _relation,
                    dropdownColor: p.surface,
                    style: th.bodyLarge?.copyWith(color: p.text),
                    hint: const Text('Seçin'),
                    decoration: const InputDecoration(
                      labelText: 'İlişki *',
                      helperText: 'Borcun hangi hesaba yazılacağını belirler.',
                      helperMaxLines: 2,
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
                    validator: (value) => value == null
                        ? 'İlişkiyi seçin (Malik, Kiracı, Aile Üyesi ya da Sakin).'
                        : null,
                    onChanged: _fieldsLocked
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
                    enabled: !_fieldsLocked,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [DateInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Taşınma (giriş) tarihi *',
                      hintText: 'GG.AA.YYYY',
                      helperText: 'Borcum görünürlüğü bu tarihe bağlıdır.',
                      helperMaxLines: 2,
                      prefixIcon: Icon(Icons.event_rounded),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Taşınma (giriş) tarihi zorunlu.';
                      }
                      return validateDateField(value);
                    },
                  ),
                ],
              ],
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('person_plates'),
                controller: _plates,
                enabled: !_submitting,
                inputFormatters: [PlateListInputFormatter(preserved: _storedPlates)],
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Plaka (isteğe bağlı)',
                  hintText: '34 ABC 123, 06 XY 789',
                  helperText: 'Birden çok plaka virgülle ayrılır (en çok 5).',
                  helperMaxLines: 2,
                  prefixIcon: Icon(Icons.directions_car_rounded),
                ),
                validator: _validatePlates,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('person_note'),
                controller: _note,
                enabled: !_fieldsLocked,
                minLines: 2,
                maxLines: 4,
                maxLength: PersonFormDialog.maxNoteLength,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                  alignLabelWithHint: true,
                ),
              ),
              if (_showAptSection) ...[
                const SizedBox(height: AppSpace.md),
                ApartmentInfoSection(
                  key: const ValueKey<String>('person_apt_section'),
                  draft: _aptDraft,
                  apartmentLabel: _aptLabel,
                  expanded: _aptExpanded,
                  enabled: !_submitting,
                  loading: _aptLoading,
                  loadError: _aptLoadError,
                  onRetry: _loadApartment,
                  onToggle: _toggleApartmentInfo,
                  onPartyChanged: (party) =>
                      setState(() => _aptDraft.party = party),
                ),
              ] else if (_showMultiAptNote) ...[
                const SizedBox(height: AppSpace.md),
                const InlineNotice(
                  tone: AppTone.info,
                  icon: Icons.info_outline_rounded,
                  message:
                      'Bu kişinin birden çok dairesi var; daire bilgileri Daireler ekranından düzenlenir.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
