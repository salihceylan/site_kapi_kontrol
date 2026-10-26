import 'package:flutter/foundation.dart';

/// İki kasa (Platform Finans: docs/PLATFORM_FINANS_KASALAR.md) çekirdek tipleri ve AD SABİTLERİ.
///
/// Site finansı iki mantıksal kasada izlenir:
/// - `operating` = "İşletme Projesi (Aidat) Hesabı": aidat ve işletme giderleri; borcu dairede oturan öder.
/// - `capital` = "Yatırım ve Demirbaş (Fon) Hesabı": yatırım, demirbaş, büyük onarım katkı payları; borcu malik öder.
///
/// Kullanıcı kararı (2026-10-26): arayüzde kasalar TAM bu adlarla anılır (ev sahibi / kiracı daire hesaplarıyla ve nakit /
/// banka hesaplarıyla karışmasın); yer dar olan yerde ("Aidat Hesabı" / "Fon Hesabı") kısa ad kullanılır. Adların TEK
/// kaynağı bu dosyadır; ekranlar metni elle yazmaz.
///
/// Bu dosya başka model dosyalarını İÇE AKTARMAZ (finance.dart bunu içe aktarır; döngü olmasın diye kuruş okuyucu burada
/// ayrıca durur). Para tamsayı KURUŞTUR; bozuk tutar sessizce 0 yapılmaz: ek (isteğe bağlı) kırılımlar okunamazsa null olur
/// ve ekran o kırılımı hiç çizmez.

/// "İşletme Projesi (Aidat) Hesabı".
const String kFundOperatingName = 'İşletme Projesi (Aidat) Hesabı';

/// "Yatırım ve Demirbaş (Fon) Hesabı".
const String kFundCapitalName = 'Yatırım ve Demirbaş (Fon) Hesabı';

/// Kısa ad (yer dar olan yerde): "Aidat Hesabı".
const String kFundOperatingShortName = 'Aidat Hesabı';

/// Kısa ad (yer dar olan yerde): "Fon Hesabı".
const String kFundCapitalShortName = 'Fon Hesabı';

/// Tahsilat formunda kasa seçilmediğinde (kısıtsız): en eski vadeden başlayarak dağıtılır.
const String kFundAutoName = 'Otomatik (en eski vade önce)';

/// Kasa kodu (`operating` | `capital`).
enum FinanceFund {
  operating('operating', kFundOperatingName, kFundOperatingShortName, 'dairede oturan öder (kiracı varsa kiracı)'),
  capital('capital', kFundCapitalName, kFundCapitalShortName, 'malik öder');

  const FinanceFund(this.apiValue, this.label, this.shortLabel, this.payerNote);

  final String apiValue;

  /// Tam ad ("İşletme Projesi (Aidat) Hesabı"): formlar, kart başlıkları, açıklamalar.
  final String label;

  /// Kısa ad ("Aidat Hesabı"): rozetler ve dar listeler.
  final String shortLabel;

  /// Borcu kimin ödediği ("dairede oturan öder (kiracı varsa kiracı)" / "malik öder").
  final String payerNote;

  /// Seçim satırı metni: "İşletme Projesi (Aidat) Hesabı — dairede oturan öder (kiracı varsa kiracı)".
  String get choiceText => '$label — $payerNote';

  /// Bilinmeyen / eksik değer null.
  static FinanceFund? tryParse(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    for (final fund in values) {
      if (fund.apiValue == normalized) return fund;
    }
    return null;
  }
}

/// Kuruş tutarı JSON'dan güvenle okur (tamsayı, tam sayı değerli sayı ya da rakam metni); bozuksa null.
int? fundMinor(Object? raw) {
  const limit = 9007199254740991;
  if (raw is int) return raw.abs() > limit ? null : raw;
  if (raw is num) {
    if (!raw.isFinite) return null;
    final value = raw.toInt();
    return value.abs() > limit || value != raw ? null : value;
  }
  if (raw is String) {
    final text = raw.trim();
    if (!RegExp(r'^-?[0-9]{1,16}$').hasMatch(text)) return null;
    final value = int.tryParse(text);
    return value == null || value.abs() > limit ? null : value;
  }
  return null;
}

/// Bir tahsilatın kasalara dağılımı (`fund_split`): İşletme + Fon + avans = tahsilat tutarı.
@immutable
class FundSplit {
  const FundSplit({required this.operatingMinor, required this.capitalMinor, required this.advanceMinor});

  final int operatingMinor;
  final int capitalMinor;

  /// Henüz hiçbir borca dağıtılmamış kısım (avans).
  final int advanceMinor;

  int get totalMinor => operatingMinor + capitalMinor + advanceMinor;

  int of(FinanceFund fund) => fund == FinanceFund.operating ? operatingMinor : capitalMinor;

  /// Üç alan da okunabiliyorsa dağılım; eksik / bozuksa null (uydurma 0 yazılmaz).
  static FundSplit? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final operating = fundMinor(raw['operating_minor']);
    final capital = fundMinor(raw['capital_minor']);
    final advance = fundMinor(raw['advance_minor']);
    if (operating == null || capital == null || advance == null) return null;
    return FundSplit(operatingMinor: operating, capitalMinor: capital, advanceMinor: advance);
  }

  @override
  bool operator ==(Object other) =>
      other is FundSplit &&
      other.operatingMinor == operatingMinor &&
      other.capitalMinor == capitalMinor &&
      other.advanceMinor == advanceMinor;

  @override
  int get hashCode => Object.hash(operatingMinor, capitalMinor, advanceMinor);
}

/// Bir daire hesabının tek kasadaki durumu (ekstre `funds.*`, sakin `funds.*`): açık borç, vadesi geçen ve o kasaya kısıtlı avans.
@immutable
class FundAmounts {
  const FundAmounts({this.balanceMinor = 0, this.overdueMinor = 0, this.advanceMinor = 0});

  /// Açık borç (kasaya göre; borç yoksa 0).
  final int balanceMinor;

  /// Vadesi geçen açık borç.
  final int overdueMinor;

  /// Yalnız bu kasaya kısıtlı avans.
  final int advanceMinor;

  /// Üç tutar da sıfır mı (sakin ekranı sıfır kasayı göstermez)?
  bool get isZero => balanceMinor == 0 && overdueMinor == 0 && advanceMinor == 0;

  static FundAmounts? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final balance = fundMinor(raw['balance_minor']);
    if (balance == null) return null;
    // Vadesi geçen / avans alanı yoksa 0 sayılır (eski biçim); VAR ama bozuksa kırılım okunamaz.
    final overdue = raw['overdue_minor'] == null ? 0 : fundMinor(raw['overdue_minor']);
    final advance = raw['advance_minor'] == null ? 0 : fundMinor(raw['advance_minor']);
    if (overdue == null || advance == null) return null;
    return FundAmounts(balanceMinor: balance, overdueMinor: overdue, advanceMinor: advance);
  }

  @override
  bool operator ==(Object other) =>
      other is FundAmounts &&
      other.balanceMinor == balanceMinor &&
      other.overdueMinor == overdueMinor &&
      other.advanceMinor == advanceMinor;

  @override
  int get hashCode => Object.hash(balanceMinor, overdueMinor, advanceMinor);
}

/// İki kasanın kırılımı (`funds: { operating: {...}, capital: {...} }`).
@immutable
class FundBreakdown {
  const FundBreakdown({required this.operating, required this.capital});

  final FundAmounts operating;
  final FundAmounts capital;

  FundAmounts of(FinanceFund fund) => fund == FinanceFund.operating ? operating : capital;

  /// İki kasa da okunabiliyorsa kırılım; eksik / bozuksa null (eski sunucu `funds` göndermez).
  static FundBreakdown? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final operating = FundAmounts.tryParse(raw[FinanceFund.operating.apiValue]);
    final capital = FundAmounts.tryParse(raw[FinanceFund.capital.apiValue]);
    if (operating == null || capital == null) return null;
    return FundBreakdown(operating: operating, capital: capital);
  }

  @override
  bool operator ==(Object other) =>
      other is FundBreakdown && other.operating == operating && other.capital == capital;

  @override
  int get hashCode => Object.hash(operating, capital);
}
