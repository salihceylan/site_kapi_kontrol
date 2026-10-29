// Ödeme bilgisi modelleri (Dalga 2 / 2A; sözleşme: docs/PLATFORM_FINANS_ODEME.md).

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fallback : fallback);

/// Sakin ucu `GET /app/my-finance/payment-info` kalemi. TUTAR TAŞIMAZ (Öde sayfası /app/my-finance bakiyesini kullanır).
class PaymentInfoItem {
  const PaymentInfoItem({
    required this.siteCode,
    required this.apartmentId,
    this.siteName = '',
    this.configured = false,
    this.payeeName,
    this.iban,
    this.ibanDisplay,
    this.reference,
    this.referenceShort,
    this.periodLabel,
    this.detailsChangedAt,
    this.noticesEnabled = false,
    this.onlinePaymentAvailable = false,
  });

  factory PaymentInfoItem.fromJson(Map<String, dynamic> json) => PaymentInfoItem(
    onlinePaymentAvailable: json['online_payment_available'] == true,
    siteCode: _int(json['site_code']),
    apartmentId: _int(json['apartment_id']),
    siteName: _str(json['site_name']) ?? '',
    configured: json['configured'] == true,
    payeeName: _str(json['payee_name']),
    iban: _str(json['iban']),
    ibanDisplay: _str(json['iban_display']),
    reference: _str(json['reference']),
    referenceShort: _str(json['reference_short']),
    periodLabel: _str(json['period_label']),
    detailsChangedAt: DateTime.tryParse(_str(json['details_changed_at']) ?? ''),
    noticesEnabled: json['notices_enabled'] == true,
  );

  final int siteCode;
  final int apartmentId;
  final String siteName;

  /// false: site yönetimi ödeme bilgisini (önek + banka hesabı) henüz girmedi.
  final bool configured;
  final String? payeeName;

  /// Boşluksuz IBAN (kopyalama için).
  final String? iban;

  /// 4'lü gruplu gösterim.
  final String? ibanDisplay;

  /// 'GUL-A2-1026'.
  final String? reference;

  /// 'GUL-A2' (düzenli ödeme talimatı için).
  final String? referenceShort;
  final String? periodLabel;

  /// IBAN en son ne zaman değişti (yalnız iki sürüm farklıysa dolu).
  final DateTime? detailsChangedAt;

  /// Dekont yükleme anahtarı (2B); false iken "Dekont yükle" gösterilmez.
  final bool noticesEnabled;

  /// Site bağlantısı CANLI + sınanmış + sürücü ETKİN ise true; yalnız o zaman "Online Öde" çizilir (eski sunucuda alan yok => false).
  final bool onlinePaymentAvailable;

  /// IBAN son [days] günde değiştiyse true.
  bool changedRecently(DateTime now, {int days = 14}) {
    final at = detailsChangedAt;
    return at != null && now.difference(at).inDays < days && !at.isAfter(now.add(const Duration(days: 1)));
  }
}

class PaymentInfo {
  const PaymentInfo({required this.items});

  factory PaymentInfo.fromJson(Map<String, dynamic> json) => PaymentInfo(
    items: [
      for (final raw in (json['items'] is List ? json['items'] as List : const <Object?>[]))
        if (raw is Map) PaymentInfoItem.fromJson(Map<String, dynamic>.from(raw)),
    ],
  );

  final List<PaymentInfoItem> items;

  PaymentInfoItem? forApartment(int apartmentId) {
    for (final item in items) {
      if (item.apartmentId == apartmentId) return item;
    }
    return null;
  }
}

/// Yönetici ayarlarındaki banka hesabı (IBAN yalnız yönetici/süper için açık; kurul yalnız maskeli görür).
class PaymentBankAccount {
  const PaymentBankAccount({required this.id, required this.name, this.isActive = true, this.iban, this.ibanDisplay, this.payeeName});

  factory PaymentBankAccount.fromJson(Map<String, dynamic> json) => PaymentBankAccount(
    id: _int(json['id']),
    name: _str(json['name']) ?? '',
    isActive: json['is_active'] != false,
    iban: _str(json['iban']),
    ibanDisplay: _str(json['iban_display']),
    payeeName: _str(json['payee_name']),
  );

  final int id;
  final String name;
  final bool isActive;
  final String? iban;
  final String? ibanDisplay;
  final String? payeeName;

  bool get hasIban => ibanDisplay != null;
}

class PaymentSettings {
  const PaymentSettings({
    this.prefix,
    this.aliases = const <String>[],
    this.suggestedPrefix,
    this.residentAccountId,
    this.bankAccounts = const <PaymentBankAccount>[],
    this.noticesEnabled = false,
    this.settingsVersion = 1,
    this.sampleReference,
  });

  factory PaymentSettings.fromJson(Map<String, dynamic> json) {
    final resident = json['resident_account'];
    return PaymentSettings(
      prefix: _str(json['prefix']),
      aliases: [
        for (final a in (json['aliases'] is List ? json['aliases'] as List : const <Object?>[]))
          if (a is String) a,
      ],
      suggestedPrefix: _str(json['suggested_prefix']),
      residentAccountId: resident is Map ? _int(resident['id']) : null,
      bankAccounts: [
        for (final raw in (json['bank_accounts'] is List ? json['bank_accounts'] as List : const <Object?>[]))
          if (raw is Map) PaymentBankAccount.fromJson(Map<String, dynamic>.from(raw)),
      ],
      noticesEnabled: json['notices_enabled'] == true,
      settingsVersion: _int(json['settings_version'], 1),
      sampleReference: _str(json['sample_reference']),
    );
  }

  final String? prefix;
  final List<String> aliases;
  final String? suggestedPrefix;
  final int? residentAccountId;
  final List<PaymentBankAccount> bankAccounts;
  final bool noticesEnabled;
  final int settingsVersion;
  final String? sampleReference;
}

/// TR IBAN denetimi (istemci tarafı, canlı geri bildirim için; sunucu yine denetler). Geçerliyse boşluksuz büyük harfli IBAN, değilse null.
String? parseTrIban(String input) {
  final n = input.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
  if (!RegExp(r'^TR[0-9]{24}$').hasMatch(n)) return null;
  final moved = n.substring(4) + n.substring(0, 4);
  var remainder = 0;
  for (final unit in moved.codeUnits) {
    final digits = unit >= 65 && unit <= 90 ? (unit - 55).toString() : String.fromCharCode(unit);
    for (final d in digits.codeUnits) {
      remainder = (remainder * 10 + (d - 48)) % 97;
    }
  }
  return remainder == 1 ? n : null;
}

/// 'TR33 0006 1005 ...' gruplu gösterim.
String groupIban(String iban) {
  final n = iban.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  final buffer = StringBuffer();
  for (var i = 0; i < n.length; i += 4) {
    if (i > 0) buffer.write(' ');
    buffer.write(n.substring(i, i + 4 > n.length ? n.length : i + 4));
  }
  return buffer.toString();
}
