// MT940 ekstre ayrıştırıcısı (el yazımı, saf Dart; MT942 ve CAMT.053 kapsam dışı).
//
// Desteklenen alanlar: :20: (dosya), :25: (hesap / IBAN), :28C:, :60F/M: (açılış), :61: (valör, C/D/RC/RD, tutar, referans, //banka referansı),
// çok satırlı :86: (?20-?29 açıklama, ?32-?33 gönderen adı, IBAN deseni), :62F/M: (kapanış); çok bloklu dosya; CRLF / LF.
// Gerçek banka örneği olmadığı için :86: alt alan düzenleri doğrulanmadı: ?xx yoksa tüm metin açıklama sayılır.
import 'package:site_kapi_kontrol/services/bank_amount.dart';

class Mt940Line {
  const Mt940Line({
    required this.valueDate,
    required this.amountMinor,
    required this.description,
    this.counterpartyName,
    this.counterpartyIban,
    this.bankReference,
  });

  /// yyyy-MM-dd
  final String valueDate;

  /// Giriş artı, çıkış eksi.
  final int amountMinor;
  final String description;
  final String? counterpartyName;
  final String? counterpartyIban;
  final String? bankReference;
}

class Mt940Statement {
  const Mt940Statement({this.accountIban, this.openingMinor, this.closingMinor, required this.lines});

  final String? accountIban;
  final int? openingMinor;
  final int? closingMinor;
  final List<Mt940Line> lines;
}

class Mt940Exception implements Exception {
  const Mt940Exception(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Metin MT940 gibi görünüyor mu? (:20: ve :61: etiketleri)
bool looksLikeMt940(String text) => RegExp(r'^:20:', multiLine: true).hasMatch(text) && RegExp(r'^:61:', multiLine: true).hasMatch(text);

final RegExp _ibanPattern = RegExp(r'TR\d{2}(?:\s?[0-9A-Z]){22}(?![0-9A-Z])');
final RegExp _line61 = RegExp(r'^(\d{6})(\d{4})?(R?[CD])([A-Z]?)(\d+(?:,\d{0,2})?)N([A-Z0-9]{3})([^/]*)(?://(.*))?$');

String _iso(String yymmdd) {
  final yy = int.parse(yymmdd.substring(0, 2));
  final year = 2000 + yy;
  return '$year-${yymmdd.substring(2, 4)}-${yymmdd.substring(4, 6)}';
}

int? _balance(String value) {
  // C|D + YYMMDD + PARA(3) + tutar
  final m = RegExp(r'^([CD])(\d{6})[A-Z]{3}(\d+(?:,\d{0,2})?)$').firstMatch(value.trim());
  if (m == null) return null;
  final minor = parseAmountMinor(m.group(3)!);
  if (minor == null) return null;
  return m.group(1) == 'D' ? -minor : minor;
}

Mt940Statement parseMt940(String text) {
  // (etiket, değer) alanlarına böl; ':' + etiket + ':' ile başlamayan satırlar öncekinin devamıdır.
  final fields = <(String, String)>[];
  for (final raw in text.split(RegExp(r'\r\n|\r|\n'))) {
    final line = raw.trimRight();
    final m = RegExp(r'^:(\d{2}[A-Z]?):(.*)$').firstMatch(line);
    if (m != null) {
      fields.add((m.group(1)!, m.group(2)!));
    } else if (line.startsWith('-}') || line.startsWith('{') || line == '-') {
      continue;
    } else if (fields.isNotEmpty && line.isNotEmpty) {
      final last = fields.removeLast();
      fields.add((last.$1, '${last.$2}\n$line'));
    }
  }
  if (!fields.any((f) => f.$1 == '61')) throw const Mt940Exception('Dosyada MT940 hareket satırı (:61:) bulunamadı.');

  String? iban;
  int? opening;
  int? closing;
  final lines = <Mt940Line>[];
  for (var i = 0; i < fields.length; i++) {
    final (tag, value) = fields[i];
    if (tag == '25') {
      final found = _ibanPattern.firstMatch(value.toUpperCase());
      iban ??= found?.group(0)?.replaceAll(RegExp(r'\s'), '');
    } else if (tag == '60F' || tag == '60M') {
      opening ??= _balance(value);
    } else if (tag == '62F' || tag == '62M') {
      closing = _balance(value);
    } else if (tag == '61') {
      final first = value.split('\n').first;
      final m = _line61.firstMatch(first.trim());
      if (m == null) throw Mt940Exception('Bir hareket satırı (:61:) okunamadı: $first');
      final amount = parseAmountMinor(m.group(5)!);
      if (amount == null || amount == 0) throw Mt940Exception('Bir hareketin tutarı okunamadı: $first');
      final mark = m.group(3)!;
      // C artı, D eksi; RC (alacak iadesi) eksi, RD (borç iadesi) artı
      final credit = mark == 'C' || mark == 'RD';
      var ref = m.group(7)!.trim();
      final bankRef = m.group(8)?.trim();
      if (ref == 'NONREF') ref = '';
      var description = '';
      String? name;
      String? counterIban;
      if (i + 1 < fields.length && fields[i + 1].$1 == '86') {
        final body = fields[i + 1].$2.replaceAll('\n', '');
        final parts = <String, String>{};
        final sub = RegExp(r'\?(\d{2})([^?]*)');
        for (final s in sub.allMatches(body)) {
          parts[s.group(1)!] = (parts[s.group(1)!] ?? '') + s.group(2)!;
        }
        if (parts.isNotEmpty) {
          final desc = <String>[];
          for (var k = 20; k <= 29; k++) {
            final p = parts['$k'];
            if (p != null && p.trim().isNotEmpty) desc.add(p.trim());
          }
          description = desc.join(' ');
          final n = '${parts['32'] ?? ''}${parts['33'] ?? ''}'.trim();
          name = n.isEmpty ? null : n;
        } else {
          description = body.replaceAll(RegExp(r'\s+'), ' ').trim();
        }
        final found = _ibanPattern.firstMatch(body.toUpperCase());
        counterIban = found?.group(0)?.replaceAll(RegExp(r'\s'), '');
        if (counterIban == iban) counterIban = null;
      }
      if (description.isEmpty) description = ref;
      lines.add(
        Mt940Line(
          valueDate: _iso(m.group(1)!),
          amountMinor: credit ? amount : -amount,
          description: description,
          counterpartyName: name,
          counterpartyIban: counterIban,
          bankReference: (bankRef != null && bankRef.isNotEmpty) ? bankRef : (ref.isEmpty ? null : ref),
        ),
      );
    }
  }
  return Mt940Statement(accountIban: iban, openingMinor: opening, closingMinor: closing, lines: lines);
}
