// Firma ve Sözleşme Takibi (`contracts`) modelleri.
//
// Uçlar: `/manager/sites/:siteCode/contract-vendors` ve `/manager/sites/:siteCode/contracts` (+ `/summary`).
// Kurallar (diğer modüllerle aynı): alan yok / bozuk ise güvenli varsayılan (uygulama çökmez); bilinmeyen sabit
// değerler enum'larda en zararsız değere düşer; DATE alanları (`YYYY-AA-GG`) takvim günü olarak okunur (saat dilimi
// kayması günü değiştirmez); zaman damgaları evrensel an (UTC) okunur ve ekranda İstanbul saatiyle gösterilir.
// Tutar sunucudan metin ("1250.00") gelir ve TAMSAYI KURUŞ olarak tutulur (kayan nokta yok).
// Firma adı / yetkili / telefon / e-posta / not HİÇBİR YERDE günlüğe yazılmaz.
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/document_models.dart'
    show documentInstant;
import 'package:site_kapi_kontrol/models/vehicle_record.dart'
    show crmDate, crmDateParam, crmInt, crmIntOrNull, crmText;

/// Serbest metin üst sınırları (kod noktası; sunucu `contracts_common.js` ile aynı). Aşımda sunucu `INVALID_FIELD` döner.
const int kVendorNameMax = 120;
const int kVendorContactMax = 120;
const int kVendorPhoneMax = 32;
const int kVendorEmailMax = 254;
const int kVendorTaxNoMax = 20;
const int kVendorNoteMax = 1000;
const int kContractTitleMax = 160;
const int kContractNoteMax = 2000;

/// Gün alanlarının aralıkları (sözleşme: fesih bildirimi 0..365, hatırlatma 0..180).
const int kContractNoticeDaysMax = 365;
const int kContractRemindDaysMax = 180;

String _text(Object? raw) => raw?.toString().trim() ?? '';

bool _flag(Object? raw, {bool fallback = false}) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  final text = raw?.toString().trim().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

/// Firma / sözleşme kategorisi (sunucu `category`). Bilinmeyen değer [diger] olur.
enum ContractCategory {
  asansor('asansor', 'Asansör'),
  guvenlik('guvenlik', 'Güvenlik'),
  temizlik('temizlik', 'Temizlik'),
  bahce('bahce', 'Bahçe'),
  havuz('havuz', 'Havuz'),
  teknikBakim('teknik_bakim', 'Teknik Bakım'),
  yazilim('yazilim', 'Yazılım'),
  sigorta('sigorta', 'Sigorta'),
  diger('diger', 'Diğer');

  const ContractCategory(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ContractCategory fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final category in values) {
      if (category.apiValue == normalized) return category;
    }
    return ContractCategory.diger;
  }

  /// Bilinmeyen / boş değerde null (süzgeç parametresi için).
  static ContractCategory? tryParse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final category in values) {
      if (category.apiValue == normalized) return category;
    }
    return null;
  }
}

/// Ödeme dönemi (sunucu `period`; null = belirtilmedi).
enum ContractPeriod {
  aylik('aylik', 'Aylık'),
  yillik('yillik', 'Yıllık'),
  tekSefer('tek_sefer', 'Tek seferlik'),
  diger('diger', 'Diğer');

  const ContractPeriod(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Boş ya da bilinmeyen değerde null.
  static ContractPeriod? fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final period in values) {
      if (period.apiValue == normalized) return period;
    }
    return null;
  }
}

/// Kayıtlı durum (sunucu `status`): yalnız fesih yazılır; bitiş tarihi geçince de `aktif` kalır ([ContractState]
/// hesaplanmış durumu verir). Bilinmeyen değer [aktif] sayılır.
enum ContractStatus {
  aktif('aktif'),
  feshedildi('feshedildi');

  const ContractStatus(this.apiValue);

  final String apiValue;

  static ContractStatus fromApi(Object? value) =>
      value?.toString().trim().toLowerCase() == 'feshedildi'
      ? ContractStatus.feshedildi
      : ContractStatus.aktif;
}

/// Sunucunun hesapladığı durum (sunucu `state`): yürürlükte / bitişi yaklaşıyor / süresi doldu / feshedildi.
enum ContractState {
  aktif('aktif', 'Yürürlükte'),
  yaklasiyor('yaklasiyor', 'Bitişi yaklaşıyor'),
  sonaErdi('sona_erdi', 'Süresi doldu'),
  feshedildi('feshedildi', 'Feshedildi'),
  unknown('', 'Durum bilinmiyor');

  const ContractState(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Süzgeçte listelenen bilinen durumlar (sunucu sırası).
  static const List<ContractState> known = <ContractState>[
    aktif,
    yaklasiyor,
    sonaErdi,
    feshedildi,
  ];

  static ContractState fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final state in values) {
      if (state.apiValue.isNotEmpty && state.apiValue == normalized) {
        return state;
      }
    }
    return ContractState.unknown;
  }
}

// --- Tutar --------------------------------------------------------------------------------------

/// Sunucu tutarı ("1250.00", "1250", 1250.5) -> kuruş. Boş / bozuk değerde null. Kayan nokta ile hesap yapılmaz:
/// sayı gelirse önce iki ondalıklı metne çevrilir. İkiden fazla ondalık basamak KESİLİR (sunucu NUMERIC(.., 2)).
int? contractAmountMinor(Object? raw) {
  if (raw == null) return null;
  String text;
  if (raw is int) {
    text = '$raw';
  } else if (raw is double) {
    if (!raw.isFinite) return null;
    text = raw.toStringAsFixed(2);
  } else {
    text = raw.toString().trim();
  }
  final match = RegExp(r'^(-?)(\d+)(?:[.,](\d+))?$').firstMatch(text);
  if (match == null) return null;
  final whole = match.group(2)!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (whole.length > 13) return null;
  final fraction = (match.group(3) ?? '').padRight(2, '0').substring(0, 2);
  final minor = int.parse(whole) * 100 + int.parse(fraction);
  return match.group(1) == '-' ? -minor : minor;
}

/// Kuruş -> sunucu metni ("1250.00"; ondalık ayırıcı nokta, binlik yok).
String contractAmountWire(int minor) {
  final negative = minor < 0;
  final magnitude = minor.abs();
  final whole = magnitude ~/ 100;
  final fraction = (magnitude % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole.$fraction';
}

// --- Firma --------------------------------------------------------------------------------------

/// Firma (`Vendor`). Yanıt `{vendor: {...}}` ya da düz nesne olabilir.
@immutable
class ContractVendor {
  const ContractVendor({
    required this.id,
    this.name = '',
    this.category = ContractCategory.diger,
    this.contactName,
    this.phone,
    this.email,
    this.taxNo,
    this.note,
    this.isActive = true,
    this.contractCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final ContractCategory category;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? taxNo;
  final String? note;
  final bool isActive;
  final int contractCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Ad boşsa yer tutucu.
  String get displayName => name.trim().isEmpty ? 'İsimsiz firma' : name.trim();

  factory ContractVendor.fromJson(Map<String, dynamic> raw) {
    final inner = raw['vendor'] ?? raw['item'];
    final json = inner is Map ? Map<String, dynamic>.from(inner) : raw;
    final count = crmIntOrNull(json['contract_count']);
    return ContractVendor(
      id: crmInt(json['id']),
      name: _text(json['name']),
      category: ContractCategory.fromApi(json['category']),
      contactName: crmText(json['contact_name']),
      phone: crmText(json['phone']),
      email: crmText(json['email']),
      taxNo: crmText(json['tax_no']),
      note: crmText(json['note']),
      isActive: _flag(json['is_active'], fallback: true),
      contractCount: count == null || count < 0 ? 0 : count,
      createdAt: documentInstant(json['created_at']),
      updatedAt: documentInstant(json['updated_at']),
    );
  }

  /// `{items: [...]}` ya da düz liste; kimliği geçersiz öğe atlanır.
  static List<ContractVendor> listFrom(Object? raw) {
    final list = raw is Map ? raw['items'] : raw;
    if (list is! List) return const <ContractVendor>[];
    return List<ContractVendor>.unmodifiable(<ContractVendor>[
      for (final item in list.whereType<Map>())
        if (crmInt(item['id']) > 0)
          ContractVendor.fromJson(Map<String, dynamic>.from(item)),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is ContractVendor &&
      other.id == id &&
      other.name == name &&
      other.category == category &&
      other.contactName == contactName &&
      other.phone == phone &&
      other.email == email &&
      other.taxNo == taxNo &&
      other.note == note &&
      other.isActive == isActive &&
      other.contractCount == contractCount;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    category,
    contactName,
    phone,
    email,
    taxNo,
    note,
    isActive,
    contractCount,
  );
}

/// Firma formunun gövdesi (`POST` / `PATCH .../contract-vendors`).
@immutable
class ContractVendorDraft {
  const ContractVendorDraft({
    required this.name,
    required this.category,
    this.contactName = '',
    this.phone = '',
    this.email = '',
    this.taxNo = '',
    this.note = '',
  });

  final String name;
  final ContractCategory category;
  final String contactName;
  final String phone;
  final String email;
  final String taxNo;
  final String note;

  /// Yeni firma: boş isteğe bağlı alanlar gönderilmez.
  Map<String, dynamic> toCreateJson() {
    final contact = contactName.trim();
    final phone = this.phone.trim();
    final email = this.email.trim();
    final tax = taxNo.trim();
    final note = this.note.trim();
    return <String, dynamic>{
      'name': name.trim(),
      'category': category.apiValue,
      if (contact.isNotEmpty) 'contact_name': contact,
      if (phone.isNotEmpty) 'phone': phone,
      if (email.isNotEmpty) 'email': email,
      if (tax.isNotEmpty) 'tax_no': tax,
      if (note.isNotEmpty) 'note': note,
    };
  }

  /// Düzenleme: YALNIZ değişen alanlar gönderilir; temizlenen isteğe bağlı alan `null` gider. Değişiklik yoksa boş.
  Map<String, dynamic> toPatchJson(ContractVendor original) {
    String? optional(String value) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final body = <String, dynamic>{};
    final name = this.name.trim();
    if (name != original.name.trim()) body['name'] = name;
    if (category != original.category) body['category'] = category.apiValue;
    void diff(String key, String value, String? before) {
      final next = optional(value);
      if (next != optional(before ?? '')) body[key] = next;
    }

    diff('contact_name', contactName, original.contactName);
    diff('phone', phone, original.phone);
    diff('email', email, original.email);
    diff('tax_no', taxNo, original.taxNo);
    diff('note', note, original.note);
    return body;
  }
}

// --- Sözleşme -----------------------------------------------------------------------------------

/// Sözleşme (`Contract`). Yanıt `{contract: {...}}` ya da düz nesne olabilir.
@immutable
class Contract {
  const Contract({
    required this.id,
    this.vendorId = 0,
    this.vendorName = '',
    this.title = '',
    this.category = ContractCategory.diger,
    this.startDate,
    this.endDate,
    this.noticeDays = 0,
    this.remindBeforeDays = 0,
    this.amountMinor,
    this.currency = 'TRY',
    this.period,
    this.autoRenew = false,
    this.status = ContractStatus.aktif,
    this.state = ContractState.unknown,
    this.daysLeft,
    this.noticeDeadline,
    this.terminatedAt,
    this.note,
    this.createdByName,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int vendorId;
  final String vendorName;
  final String title;
  final ContractCategory category;

  /// Takvim günleri (saat yok).
  final DateTime? startDate;
  final DateTime? endDate;
  final int noticeDays;
  final int remindBeforeDays;

  /// Tutar (kuruş); belirtilmemişse null.
  final int? amountMinor;
  final String currency;
  final ContractPeriod? period;
  final bool autoRenew;
  final ContractStatus status;
  final ContractState state;

  /// Bitişe kalan gün (geçmişte negatif); süresiz sözleşmede null.
  final int? daysLeft;

  /// Otomatik yenilenen sözleşmede fesih bildiriminin son günü (takvim günü).
  final DateTime? noticeDeadline;
  final DateTime? terminatedAt;
  final String? note;
  final String? createdByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isTerminated =>
      status == ContractStatus.feshedildi || state == ContractState.feshedildi;

  /// Süresiz (bitiş tarihi yok).
  bool get isOpenEnded => endDate == null;

  String get displayTitle => title.trim().isEmpty ? 'Başlıksız sözleşme' : title.trim();

  String get displayVendor =>
      vendorName.trim().isEmpty ? 'İsimsiz firma' : vendorName.trim();

  factory Contract.fromJson(Map<String, dynamic> raw) {
    final inner = raw['contract'] ?? raw['item'];
    final json = inner is Map ? Map<String, dynamic>.from(inner) : raw;
    final notice = crmIntOrNull(json['notice_days']);
    final remind = crmIntOrNull(json['remind_before_days']);
    final currency = _text(json['currency']);
    return Contract(
      id: crmInt(json['id']),
      vendorId: crmInt(json['vendor_id']),
      vendorName: _text(json['vendor_name']),
      title: _text(json['title']),
      category: ContractCategory.fromApi(json['category']),
      startDate: crmDate(json['start_date']),
      endDate: crmDate(json['end_date']),
      noticeDays: notice == null || notice < 0 ? 0 : notice,
      remindBeforeDays: remind == null || remind < 0 ? 0 : remind,
      amountMinor: contractAmountMinor(json['amount']),
      currency: currency.isEmpty ? 'TRY' : currency.toUpperCase(),
      period: ContractPeriod.fromApi(json['period']),
      autoRenew: _flag(json['auto_renew']),
      status: ContractStatus.fromApi(json['status']),
      state: ContractState.fromApi(json['state']),
      daysLeft: crmIntOrNull(json['days_left']),
      noticeDeadline: crmDate(json['notice_deadline']),
      terminatedAt: documentInstant(json['terminated_at']),
      note: crmText(json['note']),
      createdByName: crmText(json['created_by_name']),
      createdAt: documentInstant(json['created_at']),
      updatedAt: documentInstant(json['updated_at']),
    );
  }

  static List<Contract> listFrom(Object? raw) {
    if (raw is! List) return const <Contract>[];
    return List<Contract>.unmodifiable(<Contract>[
      for (final item in raw.whereType<Map>())
        if (crmInt(item['id']) > 0)
          Contract.fromJson(Map<String, dynamic>.from(item)),
    ]);
  }
}

/// `GET .../contracts`: `{items, next_cursor}`. Sıra `end_date` artan (bitişsizler sonda), sonra `id`; bu yüzden
/// sayfalama YALNIZ opak `cursor` iledir (sunucu `before_id` kabul etmez: 400). Son sayfada `next_cursor` null.
@immutable
class ContractPage {
  const ContractPage({this.items = const <Contract>[], this.nextCursor});

  final List<Contract> items;

  /// Sonraki sayfanın opak imleci (sonraki istekte `cursor` olarak aynen gönderilir); son sayfada null.
  final String? nextCursor;

  factory ContractPage.fromJson(Map<String, dynamic> json) {
    final raw = json['next_cursor'];
    final cursor = raw == null ? '' : raw.toString().trim();
    return ContractPage(
      items: Contract.listFrom(json['items']),
      nextCursor: cursor.isEmpty ? null : cursor,
    );
  }
}

/// `GET .../contracts/summary`: `{active, expiring_soon, expired, terminated}` (ya da `{summary: {...}}`).
@immutable
class ContractSummary {
  const ContractSummary({
    this.active = 0,
    this.expiringSoon = 0,
    this.expired = 0,
    this.terminated = 0,
  });

  final int active;
  final int expiringSoon;
  final int expired;
  final int terminated;

  /// [state] durumuna düşen sayı (bilinmeyende 0).
  int countOf(ContractState state) => switch (state) {
    ContractState.aktif => active,
    ContractState.yaklasiyor => expiringSoon,
    ContractState.sonaErdi => expired,
    ContractState.feshedildi => terminated,
    ContractState.unknown => 0,
  };

  factory ContractSummary.fromJson(Map<String, dynamic> raw) {
    final inner = raw['summary'];
    final json = inner is Map ? Map<String, dynamic>.from(inner) : raw;
    int count(String key) {
      final value = crmIntOrNull(json[key]);
      return value == null || value < 0 ? 0 : value;
    }

    return ContractSummary(
      active: count('active'),
      expiringSoon: count('expiring_soon'),
      expired: count('expired'),
      terminated: count('terminated'),
    );
  }
}

/// Sözleşme formunun gövdesi (`POST` / `PATCH .../contracts`).
@immutable
class ContractDraft {
  const ContractDraft({
    required this.vendorId,
    required this.title,
    required this.category,
    required this.startDate,
    this.endDate,
    required this.noticeDays,
    required this.remindBeforeDays,
    this.amountMinor,
    this.period,
    this.autoRenew = false,
    this.note = '',
  });

  final int vendorId;
  final String title;
  final ContractCategory category;
  final DateTime startDate;
  final DateTime? endDate;
  final int noticeDays;
  final int remindBeforeDays;
  final int? amountMinor;
  final ContractPeriod? period;
  final bool autoRenew;
  final String note;

  /// Yeni sözleşme: boş isteğe bağlı alanlar gönderilmez.
  Map<String, dynamic> toCreateJson() {
    final note = this.note.trim();
    final end = endDate;
    final amount = amountMinor;
    final period = this.period;
    return <String, dynamic>{
      'vendor_id': vendorId,
      'title': title.trim(),
      'category': category.apiValue,
      'start_date': crmDateParam(startDate),
      if (end != null) 'end_date': crmDateParam(end),
      'notice_days': noticeDays,
      'remind_before_days': remindBeforeDays,
      if (amount != null) 'amount': contractAmountWire(amount),
      if (period != null) 'period': period.apiValue,
      'auto_renew': autoRenew,
      if (note.isNotEmpty) 'note': note,
    };
  }

  /// Düzenleme: YALNIZ değişen alanlar gönderilir; temizlenen isteğe bağlı alan (bitiş, tutar, dönem, not) `null`
  /// gider. Değişiklik yoksa boş harita.
  Map<String, dynamic> toPatchJson(Contract original) {
    final body = <String, dynamic>{};
    if (vendorId != original.vendorId) body['vendor_id'] = vendorId;
    final title = this.title.trim();
    if (title != original.title.trim()) body['title'] = title;
    if (category != original.category) body['category'] = category.apiValue;
    final start = crmDateParam(startDate);
    final originalStart = original.startDate;
    if (originalStart == null || start != crmDateParam(originalStart)) {
      body['start_date'] = start;
    }
    final end = endDate == null ? null : crmDateParam(endDate!);
    final originalEnd = original.endDate == null ? null : crmDateParam(original.endDate!);
    if (end != originalEnd) body['end_date'] = end;
    if (noticeDays != original.noticeDays) body['notice_days'] = noticeDays;
    if (remindBeforeDays != original.remindBeforeDays) {
      body['remind_before_days'] = remindBeforeDays;
    }
    if (amountMinor != original.amountMinor) {
      body['amount'] = amountMinor == null ? null : contractAmountWire(amountMinor!);
    }
    if (period != original.period) body['period'] = period?.apiValue;
    if (autoRenew != original.autoRenew) body['auto_renew'] = autoRenew;
    final note = this.note.trim();
    final originalNote = original.note?.trim() ?? '';
    if (note != originalNote) body['note'] = note.isEmpty ? null : note;
    return body;
  }
}

// --- Menü / ekran kapısı ------------------------------------------------------------------------

/// Sitedeki erişim türü: yönetici (yazar), görevli ve yönetim kurulu (salt okur).
enum ContractSiteAccess { manager, staff, board }

/// "Sözleşmeler" ekranında listelenen site ve erişim türü.
@immutable
class ContractSite {
  const ContractSite({
    required this.code,
    required this.name,
    this.access = ContractSiteAccess.manager,
  });

  final int code;
  final String name;
  final ContractSiteAccess access;

  /// Yalnız yönetici yazar (kurul ve görevli salt okur).
  bool get canWrite => access == ContractSiteAccess.manager;

  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();

  @override
  bool operator ==(Object other) =>
      other is ContractSite &&
      other.code == code &&
      other.name == name &&
      other.access == access;

  @override
  int get hashCode => Object.hash(code, name, access);
}

// --- Denetim kaydı ------------------------------------------------------------------------------

/// Firma ve Sözleşme Takibi denetim eylemlerinin Türkçe başlığı; bilinmeyen eylemde null (zincirdeki sonraki üretici
/// dener). [details]: sunucunun `fields` / `is_active` / `from` / `to` alanları (ad, telefon, tutar, not YAZILMAZ).
String? contractActionLabel(String action, [Map<String, dynamic> details = const <String, dynamic>{}]) {
  switch (action) {
    case 'contract_vendor.created':
      return 'Firma eklendi';
    case 'contract_vendor.updated':
      final active = details['is_active'];
      if (active == false) return 'Firma pasife alındı';
      if (active == true) return 'Firma etkinleştirildi';
      return 'Firma güncellendi';
    case 'contract.created':
      return 'Sözleşme eklendi';
    case 'contract.updated':
      final to = details['to'];
      if (to == 'feshedildi') return 'Sözleşme feshedildi';
      if (to == 'aktif') return 'Sözleşme yeniden etkinleştirildi';
      return 'Sözleşme güncellendi';
  }
  return null;
}
