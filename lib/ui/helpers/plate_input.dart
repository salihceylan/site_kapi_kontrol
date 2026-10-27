// Plaka girdisi: uygulamadaki TEK Türk plakası kuralı + yazarken biçimlendiren giriş süzgeçleri.
//
// Kural sunucuyla aynıdır (server/src/modules/plate_format.js): il kodu 01-81 + 1-3 harf + 2-4 rakam. Boşluk / tire / nokta
// atılır, büyük harf, Türkçe harfler ASCII'ye iner. Sunucuya `34ABC123` (boşluksuz) saklanır, ekranda `34 ABC 123` görünür.
//
// - [PlateInputFormatter]: tek plaka alanı; yazarken "34 ABC 123" biçiminde gruplar, plakaya götüremeyecek tuşu reddeder.
// - [PlateListInputFormatter]: virgülle ayrılmış çok plakalı alan ("34 ABC 123, 06 XY 789").
// - [validatePlate] / [validatePlateList]: form doğrulayıcıları (sunucu iletisiyle aynı metin).
//
// ESKİ KAYITLI plaka bu kurala uymayabilir (eskiden 5-10 harf / rakam yeterdi). Bu yüzden alan ilk değeriyle aynıysa
// ([validatePlate] `initial`) ya da parça kayıtlı plakalardan biriyse (`preserved`) engellenmez ve süzgeç onu bozmaz.

import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart' show canonicalTrPlate, formatTrPlate, normalizeTrPlate;

/// Geçersiz plaka iletisi; sunucudaki `PLATE_INVALID` iletisiyle aynıdır.
const String kPlateInvalidMessage = 'Plaka biçimi geçersiz. Örnek: 34 ABC 123 (il kodu 01-81).';

/// Bir alandaki en çok plaka sayısı (toplu yükleme ile aynı).
const int maxPlatesPerField = 5;

/// Çok plakalı alanda ayırıcılar (toplu yüklemedeki ayrıştırıcıyla aynı).
final RegExp _listSeparator = RegExp(r'[,;/|\r\n]');

/// Il kodu 01-81 + 1-3 harf + 2-4 rakam yolunda GEÇERLİ bir başlangıç mı (boş dahil)? Yazarken tuş kabulünde kullanılır.
final RegExp _platePrefix = RegExp(r'^(?:|[0-8]|(?:0[1-9]|[1-7][0-9]|8[01])(?:|[A-Z]{1,3}(?:|[0-9]{1,4})))$');

/// Plakaya benzeyen biçim (il kodu aralığına bakmaz): en çok 2 rakam, en çok 3 harf, en çok 4 rakam. Silerken ara hâller için.
final RegExp _plateShape = RegExp(r'^[0-9]{0,2}[A-Z]{0,3}[0-9]{0,4}$');

final RegExp _plateGroups = RegExp(r'^([0-9]{0,2})([A-Z]{0,3})([0-9]{0,4})$');

final RegExp _alnum = RegExp(r'^[A-Z0-9]$');

/// [canonical] (harf / rakam, büyük harf) yazarken plakaya götürebilecek bir başlangıç mı ("34", "34A", "34 ABC 12"...).
bool isPlatePrefix(String canonical) => _platePrefix.hasMatch(canonical);

/// Geçerli Türk plakası ise normalize hâli (`34ABC123`), değilse null. Boşluk / tire / nokta atılır, Türkçe harf ASCII olur.
String? normalizePlateInput(String? text) => normalizeTrPlate(text ?? '');

/// Geçerliyse "34 ABC 123"; değilse kullanıcının yazdığı metin (kenar boşlukları atılmış, büyük harf).
String formatPlateInput(String? text) {
  final plate = normalizePlateInput(text);
  if (plate != null) return formatTrPlate(plate);
  return (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
}

/// Tek plaka alanı doğrulayıcısı: boş ya da geçersiz [kPlateInvalidMessage]; geçerliyse null.
///
/// [initial] verilirse ve alan hâlâ ilk değerine eşitse (eski kayıtlı, kurala uymayan plaka) engellenmez.
String? validatePlate(String? value, {String? initial}) {
  if (normalizePlateInput(value) != null) return null;
  final text = (value ?? '').trim();
  if (initial != null && text.isNotEmpty && text == initial.trim()) return null;
  return kPlateInvalidMessage;
}

// --- Çok plakalı alan ----------------------------------------------------------------------------------------------

/// Girilen tek bir plaka: [plate] normalize (`34ABC123`), [display] sunucuya gönderilen / gösterilen biçim (`34 ABC 123`).
class PlateEntry {
  const PlateEntry(this.plate, this.display);

  final String plate;
  final String display;
}

/// [parsePlateList] sonucu: geçerli plakalar (yinelenenler atılmış), geçersiz parçalar ve sayı sınırı aşımı.
class PlateListParse {
  const PlateListParse({
    this.plates = const <PlateEntry>[],
    this.invalid = const <String>[],
    this.tooMany = false,
    this.formulaLike = false,
  });

  final List<PlateEntry> plates;
  final List<String> invalid;

  /// [maxPlatesPerField]'ten fazla parça var.
  final bool tooMany;

  /// Alan `=`, `@`, `+`, `-` ile başlıyor (toplu yüklemede de reddedilir: tablo formülü gibi görünür).
  final bool formulaLike;

  bool get isValid => invalid.isEmpty && !tooMany && !formulaLike;
}

/// Plaka alanını (birden çok plaka `,` `;` `/` `|` ya da satır sonuyla ayrılır) ayrıştırır: en çok [maxPlatesPerField] parça;
/// her parça Türk plakası olmalı; aynı plaka bir kez sayılır. Boş metin: hiç plaka.
///
/// [preserved]: kişide zaten kayıtlı plakalar (normalize). Kurala uymasalar bile bu parçalar geçerli sayılır (eski kayıt; sunucuya
/// yeniden gönderilmez, ama alandan çıkarılırsa pasife alınabilmesi için listede kalmalıdır).
PlateListParse parsePlateList(String? text, {Set<String> preserved = const <String>{}}) {
  final cleaned = (text ?? '').replaceAll(RegExp(r'[ \t\f\v]+'), ' ').trim();
  if (cleaned.isEmpty) return const PlateListParse();
  if (RegExp(r'^[=@+\-]').hasMatch(cleaned)) {
    return const PlateListParse(formulaLike: true);
  }
  final parts = cleaned
      .split(_listSeparator)
      .map((part) => part.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length > maxPlatesPerField) {
    return const PlateListParse(tooMany: true);
  }
  final plates = <PlateEntry>[];
  final invalid = <String>[];
  final seen = <String>{};
  for (final part in parts) {
    final plate = normalizePlateInput(part);
    if (plate != null) {
      if (seen.add(plate)) plates.add(PlateEntry(plate, formatTrPlate(plate)));
      continue;
    }
    final legacy = canonicalTrPlate(part);
    if (legacy.isNotEmpty && preserved.contains(legacy)) {
      if (seen.add(legacy)) plates.add(PlateEntry(legacy, part.toUpperCase()));
      continue;
    }
    invalid.add(part.length > 40 ? part.substring(0, 40) : part);
  }
  return PlateListParse(plates: plates, invalid: invalid);
}

/// Çok plakalı alan doğrulayıcısı: en çok [maxPlatesPerField] plaka, her biri Türk plakası. Tek ileti, geçersiz plakaları adıyla söyler
/// ("Plaka biçimi geçersiz: ABC12345. Örnek: 34 ABC 123 (il kodu 01-81).").
///
/// [initial] verilirse ve alan hâlâ ilk değerine eşitse (eski kayıtlı veri) engellenmez; [preserved] için bkz. [parsePlateList].
String? validatePlateList(String? value, {Set<String> preserved = const <String>{}, String? initial}) {
  final parsed = parsePlateList(value, preserved: preserved);
  if (parsed.formulaLike) {
    return 'Plaka biçimi geçersiz: =, @, + ya da - ile başlayamaz.';
  }
  if (parsed.tooMany) {
    // Kayıtlı plaka sayısı zaten sınırı aşıyorsa (eski veri) DEĞİŞMEMİŞ alan engellenmez.
    final unchanged = initial != null && (value ?? '').trim() == initial.trim();
    return unchanged ? null : 'En çok $maxPlatesPerField plaka girilebilir; virgülle ayırın.';
  }
  if (parsed.invalid.isNotEmpty) {
    return 'Plaka biçimi geçersiz: ${parsed.invalid.join(', ')}. Örnek: 34 ABC 123 (il kodu 01-81).';
  }
  return null;
}

/// Çok plakalı metni "34 ABC 123, 06 XY 789" biçimine getirir (geçersiz parçalar yazıldığı gibi, büyük harfle kalır).
String formatPlateList(String? text) {
  final parts = (text ?? '').split(_listSeparator).map((p) => p.trim()).where((p) => p.isNotEmpty);
  return parts.map(formatPlateInput).join(', ');
}

// --- Giriş süzgeçleri ----------------------------------------------------------------------------------------------

/// Tek plaka alanı: BÜYÜK harf, Türkçe harf -> ASCII, "34 ABC 123" gruplama ve plakaya götürmeyen tuşları reddetme.
///
/// Reddedilenler: il kodunda harf, il kodu 00 ya da 81'den büyük, 4. harf, 5. rakam, harften sonra yeniden harf, harfsiz rakam
/// ve harf / rakam / ayırıcı (boşluk, `-`, `.`, `_`) dışındaki karakterler. Silme serbesttir (ara hâl geçersiz görünebilir,
/// doğrulayıcı yakalar). Ayırıcıya (otomatik boşluk) geri tuşu imleci boşluğun öbür yanına geçirir.
class PlateInputFormatter extends TextInputFormatter {
  const PlateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      _formatPlateEdit(oldValue, newValue, list: false, preserved: const <String>{});
}

/// Virgülle ayrılmış çok plakalı alan (en çok [maxPlatesPerField]): her plakayı gruplar, ayırıcıları ", " yapar.
///
/// `;` `/` `|` ve satır sonu virgüle çevrilir. [preserved]: kişide kayıtlı eski plakalar; bunlara dokunulmaz.
class PlateListInputFormatter extends TextInputFormatter {
  const PlateListInputFormatter({this.preserved = const <String>{}});

  final Set<String> preserved;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      _formatPlateEdit(oldValue, newValue, list: true, preserved: preserved);
}

/// Harf / rakamlar (Türkçe harf ASCII, büyük harf); ayırıcılar (boşluk, tire, nokta, alt çizgi) atılır. İzin dışı karakter varsa null.
String? _significant(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final folded = canonicalTrPlate(String.fromCharCode(rune));
    if (folded.isEmpty) continue;
    if (folded.length != 1 || !_alnum.hasMatch(folded)) return null;
    out.write(folded);
  }
  return out.toString();
}

/// [sub] harfleri sırası bozulmadan [full] içinde geçiyor mu?
bool _isSubsequence(String sub, String full) {
  var at = 0;
  for (var i = 0; i < full.length && at < sub.length; i++) {
    if (full[i] == sub[at]) at++;
  }
  return at == sub.length;
}

/// Bir plaka parçasını gruplar: "34ABC123" -> "34 ABC 123". Plaka biçimine uymayan (eski) parça olduğu gibi kalır.
String _group(String sig) {
  final m = _plateGroups.firstMatch(sig);
  if (m == null) return sig;
  return <String>[m[1]!, m[2]!, m[3]!].where((p) => p.isNotEmpty).join(' ');
}

TextEditingValue _formatPlateEdit(
  TextEditingValue oldValue,
  TextEditingValue newValue, {
  required bool list,
  required Set<String> preserved,
}) {
  final raw = newValue.text;

  // 1) Parçala: tek plaka alanında tek parça (virgül vb. izin dışı karakter olur ve reddedilir).
  final rawParts = list ? raw.split(_listSeparator) : <String>[raw];
  final sigs = <String>[];
  for (final part in rawParts) {
    final sig = _significant(part);
    if (sig == null) return oldValue;
    sigs.add(sig);
  }
  final trailingSeparator = list && sigs.length > 1 && sigs.last.isEmpty && sigs.any((s) => s.isNotEmpty);
  final filled = sigs.where((s) => s.isNotEmpty).toList(growable: false);

  // Saf silme: yeni harf / rakamlar eskilerinin alt dizisi ve metin kısaldı. Silerken plakaya götürmeyen ara hâller serbesttir.
  final oldAll = _significant(oldValue.text.replaceAll(_listSeparator, ''));
  final isDeletion = raw.length < oldValue.text.length && (oldAll == null || _isSubsequence(sigs.join(), oldAll));

  // 2) Eski değerde plakaya götürmeyen (eski kayıt) parça var mı? Varsa silme tümüyle serbest (kullanıcı temizleyebilsin).
  var oldHasOffender = false;
  final oldParts = list ? oldValue.text.split(_listSeparator) : <String>[oldValue.text];
  for (final part in oldParts) {
    final sig = _significant(part);
    if (sig == null || sig.isEmpty) continue;
    if (!isPlatePrefix(sig) && !preserved.contains(sig)) oldHasOffender = true;
  }

  // 3) Her parça: plaka başlangıcı, kayıtlı eski plaka ya da (silerken) plaka biçiminde ara hâl olmalı.
  for (final sig in filled) {
    final ok = isPlatePrefix(sig) || preserved.contains(sig) || (isDeletion && (oldHasOffender || _plateShape.hasMatch(sig)));
    if (!ok) return oldValue;
  }
  final count = filled.length + (trailingSeparator ? 1 : 0);
  if (list && count > maxPlatesPerField && !isDeletion) return oldValue;

  // 4) Biçimlendir.
  final groups = <String>[];
  for (var i = 0; i < rawParts.length; i++) {
    final sig = sigs[i];
    if (sig.isEmpty) continue;
    groups.add(preserved.contains(sig) && !isPlatePrefix(sig) ? rawParts[i].replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase() : _group(sig));
  }
  final formatted = groups.join(', ') + (trailingSeparator ? ',' : '');
  if (formatted == raw) return newValue;

  // 5) İmleç: imlecin solundaki harf / rakam (ve ayırıcı virgül) sayısı kadar öğenin sonuna.
  final forward = isDeletion && formatted == oldValue.text && newValue.selection.isCollapsed && newValue.selection.baseOffset == oldValue.selection.baseOffset;
  final selection = newValue.selection.isValid
      ? TextSelection(
          baseOffset: _mapOffset(raw, newValue.selection.baseOffset, formatted, forward: forward),
          extentOffset: _mapOffset(raw, newValue.selection.extentOffset, formatted, forward: forward),
        )
      : TextSelection.collapsed(offset: formatted.length);
  return TextEditingValue(text: formatted, selection: selection);
}

bool _isToken(String ch) => _listSeparator.hasMatch(ch) || canonicalTrPlate(ch).isNotEmpty;

/// [raw] metninde [offset]'in solundaki öğe (harf / rakam / ayırıcı virgül) sayısı kadar öğenin, [formatted] metindeki sonuna giden yer.
/// [forward]: boşluklar da atlanır (imleç bir sonraki öğenin önüne gelir; Delete tuşunun ayırıcıyı geçmesi için).
int _mapOffset(String raw, int offset, String formatted, {required bool forward}) {
  final end = offset.clamp(0, raw.length);
  var count = 0;
  for (final rune in raw.substring(0, end).runes) {
    if (_isToken(String.fromCharCode(rune))) count++;
  }
  if (count == 0) return 0;
  var seen = 0;
  for (var i = 0; i < formatted.length; i++) {
    if (_isToken(formatted[i])) seen++;
    if (seen == count) {
      var at = i + 1;
      if (forward) {
        while (at < formatted.length && !_isToken(formatted[at])) {
          at++;
        }
      }
      return at;
    }
  }
  return formatted.length;
}
