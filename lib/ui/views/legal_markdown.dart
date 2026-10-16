import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:url_launcher/url_launcher.dart';

/// Yasal belgelerin Markdown ALT KÜMESİNİ yerelde, bağımlılıksız ve güvenle işleyen küçük çözümleyici +
/// widget (docs/PLATFORM_SATISA_HAZIRLIK.md §1.4).
///
/// İzinli sözdizimi: `#`/`##`/`###` başlık, paragraf, `-`/`*`/`+` ve `1.` listeler (iki boşlukla iç içe),
/// `**kalın**`, `[metin](https://…)` bağlantı. Tablo, görsel, HTML, satır içi kod YOKTUR: bunlar düz
/// metin olarak gösterilir. Hiçbir girdi widget ağacında HTML/komut olarak yorumlanmaz.
///
/// Güvenlik: bağlantılar yalnız `https` + ana makine adı olan, kullanıcı bilgisi/boşluk/denetim
/// karakteri içermeyen adreslerdir; diğer her şey (`javascript:`, `http:`, `data:`, `mailto:`, göreli
/// adres…) bağlantı OLMAZ, yalnız bağlantı metni düz yazı olarak kalır. Denetim ve çift yönlü
/// (bidi) yön karakterleri temizlenir. Çözümleyici hiçbir girdide hata fırlatmaz.

/// Çözümlenen en çok kaynak uzunluğu (daha uzunu kesilir).
const int kLegalMarkdownMaxLength = 700000;

/// Çözümlenen en çok blok sayısı (daha fazlası atılır).
const int kLegalMarkdownMaxBlocks = 12000;

/// Çözümlenen en uzun tek satır (daha uzunu kesilir).
const int kLegalMarkdownMaxLineLength = 100000;

/// Çözümlenen en çok satır sayısı.
const int kLegalMarkdownMaxLines = 400000;

/// Çözümlenen en çok liste maddesi sayısı (tüm belge).
const int kLegalMarkdownMaxListItems = 60000;

/// Sınırlardan biri aşılıp belge kesildiğinde belge sonunda gösterilen uyarı.
const String kLegalMarkdownTruncatedMessage =
    'Belgenin devamı gösterilemiyor; tam metin için web sayfasını açın.';

/// Satır içi parça.
sealed class MdSpan {
  const MdSpan(this.text, this.bold);

  final String text;
  final bool bold;
}

/// Düz (ya da kalın) metin.
final class MdText extends MdSpan {
  const MdText(String text, {bool bold = false}) : super(text, bold);
}

/// Doğrulanmış https bağlantısı.
final class MdLink extends MdSpan {
  const MdLink(String text, this.uri, {bool bold = false}) : super(text, bold);

  final Uri uri;
}

/// Blok.
sealed class MdBlock {
  const MdBlock();
}

final class MdHeading extends MdBlock {
  const MdHeading(this.level, this.spans);

  /// 1..3.
  final int level;
  final List<MdSpan> spans;
}

final class MdParagraph extends MdBlock {
  const MdParagraph(this.spans);

  final List<MdSpan> spans;
}

final class MdListItem {
  const MdListItem({required this.spans, required this.depth, this.number});

  final List<MdSpan> spans;

  /// 0..3 iç içelik düzeyi.
  final int depth;

  /// Sıralı listede gösterilen numara; madde işaretinde null.
  final int? number;
}

final class MdList extends MdBlock {
  const MdList(this.items);

  final List<MdListItem> items;
}

/// Belge sınırlarını aştığı için KESİLDİ: sonuna eklenen işaret bloğu (ekranda uyarı olarak gösterilir).
final class MdTruncated extends MdBlock {
  const MdTruncated();
}

final class MdRule extends MdBlock {
  const MdRule();
}

// --- Çözümleyici ------------------------------------------------------------------------------
//
// Tüm adımlar DOĞRUSALDIR (geri izlemeli düzenli ifade yok): kaynak sunucudaki bir belge bozulsa ya da
// kötü niyetli olsa bile çözümleme milisaniyelerde biter (UI donmaz). Sınırlar: toplam kaynak
// [kLegalMarkdownMaxLength], tek satır [kLegalMarkdownMaxLineLength], satır [kLegalMarkdownMaxLines], blok
// [kLegalMarkdownMaxBlocks], madde [kLegalMarkdownMaxListItems]; bağlantı çözümleme bütçesi dolarsa kalan
// köşeli parantezler düz metin kalır.

/// Denetim, çift yönlü (bidi) yön ve sıfır genişlikli karakterler ile BOM: yalnız kod noktası sayılarıyla elenir
/// (kaynakta kaçış dizisi/görünmez karakter bulunmaz).
///
/// Elenenler: C0 denetimleri (satır sonu ve sekme hariç), DEL, U+061C (ALM), U+200B-U+200F (sıfır genişlik,
/// ZWNJ/ZWJ, LRM, RLM), U+202A-U+202E, U+2060, U+2066-U+2069, U+FEFF.
///
/// Not: ZWJ (U+200D) silinmesi emoji dizilerini (birleşik emoji) böler; Türkçe hukuki metinde emoji/ZWJ
/// kullanımı olmadığından bilerek kabul edilmiştir (görünmez karakterle bağlantı/başlık sahteciliği riski daha
/// ağır basar).
bool _isStrippedRune(int c) =>
    c <= 0x08 ||
    c == 0x0B ||
    c == 0x0C ||
    (c >= 0x0E && c <= 0x1F) ||
    c == 0x7F ||
    c == 0x061C ||
    (c >= 0x200B && c <= 0x200F) ||
    (c >= 0x202A && c <= 0x202E) ||
    c == 0x2060 ||
    (c >= 0x2066 && c <= 0x2069) ||
    c == 0xFEFF;

/// U+2028 (satır ayırıcı) ve U+2029 (paragraf ayırıcı) SİLİNMEZ, boşluğa çevrilir: silinirse
/// `kelime1<LS>kelime2` yapışırdı.
bool _isSeparatorRune(int c) => c == 0x2028 || c == 0x2029;

String _stripControl(String value) {
  // Çoğu belgede temizlenecek karakter yoktur: tek geçişte denetle, gerekmedikçe kopyalama.
  var dirty = false;
  for (final c in value.runes) {
    if (_isStrippedRune(c) || _isSeparatorRune(c)) {
      dirty = true;
      break;
    }
  }
  if (!dirty) return value;
  final kept = <int>[];
  for (final c in value.runes) {
    if (_isStrippedRune(c)) continue;
    kept.add(_isSeparatorRune(c) ? 0x20 : c);
  }
  return String.fromCharCodes(kept);
}

/// [source] Markdown metnini bloklara çevirir. Asla hata fırlatmaz; bozuk girdi düz metne düşer.
List<MdBlock> parseLegalMarkdown(String source) {
  try {
    return _parseBlocks(source);
  } catch (_) {
    // Savunma: beklenmeyen bir durumda metni düz paragraf olarak göster (içerik kaybolmaz).
    final cut = source.length > kLegalMarkdownMaxLength;
    final text = _stripControl(cut ? source.substring(0, kLegalMarkdownMaxLength) : source).trim();
    if (text.isEmpty) return const <MdBlock>[];
    return <MdBlock>[
      MdParagraph(<MdSpan>[MdText(text)]),
      if (cut) const MdTruncated(),
    ];
  }
}

/// Satır sınıfı.
enum _LineKind { blank, heading, rule, bullet, ordered, text }

/// Tek bir satırın doğrusal sınıflandırması.
class _LineInfo {
  const _LineInfo(this.kind, {this.level = 0, this.indent = 0, this.number, this.text = ''});

  final _LineKind kind;
  final int level;
  final int indent;
  final int? number;
  final String text;
}

bool _isBlank(int unit) => unit == 0x20 || unit == 0x09;

/// Başlık satırı: en çok 3 boşluk girinti + 1-6 `#` + en az bir boşluk + metin. Kapanış `#` dizisi (öncesinde
/// boşluk varsa) atılır. Metin yoksa başlık sayılmaz.
_LineInfo? _asHeading(String line, int indent) {
  if (indent > 3 || indent >= line.length || line.codeUnitAt(indent) != 0x23) return null;
  var i = indent;
  while (i < line.length && line.codeUnitAt(i) == 0x23) {
    i++;
  }
  final hashes = i - indent;
  if (hashes < 1 || hashes > 6 || i >= line.length || !_isBlank(line.codeUnitAt(i))) return null;
  var end = line.length;
  while (end > i && _isBlank(line.codeUnitAt(end - 1))) {
    end--;
  }
  // Kapanış `#` dizisi: öncesinde boşluk olmalı ve metin başlangıcından sonra gelmeli.
  var close = end;
  while (close > i && line.codeUnitAt(close - 1) == 0x23) {
    close--;
  }
  if (close < end && close > i && _isBlank(line.codeUnitAt(close - 1))) {
    end = close;
    while (end > i && _isBlank(line.codeUnitAt(end - 1))) {
      end--;
    }
  }
  var start = i;
  while (start < end && _isBlank(line.codeUnitAt(start))) {
    start++;
  }
  return _LineInfo(_LineKind.heading, level: hashes > 3 ? 3 : hashes, text: line.substring(start, end));
}

/// Yatay çizgi: en çok 3 boşluk girinti, aynı işaretten (`-`, `*`, `_`) en az 3 tane, aralarında yalnız boşluk.
bool _isRule(String line, int indent) {
  if (indent > 3 || indent >= line.length) return false;
  final marker = line.codeUnitAt(indent);
  if (marker != 0x2D && marker != 0x2A && marker != 0x5F) return false;
  var count = 0;
  for (var i = indent; i < line.length; i++) {
    final c = line.codeUnitAt(i);
    if (c == marker) {
      count++;
    } else if (!_isBlank(c)) {
      return false;
    }
  }
  return count >= 3;
}

/// Madde satırı (`-`, `*`, `+` + boşluk) ya da sıralı madde (1-9 rakam + `.`/`)` + boşluk).
_LineInfo? _asListItem(String line, int indent) {
  if (indent >= line.length) return null;
  final first = line.codeUnitAt(indent);
  int textStart;
  _LineKind kind;
  int? number;
  if (first == 0x2D || first == 0x2A || first == 0x2B) {
    if (indent + 1 >= line.length || !_isBlank(line.codeUnitAt(indent + 1))) return null;
    kind = _LineKind.bullet;
    textStart = indent + 1;
  } else if (first >= 0x30 && first <= 0x39) {
    var i = indent;
    while (i < line.length && line.codeUnitAt(i) >= 0x30 && line.codeUnitAt(i) <= 0x39) {
      i++;
    }
    final digits = i - indent;
    if (digits < 1 || digits > 9 || i + 1 >= line.length) return null;
    final delimiter = line.codeUnitAt(i);
    if ((delimiter != 0x2E && delimiter != 0x29) || !_isBlank(line.codeUnitAt(i + 1))) return null;
    kind = _LineKind.ordered;
    number = int.tryParse(line.substring(indent, i));
    textStart = i + 1;
  } else {
    return null;
  }
  while (textStart < line.length && _isBlank(line.codeUnitAt(textStart))) {
    textStart++;
  }
  return _LineInfo(kind, indent: indent, number: number, text: line.substring(textStart));
}

_LineInfo _classify(String line) {
  var indent = 0;
  while (indent < line.length && line.codeUnitAt(indent) == 0x20) {
    indent++;
  }
  // Boş satır: yalnız boşluk türleri (boşluk, sekme, NBSP U+00A0, ideografik U+3000, U+202F... — Dart'ın
  // String.trim kümesi). Doğrusaldır.
  if (line.trim().isEmpty) return const _LineInfo(_LineKind.blank);
  final heading = _asHeading(line, indent);
  if (heading != null) return heading;
  if (_isRule(line, indent)) return const _LineInfo(_LineKind.rule);
  return _asListItem(line, indent) ?? _LineInfo(_LineKind.text, indent: indent, text: line);
}

List<MdBlock> _parseBlocks(String raw) {
  // Sınırlardan biri aşılıp içerik atılırsa `truncated` olur ve sona MdTruncated eklenir (sessiz kesme yok).
  var truncated = raw.length > kLegalMarkdownMaxLength;
  var source = truncated ? raw.substring(0, kLegalMarkdownMaxLength) : raw;
  source = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('\t', '    ');
  source = _stripControl(source);

  final budget = _ParseBudget(_kInlineBudget);
  final blocks = <MdBlock>[];
  final paragraph = <String>[];
  var listItems = <_RawItem>[];
  var totalItems = 0;

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final buffer = StringBuffer();
    for (var i = 0; i < paragraph.length; i++) {
      final line = paragraph[i];
      final hardBreak = line.endsWith('  ') || line.endsWith('\\');
      var text = line.trim();
      if (line.endsWith('\\') && text.endsWith('\\')) {
        text = text.substring(0, text.length - 1);
      }
      buffer.write(text);
      if (i < paragraph.length - 1) buffer.write(hardBreak ? '\n' : ' ');
    }
    paragraph.clear();
    final spans = _parseInline(buffer.toString().trim(), budget: budget);
    if (spans.isNotEmpty) blocks.add(MdParagraph(spans));
  }

  void flushList() {
    if (listItems.isEmpty) return;
    final items = <MdListItem>[];
    for (final item in listItems) {
      final spans = _parseInline(item.joined().trim(), budget: budget);
      if (spans.isNotEmpty) {
        items.add(MdListItem(spans: spans, depth: item.depth, number: item.number));
      }
    }
    listItems = <_RawItem>[];
    if (items.isNotEmpty) blocks.add(MdList(items));
  }

  var lineCount = 0;
  var start = 0;
  final length = source.length;
  while (start <= length) {
    if (blocks.length >= kLegalMarkdownMaxBlocks ||
        lineCount >= kLegalMarkdownMaxLines ||
        totalItems >= kLegalMarkdownMaxListItems) {
      // Kalan satırlarda görünür metin varsa belge kesilmiştir (yalnız boş satırlar kaldıysa kesme sayılmaz).
      if (start < length && source.substring(start).trim().isNotEmpty) truncated = true;
      break;
    }
    var end = source.indexOf('\n', start);
    if (end < 0) end = length;
    lineCount++;
    var line = source.substring(start, end);
    start = end + 1;
    if (line.length > kLegalMarkdownMaxLineLength) {
      line = line.substring(0, kLegalMarkdownMaxLineLength);
      truncated = true;
    }

    final info = _classify(line);
    switch (info.kind) {
      case _LineKind.blank:
        flushParagraph();
        flushList();
      case _LineKind.heading:
        flushParagraph();
        flushList();
        final spans = _parseInline(info.text, budget: budget);
        if (spans.isNotEmpty) blocks.add(MdHeading(info.level, spans));
      case _LineKind.rule:
        flushParagraph();
        flushList();
        blocks.add(const MdRule());
      case _LineKind.bullet:
      case _LineKind.ordered:
        flushParagraph();
        totalItems++;
        listItems.add(
          _RawItem(text: info.text, depth: (info.indent ~/ 2).clamp(0, 3), number: info.number),
        );
      case _LineKind.text:
        // Düz metin satırı: açık bir listenin devamıdır (tembel devam) ya da paragrafa eklenir. Bir maddeye
        // aşırı çok devam satırı eklenmez: liste kapanır, satır yeni paragraf olur (içerik kaybolmaz).
        if (listItems.isNotEmpty && listItems.last.parts.length < _kMaxContinuations) {
          listItems.last.parts.add(line.trim());
        } else {
          if (listItems.isNotEmpty) flushList();
          // Sondaki iki boşluk / ters eğik çizgi SERT SATIR SONUDUR: satır kırpılmadan eklenir (flushParagraph
          // sert satır sonunu görür ve sonra kırpar).
          paragraph.add(line);
        }
    }
  }
  flushParagraph();
  flushList();
  if (truncated) blocks.add(const MdTruncated());
  return blocks;
}

class _RawItem {
  _RawItem({required String text, required this.depth, this.number}) : parts = <String>[text];

  /// İlk parça madde metni; sonrakiler tembel devam satırları (doğrusal birleştirme için liste).
  final List<String> parts;
  final int depth;
  final int? number;

  String joined() => parts.length == 1 ? parts.first : parts.map((part) => part.trim()).join(' ');
}

/// Bir maddeye eklenen en çok tembel devam satırı.
const int _kMaxContinuations = 400;

/// Belge başına satır içi bağlantı çözümleme bütçesi (taranan karakter sayısı).
const int _kInlineBudget = 3000000;

/// Çözümleme sırasında harcanan bağlantı tarama adımları.
class _ParseBudget {
  _ParseBudget(this.remaining);

  int remaining;

  bool spend(int steps) {
    remaining -= steps;
    return remaining >= 0;
  }
}

/// Satır içi biçim: `**kalın**`, `[metin](https://…)`, `\` kaçışları.
List<MdSpan> _parseInline(
  String text, {
  bool bold = false,
  bool allowLinks = true,
  required _ParseBudget budget,
}) {
  final spans = <MdSpan>[];
  final literal = StringBuffer();

  void flushLiteral() {
    if (literal.isEmpty) return;
    _addText(spans, literal.toString(), bold);
    literal.clear();
  }

  const escapable = r'\*[]()#-_+.!`~<>|{}';
  var i = 0;
  while (i < text.length) {
    final ch = text[i];

    if (ch == r'\' && i + 1 < text.length && escapable.contains(text[i + 1])) {
      literal.write(text[i + 1]);
      i += 2;
      continue;
    }

    if ((text.startsWith('**', i) || text.startsWith('__', i))) {
      final delimiter = text.substring(i, i + 2);
      final close = text.indexOf(delimiter, i + 2);
      if (close > i + 2 && text.substring(i + 2, close).trim().isNotEmpty) {
        flushLiteral();
        spans.addAll(
          _parseInline(text.substring(i + 2, close), bold: true, allowLinks: allowLinks, budget: budget),
        );
        i = close + 2;
        continue;
      }
      literal.write(delimiter);
      i += 2;
      continue;
    }

    final isImage = ch == '!' && i + 1 < text.length && text[i + 1] == '[';
    if (ch == '[' || isImage) {
      final open = isImage ? i + 1 : i;
      final parsed = _parseBracketLink(text, open, budget);
      if (parsed != null) {
        flushLiteral();
        final label = parsed.label;
        final uri = (isImage || !allowLinks) ? null : _safeHttpsUri(parsed.target);
        // Etiket de biçim içerebilir (kalın); iç içe bağlantı yoktur.
        final inner = _parseInline(label, bold: bold, allowLinks: false, budget: budget);
        if (uri == null) {
          spans.addAll(inner);
        } else {
          final linkText = inner.map((s) => s.text).join();
          final isBold = inner.isNotEmpty && inner.every((s) => s.bold);
          if (linkText.trim().isNotEmpty) {
            spans.add(MdLink(linkText, uri, bold: isBold || bold));
          }
        }
        i = parsed.end;
        continue;
      }
    }

    literal.write(ch);
    i++;
  }
  flushLiteral();
  return _mergeSpans(spans);
}

/// Bağlantı etiketi / hedefi için en çok taranan karakter sayısı.
const int _kMaxLinkLabel = 600;
const int _kMaxLinkTarget = 2100;

class _BracketLink {
  const _BracketLink(this.label, this.target, this.end);

  final String label;
  final String target;
  final int end;
}

/// `[etiket](hedef)` biçimini [open] konumundaki `[` için çözer; biçim bozuksa (ya da bütçe bittiyse) null.
_BracketLink? _parseBracketLink(String text, int open, _ParseBudget budget) {
  var depth = 0;
  var close = -1;
  // Arama penceresi ve belge bütçesi sınırlıdır: kapanmayan `[` yığınları (bozuk girdi) ikinci dereceden
  // süreye yol açmasın.
  final labelEnd = open + _kMaxLinkLabel < text.length ? open + _kMaxLinkLabel : text.length;
  for (var j = open; j < labelEnd; j++) {
    if (!budget.spend(1)) return null;
    final c = text[j];
    if (c == r'\') {
      j++;
      continue;
    }
    if (c == '[') {
      depth++;
    } else if (c == ']') {
      depth--;
      if (depth == 0) {
        close = j;
        break;
      }
    }
  }
  if (close < 0 || close + 1 >= text.length || text[close + 1] != '(') return null;

  var parens = 0;
  var end = -1;
  final targetEnd = close + 1 + _kMaxLinkTarget < text.length ? close + 1 + _kMaxLinkTarget : text.length;
  for (var j = close + 1; j < targetEnd; j++) {
    if (!budget.spend(1)) return null;
    final c = text[j];
    if (c == '(') {
      parens++;
    } else if (c == ')') {
      parens--;
      if (parens == 0) {
        end = j;
        break;
      }
    }
  }
  if (end < 0) return null;
  var target = text.substring(close + 2, end).trim();
  // İsteğe bağlı başlık: `adres "başlık"` (adres boşluk içeremez; başlık tırnaksız metin).
  final space = target.indexOf(' ');
  if (space > 0 && target.endsWith('"')) {
    final rest = target.substring(space).trim();
    if (rest.length >= 2 && rest.startsWith('"') && rest.indexOf('"', 1) == rest.length - 1) {
      target = target.substring(0, space);
    }
  }
  return _BracketLink(text.substring(open + 1, close), target, end + 1);
}

/// Yalnız güvenli bir https adresini döndürür; aksi hâlde null.
Uri? _safeHttpsUri(String candidate) {
  if (candidate.isEmpty || candidate.length > 2000) return null;
  // Adres yalnız yazdırılabilir ASCII olabilir (boşluk, denetim karakteri, görünmez/benzer-görünümlü karakter yok).
  if (candidate.runes.any((c) => c <= 0x20 || c >= 0x7F || c == 0x22 || c == 0x3C || c == 0x3E || c == 0x5C)) {
    return null;
  }
  final uri = Uri.tryParse(candidate);
  if (uri == null) return null;
  if (uri.scheme != 'https') return null;
  if (!uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.userInfo.isNotEmpty) return null;
  return uri;
}

void _addText(List<MdSpan> spans, String text, bool bold) {
  if (text.isEmpty) return;
  spans.add(MdText(text, bold: bold));
}

/// Yan yana aynı kalınlıktaki düz metin parçalarını birleştirir (doğrusal: parçalar tamponda toplanır).
List<MdSpan> _mergeSpans(List<MdSpan> spans) {
  final merged = <MdSpan>[];
  StringBuffer? run;
  var runBold = false;

  void flushRun() {
    final buffer = run;
    if (buffer == null) return;
    merged.add(MdText(buffer.toString(), bold: runBold));
    run = null;
  }

  for (final span in spans) {
    if (span is MdText) {
      if (run != null && runBold != span.bold) flushRun();
      run ??= StringBuffer();
      runBold = span.bold;
      run!.write(span.text);
    } else {
      flushRun();
      merged.add(span);
    }
  }
  flushRun();
  return merged;
}

/// Blokların düz metin dökümü (yalnız test ve erişilebilirlik özeti için).
String legalMarkdownPlainText(List<MdBlock> blocks) {
  final buffer = StringBuffer();
  for (final block in blocks) {
    switch (block) {
      case MdHeading(:final spans):
      case MdParagraph(:final spans):
        buffer.writeln(spans.map((s) => s.text).join());
      case MdList(:final items):
        for (final item in items) {
          final marker = item.number == null ? '-' : '${item.number}.';
          buffer.writeln('$marker ${item.spans.map((s) => s.text).join()}');
        }
      case MdRule():
        buffer.writeln('---');
      case MdTruncated():
        break; // uyarı bloğu belge metni değildir
    }
  }
  return buffer.toString().trim();
}

// --- Widget -----------------------------------------------------------------------------------

/// Bağlantıyı dış uygulamada açar; açılamazsa false.
typedef LegalLinkOpener = Future<bool> Function(Uri uri);

Future<bool> _defaultOpenLink(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Çözümlenmiş Markdown'u gösterir. Metin boyutu ölçeğine uyar (sabit boyut yok); başlıklar ekran
/// okuyucuda başlık, bağlantılar bağlantı olarak okunur (ana makine adıyla).
class LegalMarkdown extends StatefulWidget {
  const LegalMarkdown({super.key, required this.source, this.onOpenLink, this.fullTextUri});

  final String source;

  /// Belge kesildiğinde uyarının altında "Web sayfasını aç" ile açılan tam metin adresi (yalnız https).
  final Uri? fullTextUri;

  /// Bağlantı açıcı (varsayılan: `url_launcher`, dış uygulama). Yalnız https adresleri verilir.
  final LegalLinkOpener? onOpenLink;

  @override
  State<LegalMarkdown> createState() => _LegalMarkdownState();
}

class _LegalMarkdownState extends State<LegalMarkdown> {
  late List<MdBlock> _blocks;
  final Map<MdLink, TapGestureRecognizer> _recognizers =
      Map<MdLink, TapGestureRecognizer>.identity();

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(LegalMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _parse();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _parse() {
    _disposeRecognizers();
    _blocks = parseLegalMarkdown(widget.source);
    void register(List<MdSpan> spans) {
      for (final span in spans) {
        if (span is MdLink) {
          _recognizers[span] = TapGestureRecognizer()..onTap = () => _open(span.uri);
        }
      }
    }

    for (final block in _blocks) {
      switch (block) {
        case MdHeading(:final spans):
        case MdParagraph(:final spans):
          register(spans);
        case MdList(:final items):
          for (final item in items) {
            register(item.spans);
          }
        case MdRule():
        case MdTruncated():
          break;
      }
    }
  }

  Future<void> _open(Uri uri) async {
    // Savunma: çözümleyici yalnız https üretir; yine de açmadan önce yeniden denetlenir.
    if (uri.scheme != 'https' || uri.host.isEmpty) return;
    final opened = await (widget.onOpenLink ?? _defaultOpenLink)(uri);
    if (opened || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Bağlantı açılamadı: ${uri.host}', maxLines: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  TextSpan _spanOf(MdSpan span, TextStyle base, Color linkColor) {
    final weight = span.bold ? FontWeight.w800 : null;
    if (span is MdLink) {
      return TextSpan(
        text: span.text,
        recognizer: _recognizers[span],
        semanticsLabel: '${span.text}, bağlantı, ${span.uri.host}',
        mouseCursor: SystemMouseCursors.click,
        style: base.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
          fontWeight: weight ?? FontWeight.w600,
        ),
      );
    }
    return TextSpan(
      text: span.text,
      style: weight == null ? null : base.copyWith(fontWeight: weight),
    );
  }

  Widget _rich(List<MdSpan> spans, TextStyle style, Color linkColor) {
    return Text.rich(
      TextSpan(
        style: style,
        children: <InlineSpan>[for (final s in spans) _spanOf(s, style, linkColor)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final linkColor = AppTone.primary.ink(p);
    final body = (th.bodyLarge ?? const TextStyle()).copyWith(color: p.text);

    final children = <Widget>[];
    for (var i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      final top = i == 0 ? 0.0 : AppSpace.md;
      switch (block) {
        case MdHeading(:final level, :final spans):
          final style = switch (level) {
            1 => th.titleLarge,
            2 => th.titleMedium,
            _ => body.copyWith(fontWeight: FontWeight.w800),
          };
          children.add(
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpace.lg),
              child: Semantics(
                header: true,
                child: _rich(spans, (style ?? body).copyWith(color: p.text), linkColor),
              ),
            ),
          );
        case MdParagraph(:final spans):
          children.add(Padding(padding: EdgeInsets.only(top: top), child: _rich(spans, body, linkColor)));
        case MdList(:final items):
          children.add(
            Padding(
              padding: EdgeInsets.only(top: top),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final item in items)
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: item.depth * AppSpace.lg,
                        top: AppSpace.xs,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (item.number == null)
                            ExcludeSemantics(child: Text('•', style: body))
                          else
                            Text('${item.number}.', style: body),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(child: _rich(item.spans, body, linkColor)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        case MdRule():
          children.add(
            Padding(
              padding: EdgeInsets.only(top: top),
              child: ExcludeSemantics(child: Divider(color: p.border, height: 1)),
            ),
          );
        case MdTruncated():
          final web = widget.fullTextUri;
          children.add(
            Padding(
              padding: EdgeInsets.only(top: AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const InlineNotice(tone: AppTone.warning, message: kLegalMarkdownTruncatedMessage),
                  if (web != null && web.scheme == 'https')
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => _open(web),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Web sayfasını aç'),
                        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      ),
                    ),
                ],
              ),
            ),
          );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
