// Belge metninden ADAY değerler (tutar, tarih, IBAN): saf Dart, ağ ve eklenti yok (P2-13, karar K15).
//
// Girdi, telefonda metin tanımanın (ML Kit) ham metnidir. Çıktı yalnız ÖNERİDİR: forma ancak kullanıcı bir adaya dokununca yazılır.
// Metin ve çıkan değerler günlüğe YAZILMAZ. Biçimler Türkiye'dekilerdir: tutar "1.234,56", tarih "GG.AA.YYYY", IBAN "TR.." (mod 97 doğrulanır).
import 'package:site_kapi_kontrol/models/payment_info.dart' show parseTrIban;
import 'package:site_kapi_kontrol/ui/helpers/money.dart' show kMaxMoneyMinor;

/// Tutar adayı: kuruş + sıralama puanı.
class AmountCandidate {
  const AmountCandidate({required this.minor, required this.score});

  final int minor;
  final int score;
}

/// IBAN'ın belgedeki rolü (etiketten tahmin; emin değilse [unknown]).
enum IbanRole { sender, receiver, unknown }

/// IBAN adayı: boşluksuz büyük harfli IBAN + tahmin edilen rol.
class IbanCandidate {
  const IbanCandidate({required this.iban, required this.role});

  final String iban;
  final IbanRole role;
}

/// Belge metninden çıkan adaylar; her liste en iyi aday başta olacak biçimde sıralıdır.
class DocumentSuggestions {
  const DocumentSuggestions({this.amounts = const <AmountCandidate>[], this.dates = const <DateTime>[], this.ibans = const <IbanCandidate>[]});

  final List<AmountCandidate> amounts;
  final List<DateTime> dates;
  final List<IbanCandidate> ibans;

  bool get isEmpty => amounts.isEmpty && dates.isEmpty && ibans.isEmpty;
}

/// Türkçe harfleri ASCII küçük harfe indirger (uzunluk korunur): "İŞLEM TARİHİ" -> "islem tarihi". OCR çoğu kez noktalı / noktasız harfi karıştırır.
String foldTurkish(String input) {
  final out = StringBuffer();
  for (final unit in input.codeUnits) {
    switch (unit) {
      case 0x130 || 0x131 || 0x49: // İ ı I
        out.write('i');
      case 0x15E || 0x15F: // Ş ş
        out.write('s');
      case 0x11E || 0x11F: // Ğ ğ
        out.write('g');
      case 0xDC || 0xFC: // Ü ü
        out.write('u');
      case 0xD6 || 0xF6: // Ö ö
        out.write('o');
      case 0xC7 || 0xE7: // Ç ç
        out.write('c');
      default:
        out.write(String.fromCharCode(unit).toLowerCase());
    }
  }
  return out.toString();
}

const int _maxAmounts = 4;
const int _maxDates = 3;
const int _maxIbans = 3;

// "1.234,56" | "12345,67": binlik gruplu ya da düz tamsayı kısmı + TAM iki kuruş hanesi. Çevresinde rakam / ayırıcı olmaz ("1.23,45", "05,10,2026" eşleşmez).
final RegExp _amountPattern = RegExp(r'(?<![\d.,])(\d{1,3}(?:\.\d{3})+|\d+),(\d{2})(?![\d]|[.,]\d)');

// Tarihler: GG.AA.YYYY (ayırıcı . / -), YYYY-AA-GG, "15 Ekim 2026".
final RegExp _datePattern = RegExp(r'(?<![\d.,/\-])(\d{1,2})[./\-](\d{1,2})[./\-](\d{4})(?![\d]|[./\-]\d)');
final RegExp _isoDatePattern = RegExp(r'(?<![\d.,/\-])(\d{4})-(\d{2})-(\d{2})(?![\d]|[./\-]\d)');
final RegExp _namedDatePattern = RegExp(
  r'(?<![\d.,/\-])(\d{1,2})\s+(ocak|subat|mart|nisan|mayis|haziran|temmuz|agustos|eylul|ekim|kasim|aralik)\s+(\d{4})(?!\d)',
);
const Map<String, int> _months = <String, int>{
  'ocak': 1,
  'subat': 2,
  'mart': 3,
  'nisan': 4,
  'mayis': 5,
  'haziran': 6,
  'temmuz': 7,
  'agustos': 8,
  'eylul': 9,
  'ekim': 10,
  'kasim': 11,
  'aralik': 12,
};

// TR + 2 hane + 22 hane; OCR karışıklıkları (O->0, I/l->1) ve grup boşlukları / satır sonu tolere edilir, doğruluğu mod 97 belirler.
final RegExp _ibanPattern = RegExp(r'(?<![a-z0-9])tr[\doil]{2}(?:[ \t\r\n.\-]?[\doil]){22}(?!\d)');

/// Metindeki tutar / tarih / IBAN adaylarını çıkarır. [notBefore] / [notAfter] verilirse tarih adayları o aralıkla (gün dahil) sınırlanır.
DocumentSuggestions parseDocumentText(String text, {DateTime? notBefore, DateTime? notAfter}) {
  final folded = foldTurkish(text);
  return DocumentSuggestions(amounts: _amounts(folded), dates: _dates(folded, notBefore, notAfter), ibans: _ibans(folded));
}

// ---- tutar ----

const List<String> _strongAmountWords = <String>['genel toplam', 'toplam', 'odenecek', 'odenen', 'islem tutari', 'gonderilen', 'havale tutari', 'eft tutari'];
const List<String> _amountWords = <String>['tutar', 'miktar', 'bedel', 'total', 'amount', 'borc'];
const List<String> _notTheAmountWords = <String>[
  'kdv',
  'komisyon',
  'masraf',
  'bsmv',
  'vergi',
  'bakiye',
  'limit',
  'kalan',
  'ucret',
  'faiz',
  'iskonto',
  'indirim',
];

bool _hasAny(String line, List<String> words) {
  for (final w in words) {
    if (line.contains(w)) return true;
  }
  return false;
}

int _lineScore(String line) {
  if (_hasAny(line, _strongAmountWords)) return 5;
  var score = 0;
  if (_hasAny(line, _amountWords)) score += 3;
  if (_hasAny(line, _notTheAmountWords)) score -= 3;
  return score;
}

List<AmountCandidate> _amounts(String folded) {
  final lines = folded.split(RegExp(r'\r?\n'));
  final best = <int, int>{}; // kuruş -> en iyi puan
  final order = <int>[]; // ilk görülme sırası
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final m in _amountPattern.allMatches(line)) {
      final before = m.start == 0 ? '' : line.substring(0, m.start).trimRight();
      final after = line.substring(m.end).trimLeft();
      // Yüzde ("%18,00" / "18,00 %") tutar değildir.
      if (before.endsWith('%') || after.startsWith('%')) continue;
      final lira = BigInt.tryParse(m.group(1)!.replaceAll('.', ''));
      final cents = int.tryParse(m.group(2)!);
      if (lira == null || cents == null) continue;
      final total = lira * BigInt.from(100) + BigInt.from(cents);
      if (total <= BigInt.zero || total > BigInt.from(kMaxMoneyMinor)) continue;
      final minor = total.toInt();
      // Etiket çoğu kez bir önceki satırda kalır (OCR blokları ayırır): yarı ağırlıkla sayılır.
      var score = _lineScore(line);
      if (score == 0 && i > 0) score = _lineScore(lines[i - 1]) ~/ 2;
      if (before.endsWith('₺') || after.startsWith('₺') || after.startsWith('tl') || after.startsWith('try')) score += 1;
      final known = best[minor];
      if (known == null) {
        best[minor] = score;
        order.add(minor);
      } else if (score > known) {
        best[minor] = score;
      }
    }
  }
  final sorted = List<int>.of(order)
    ..sort((a, b) {
      final byScore = best[b]!.compareTo(best[a]!);
      if (byScore != 0) return byScore;
      final byValue = b.compareTo(a); // eşit puanda büyük tutar (toplam, parçalarından küçük olmaz)
      return byValue != 0 ? byValue : order.indexOf(a).compareTo(order.indexOf(b));
    });
  return [for (final minor in sorted.take(_maxAmounts)) AmountCandidate(minor: minor, score: best[minor]!)];
}

// ---- tarih ----

const List<String> _dateGoodWords = <String>['tarih', 'gonderim', 'valor', 'date'];
const List<String> _dateBadWords = <String>['vade', 'son odeme', 'dogum', 'gecerlilik', 'bitis'];

DateTime? _realDate(int year, int month, int day) {
  if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1) return null;
  final date = DateTime(year, month, day);
  // DateTime taşan günü sonraki aya kaydırır (31.02 -> 03.03): gerçek tarih mi?
  return date.year == year && date.month == month && date.day == day ? date : null;
}

List<DateTime> _dates(String folded, DateTime? notBefore, DateTime? notAfter) {
  final lowest = notBefore == null ? null : DateTime(notBefore.year, notBefore.month, notBefore.day);
  final highest = notAfter == null ? null : DateTime(notAfter.year, notAfter.month, notAfter.day);
  final lines = folded.split(RegExp(r'\r?\n'));
  final best = <DateTime, int>{};
  final order = <DateTime>[];
  void add(DateTime? date, String line, int end) {
    if (date == null) return;
    if (lowest != null && date.isBefore(lowest)) return;
    if (highest != null && date.isAfter(highest)) return;
    var score = 0;
    if (_hasAny(line, _dateBadWords)) {
      score -= 3;
    } else if (_hasAny(line, _dateGoodWords)) {
      score += 3;
    }
    // İşlem damgası "15.10.2026 14:32": saat hemen yanındaysa bu bir işlem tarihidir.
    if (RegExp(r'^[\s,t-]*\d{1,2}:\d{2}').hasMatch(line.substring(end))) score += 1;
    final known = best[date];
    if (known == null) {
      best[date] = score;
      order.add(date);
    } else if (score > known) {
      best[date] = score;
    }
  }

  for (final line in lines) {
    for (final m in _datePattern.allMatches(line)) {
      add(_realDate(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!)), line, m.end);
    }
    for (final m in _isoDatePattern.allMatches(line)) {
      add(_realDate(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)), line, m.end);
    }
    for (final m in _namedDatePattern.allMatches(line)) {
      add(_realDate(int.parse(m.group(3)!), _months[m.group(2)!]!, int.parse(m.group(1)!)), line, m.end);
    }
  }
  final sorted = List<DateTime>.of(order)
    ..sort((a, b) {
      final byScore = best[b]!.compareTo(best[a]!);
      return byScore != 0 ? byScore : b.compareTo(a); // eşit puanda yeni tarih önde
    });
  return sorted.take(_maxDates).toList();
}

// ---- IBAN ----

const List<String> _senderWords = <String>['gonderen', 'gonderici', 'borclu', 'odeyen'];
const List<String> _receiverWords = <String>['alici', 'alacakli', 'lehdar', 'hesap sahibi', 'aliciya'];

IbanRole _roleBefore(String folded, int start) {
  final from = start - 60 < 0 ? 0 : start - 60;
  // Önceki satırın etiketi de sayılır ama en yakın etiket kazanır.
  final window = folded.substring(from, start);
  var sender = -1;
  var receiver = -1;
  for (final w in _senderWords) {
    final at = window.lastIndexOf(w);
    if (at > sender) sender = at;
  }
  for (final w in _receiverWords) {
    final at = window.lastIndexOf(w);
    if (at > receiver) receiver = at;
  }
  if (sender < 0 && receiver < 0) return IbanRole.unknown;
  return sender > receiver ? IbanRole.sender : IbanRole.receiver;
}

List<IbanCandidate> _ibans(String folded) {
  final seen = <String>{};
  final found = <IbanCandidate>[];
  for (final m in _ibanPattern.allMatches(folded)) {
    final raw = m.group(0)!.replaceAll(RegExp(r'[ \t\r\n.\-]'), '');
    // İlk iki harf TR; kalanı rakam beklenir, OCR karışıklıkları düzeltilir (o -> 0, i / l -> 1).
    final digits = raw.substring(2).replaceAll('o', '0').replaceAll('i', '1').replaceAll('l', '1');
    final iban = parseTrIban('TR$digits');
    if (iban == null || !seen.add(iban)) continue;
    found.add(IbanCandidate(iban: iban, role: _roleBefore(folded, m.start)));
    if (found.length >= _maxIbans) break;
  }
  return found;
}
