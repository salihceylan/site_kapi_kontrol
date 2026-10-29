// Sayaçlar ekranı (MetersView) etiketleri: m² 078'de, "Aidat ve Finans açık olmalı" şartı 079'da, "Fotoğrafla okuma Yakında"
// yazısı fotoğrafla okuma çalışır hale geldiğinde (4C) bayat kaldı. DAVRANIŞ değişmez; yalnız görünen metinler sabitlenir.
// Isı yöntemi adı uzadığı için (m² -> alan payı) dar ekran / büyük yazı taşma matrisi de burada (AGENTS.md kural 6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/meter_models.dart';
import 'package:site_kapi_kontrol/services/meter_api.dart';
import 'package:site_kapi_kontrol/ui/views/help_content.dart';
import 'package:site_kapi_kontrol/ui/views/meters_view.dart';

import 'dialog_layout_harness.dart' show scrollIntoBuilt, settleFor;
import 'list_fixtures.dart' show listMatrix, pumpList, tapFinder;
import 'people_fixtures.dart' show PeopleFakeAuth;

class _FakeMeterService extends MeterService {
  _FakeMeterService({required super.authService, this.tariffs = const <MeterTariff>[]}) : super(api: MeterApi(baseUrl: 'http://localhost'));

  final List<MeterTariff> tariffs;

  @override
  Future<List<MeterTariff>> listTariffs(int siteCode) async => tariffs;

  @override
  Future<List<Meter>> listMeters(int siteCode, {MeterKind? kind}) async => const <Meter>[];

  @override
  Future<List<MeterBilling>> listBillings(int siteCode) async => const <MeterBilling>[];
}

const String _photoHint = 'Fotoğrafla okumak için Sayaçlar sekmesindeki “Fotoğrafla oku” düğmesini kullanın.';
const String _heatLabel = 'Isı payı (ölçüm + alan payı)';

Future<void> _open(
  WidgetTester t, {
  required bool canWrite,
  double width = 400,
  double height = 2400,
  double scale = 1.0,
  bool dark = false,
  List<MeterTariff> tariffs = const <MeterTariff>[],
}) async {
  final auth = PeopleFakeAuth();
  await pumpList(
    t,
    MetersView(
      authService: auth,
      service: _FakeMeterService(authService: auth, tariffs: tariffs),
      sites: <MeterSite>[MeterSite(code: 11, name: 'Gül Sitesi', canWrite: canWrite)],
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
}

/// Sekmeye geçer. Dokunuş `Tab` kutusunun ortasına gider (dar ekran + büyük yazıda sekme METNİ kendi yuvasından taşar; metnin
/// ortası komşu sekmeye düşebilir).
Future<void> _goToTab(WidgetTester t, String label) async {
  await tapFinder(t, find.widgetWithText(Tab, label));
  await settleFor(t, 400);
}

/// Faturalandır sekmesinde tür "Isı", yöntem "Isı payı" seçer (ısı yöntemi yalnız tür Isı iken listelenir).
Future<void> _selectHeatMethod(WidgetTester t) async {
  // Dar ekran + büyük yazıda açıklama paragrafı ilk görünür alanı doldurur; alanlar tembel listede henüz kurulmamıştır.
  final list = find.byType(ListView).first;
  await scrollIntoBuilt(t, find.byType(DropdownButtonFormField<MeterKind>), list);
  await tapFinder(t, find.byType(DropdownButtonFormField<MeterKind>));
  await tapFinder(t, find.text('Isı').last);
  await scrollIntoBuilt(t, find.byType(DropdownButtonFormField<MeterMethod>), list);
  await tapFinder(t, find.byType(DropdownButtonFormField<MeterMethod>));
  expect(find.text(_heatLabel), findsOneWidget, reason: 'açık yöntem listesinde ısı payı adı');
  await tapFinder(t, find.text(_heatLabel));
}

void main() {
  group('dağıtım yöntemi adları (model)', () {
    test('ısı payının alan kısmı m² demez: "alan payı" (m² 078\'de kaldırıldı; arsa payı ya da eşit)', () {
      expect(MeterMethod.unitPrice.label, 'Birim fiyat');
      expect(MeterMethod.invoice.label, 'Fatura tutarı');
      expect(MeterMethod.heat.label, _heatLabel);
      for (final method in MeterMethod.values) {
        expect(method.label, isNot(contains('m²')), reason: method.api);
        expect(method.label, isNot(contains('metrekare')), reason: method.api);
      }
    });
  });

  group('yardım konusu "sayaç"', () {
    test('kesme işareti kopmamış ("Drive’a", "Web’de") ve ısı yöntemi "ölçüm + alan payı" der', () {
      final topic = HelpContent.howToFor(HelpAudience.siteManager).firstWhere((t) => t.id == 'metering');
      final note = topic.note!;
      expect(note, contains('Drive bağlıysa Drive’a, değilse sunucuya kaydedilir'));
      expect(note, contains('Web’de kamera yok'));
      expect(note, contains('Sayaç okuma izni finans / borçlandırma izni vermez'));
      expect(note, isNot(contains('Drive a,')), reason: 'kopuk kesme işareti');
      expect(note, isNot(contains('Webde')), reason: 'kopuk kesme işareti');
      expect(topic.steps.join('\n'), contains('ısı için ölçüm + alan payı'));
      expect(topic.steps.join('\n'), isNot(contains('m²')));
    });
  });

  group('Okuma aktar sekmesi', () {
    testWidgets('yazma yetkisinde: "Fotoğrafla okuma: Yakında…" yok; çalışan düğmeyi gösteren ipucu var', (t) async {
      await _open(t, canWrite: true);
      // İpucunun gösterdiği düğme Sayaçlar sekmesinde gerçekten vardır.
      expect(find.text('Fotoğrafla oku'), findsOneWidget);
      await _goToTab(t, 'Okuma aktar');

      final hint = find.byKey(const ValueKey<String>('meters_import_photo_hint'));
      expect(hint, findsOneWidget);
      expect(t.widget<Text>(hint).data, _photoHint);
      expect(find.textContaining('Yakında'), findsNothing, reason: 'fotoğrafla okuma çalışıyor; "Yakında…" bayat kalmıştı');
      expect(find.textContaining('Fotoğrafla okuma:'), findsNothing);
    });

    testWidgets('salt okur (kurul üyesi): düğme de ipucu da çizilmez; "Yakında…" yok', (t) async {
      await _open(t, canWrite: false);
      expect(find.text('Fotoğrafla oku'), findsNothing, reason: 'düğme yalnız yazma yetkisi olana çizilir');
      await _goToTab(t, 'Okuma aktar');

      expect(find.byKey(const ValueKey<String>('meters_import_photo_hint')), findsNothing);
      expect(find.textContaining('Yakında'), findsNothing);
    });
  });

  group('Faturalandır sekmesi: tarife', () {
    testWidgets('hiç tarife yokken "Önce tarife girin" kurulum yönlendirmesi + Tarife gir düğmesi çıkar; Önizle kapalı; fiyat alanı yok', (t) async {
      await _open(t, canWrite: true);
      await _goToTab(t, 'Faturalandır');

      expect(find.byKey(const ValueKey<String>('billing_tariff_setup')), findsOneWidget);
      expect(find.text('Önce tarife girin'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('billing_setup_tariff')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('billing_price_from_tariff')), findsNothing);
      expect(find.widgetWithText(TextField, 'Birim fiyat (TL / birim)'), findsNothing, reason: 'birim fiyat elle girilmez, tarifeden gelir');
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Önizle')).onPressed, isNull, reason: 'tarifesiz birim fiyat önizlenemez');
    });

    testWidgets('tarife varken yönlendirme çıkmaz; fiyatın tarifeden alındığı yazar ve Önizle açıktır', (t) async {
      await _open(t, canWrite: true, tariffs: const <MeterTariff>[MeterTariff(id: 1, kind: MeterKind.water, unitPriceMinor: 4550, validFrom: '2026-01-01')]);
      await _goToTab(t, 'Faturalandır');

      expect(find.byKey(const ValueKey<String>('billing_tariff_setup')), findsNothing);
      expect(find.byKey(const ValueKey<String>('billing_price_from_tariff')), findsOneWidget);
      expect(find.textContaining('Su: 45,50 ₺ / birim'), findsOneWidget);
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Önizle')).onPressed, isNotNull);
    });
  });

  group('Faturalandır sekmesi', () {
    testWidgets('açıklama "Aidat ve Finans modülü açık olmalı" şartı koymaz (temel modül, 079); borcun yazıldığı yeri söyler', (t) async {
      await _open(t, canWrite: true);
      await _goToTab(t, 'Faturalandır');

      final intro = find.byKey(const ValueKey<String>('meters_billing_intro'));
      expect(intro, findsOneWidget);
      final text = t.widget<Text>(intro).data!;
      expect(text, contains('daire hesaplarına borç olarak yazılır'));
      expect(text.toLowerCase(), isNot(contains('modül')), reason: 'Aidat ve Finans her sitede açıktır; koşul gibi sunulmaz');
      expect(find.textContaining('modülü de açık'), findsNothing);
    });

    testWidgets('tür Isı iken yöntem listesi "Isı payı (ölçüm + alan payı)" der; ekranda m² geçmez', (t) async {
      await _open(t, canWrite: true);
      await _goToTab(t, 'Faturalandır');

      await tapFinder(t, find.byType(DropdownButtonFormField<MeterKind>));
      await tapFinder(t, find.text('Isı').last);
      await tapFinder(t, find.byType(DropdownButtonFormField<MeterMethod>));
      expect(find.text(_heatLabel), findsOneWidget);
      expect(find.text('Birim fiyat'), findsWidgets);
      expect(find.text('Fatura tutarı'), findsWidgets);

      await tapFinder(t, find.text(_heatLabel));
      // Seçili yöntem alanda görünür; açıklama alan payının dağıtım tabanını yönetimin seçtiğini söyler (K5: kod arsa payına kendiliğinden geçmez) ve "Alan payı tabanı" seçicisi görünür.
      expect(find.text(_heatLabel), findsOneWidget);
      expect(find.textContaining('Gider; ölçüme göre ve alan payıyla, platform kuralındaki oranla (varsayılan %70 / %30) paylaştırılır. Alan payının dağıtım tabanını siz seçersiniz.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('billing_area_basis')), findsOneWidget);
      expect(find.textContaining('m²'), findsNothing, reason: '078: daire alanı sistemde yok; ekranda m² geçmemeli');
      expect(find.textContaining('metrekare'), findsNothing);
    });

    testWidgets('ısı yöntemi yalnız tür Isı iken listelenir (davranış aynı)', (t) async {
      await _open(t, canWrite: true);
      await _goToTab(t, 'Faturalandır');

      await tapFinder(t, find.byType(DropdownButtonFormField<MeterMethod>));
      expect(find.text(_heatLabel), findsNothing, reason: 'varsayılan tür Su: ısı payı seçeneği yok');
      expect(find.text('Birim fiyat'), findsWidgets);
    });

    listMatrix('Isı yöntemi seçiliyken', (t, width, height, scale, dark) async {
      await _open(t, canWrite: true, width: width, height: height, scale: scale, dark: dark);
      await _goToTab(t, 'Faturalandır');
      await _selectHeatMethod(t);
      expect(find.textContaining('Gider; ölçüme göre ve alan payıyla'), findsOneWidget);
    });
  });
}
