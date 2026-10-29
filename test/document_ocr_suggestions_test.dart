// "Görselden oku" (P2-13): düğme yalnız desteklenen platformda ve görselde görünür; öneri, kullanıcı dokunmadan forma yazılmaz. Sahte okuyucu; ML Kit ve ağ yok.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/document_text_reader.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_ocr_suggestions.dart';

class _FakeReader implements DocumentTextReader {
  _FakeReader({this.supported = true, this.text});

  @override
  final bool supported;
  final String? text;
  int calls = 0;

  @override
  Future<String?> read(Uint8List imageBytes) async {
    calls++;
    return text;
  }
}

final Uint8List _jpeg = Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xe0, 0, 0]);
final Uint8List _pdf = Uint8List.fromList('%PDF-1.7 x'.codeUnits);

const String _text = 'İşlem Tarihi: 15.10.2026\nTutar: 1.250,50 TL\nGönderen IBAN: TR33 0006 1005 1978 6457 8413 26';

Future<void> _pump(WidgetTester t, Widget child) => t.pumpWidget(
  MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  testWidgets('düğme gizli: desteklenmeyen platform, dosya yok, PDF', (t) async {
    final unsupported = _FakeReader(supported: false, text: _text);
    await _pump(t, DocumentOcrSuggestions(key: UniqueKey(), bytes: _jpeg, reader: unsupported, onAmount: (_) {}));
    expect(find.byKey(const ValueKey<String>('ocr_read')), findsNothing);

    await _pump(
      t,
      DocumentOcrSuggestions(
        bytes: null,
        reader: _FakeReader(text: _text),
        onAmount: (_) {},
      ),
    );
    expect(find.byKey(const ValueKey<String>('ocr_read')), findsNothing);

    await _pump(
      t,
      DocumentOcrSuggestions(
        bytes: _pdf,
        reader: _FakeReader(text: _text),
        onAmount: (_) {},
      ),
    );
    expect(find.byKey(const ValueKey<String>('ocr_read')), findsNothing);
    expect(unsupported.calls, 0);
  });

  testWidgets('okuyunca öneri çıkar; dokunmadan hiçbir şey yazılmaz, dokununca yalnız o değer yazılır', (t) async {
    final reader = _FakeReader(text: _text);
    int? amount;
    DateTime? date;
    String? iban;
    await _pump(
      t,
      DocumentOcrSuggestions(
        bytes: _jpeg,
        reader: reader,
        notBefore: DateTime(2025, 10, 21),
        notAfter: DateTime(2026, 10, 21),
        onAmount: (m) => amount = m,
        onDate: (d) => date = d,
        onIban: (i) => iban = i,
      ),
    );
    expect(find.byKey(const ValueKey<String>('ocr_read')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('ocr_panel')), findsNothing);

    await t.tap(find.byKey(const ValueKey<String>('ocr_read')));
    await t.pumpAndSettle();
    expect(reader.calls, 1);
    expect(find.byKey(const ValueKey<String>('ocr_panel')), findsOneWidget);
    expect(find.text('1.250,50 ₺'), findsOneWidget);
    expect(find.text('15.10.2026'), findsOneWidget);
    // Hiçbir adaya dokunulmadı: forma hiçbir şey yazılmadı.
    expect(amount, isNull);
    expect(date, isNull);
    expect(iban, isNull);

    await t.tap(find.byKey(const ValueKey<String>('ocr_amount_0')));
    await t.pumpAndSettle();
    expect(amount, 125050);
    expect(date, isNull);
    expect(iban, isNull);

    await t.tap(find.byKey(const ValueKey<String>('ocr_iban_0')));
    await t.pumpAndSettle();
    expect(iban, 'TR330006100519786457841326');
  });

  testWidgets('okunamayan görsel ve boş sonuç dürüstçe söylenir; verilmeyen alan türü için aday gösterilmez', (t) async {
    await _pump(t, DocumentOcrSuggestions(key: UniqueKey(), bytes: _jpeg, reader: _FakeReader(), onAmount: (_) {}));
    await t.tap(find.byKey(const ValueKey<String>('ocr_read')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('ocr_failed')), findsOneWidget);

    // Yalnız tutar alanı olan form: tarih / IBAN adayları sunulmaz.
    await _pump(
      t,
      DocumentOcrSuggestions(
        key: UniqueKey(),
        bytes: _jpeg,
        reader: _FakeReader(text: _text),
        onAmount: (_) {},
      ),
    );
    await t.tap(find.byKey(const ValueKey<String>('ocr_read')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('ocr_amount_0')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('ocr_date_0')), findsNothing);
    expect(find.byKey(const ValueKey<String>('ocr_iban_0')), findsNothing);
  });
}
