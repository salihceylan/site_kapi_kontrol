// Platform Faz 2a: bağımsız inceleme düzeltmeleri (F1-F24) için davranış testleri.
//
// Kapsam: telefon yapıştırma (F1), seçici erişilebilirliği (F2), taşınma tarihi kuralı (F3), hata
// bildiriminin görünürlüğü (F5), çift dokunuş / geri tuşu koruması (F6, F7), kilitli telefon (F8), araç
// kaldır düğmesi (F9), arama (F10), site sayfalama (F11), iç kart değişikliği (F12), geçmiş biçimleri
// (F13, F14, F22), bayat yükleme (F15), ilişki gövdesi (F16), tek bilgilendirme bandı (F17), kurul üyesi
// notları (F18), isimsiz kişi (F19), tarih alanı (F20), alan (m²) girişi (F21), plaka / e-posta (F24).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/history_item.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_edit_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/dialogs/end_residency_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/history_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/residency_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/vehicle_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/audit_log_view.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/person_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/vehicle_card.dart';

import '../design/harness.dart';
import 'dialog_layout_harness.dart';
import 'list_fixtures.dart' show pumpList, tapFinder, tapText;
import 'people_fixtures.dart';

PeopleScope _scope(PeopleFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

Future<void> _open(
  WidgetTester t,
  Future<void> Function(BuildContext context) opener, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
}) async {
  await openDialogAt(t, opener, width: width, height: height, scale: scale, dark: false);
  await settleFor(t);
}

Future<void> _enter(WidgetTester t, String key, String text) async {
  // Üst üste açılan pencerelerde aynı anahtar birden çok olabilir: en üstteki (son) pencere.
  final field = find.byKey(ValueKey<String>(key)).last;
  await scrollTo(t, field);
  await t.enterText(field, text);
  await t.pump();
}

String _fieldText(WidgetTester t, String key) {
  final field = find.descendant(
    of: find.byKey(ValueKey<String>(key)).last,
    matching: find.byType(EditableText),
  );
  return t.widget<EditableText>(field).controller.text;
}

TextField _textField(WidgetTester t, String key) => t.widget<TextField>(
  find.descendant(of: find.byKey(ValueKey<String>(key)), matching: find.byType(TextField)),
);

/// Üstteki (en son açılan) pencerenin düğmesine dokunur.
Future<void> _tapLast(WidgetTester t, String label) async {
  final target = find.text(label).last;
  await scrollTo(t, target);
  await t.tap(target);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> _pickApartment(WidgetTester t, String fieldKey, String label) async {
  final field = find.byKey(ValueKey<String>(fieldKey));
  await scrollTo(t, field);
  await t.tap(field);
  await settleFor(t);
  final target = find.descendant(of: find.byType(AppCard), matching: find.text(label)).last;
  await scrollTo(t, target);
  await t.tap(target);
  await settleFor(t);
}


/// Hata bildiriminin, kaydırılabilir pencere alanının İÇİNDE (görünür) olduğunu doğrular.
void _expectNoticeInViewport(WidgetTester t) {
  final notice = find.byType(InlineNotice);
  expect(notice, findsWidgets);
  final viewport = t.getRect(
    find.descendant(of: find.byType(AlertDialog), matching: find.byType(SingleChildScrollView)).first,
  );
  final rect = t.getRect(notice.first);
  expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.5), reason: 'hata bildirimi görünür alanın üstünde kalmış');
  expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.5), reason: 'hata bildirimi görünür alanın altında kalmış');
}

Future<void> _pumpView(
  WidgetTester t,
  PeopleFakeAuth auth, {
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool manage = true,
  List<PeopleSite> readOnly = const <PeopleSite>[],
}) async {
  await pumpList(
    t,
    PeopleView(authService: auth, manageSites: manage, readOnlySites: readOnly),
    width: width,
    height: height,
    scale: scale,
    dark: false,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
}

void main() {
  group('F1 telefon yapıştırma (formda)', () {
    testWidgets('"+90 " alanına +905321234567 yapıştırmak doğru numarayı verir; kaydedilen numara +905321234567', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_name', 'Ali Veli');
      // Yapıştırma sonrası alan metni: "+90 " + yapıştırılan.
      await _enter(t, 'person_phone', '+90 +905321234567');
      expect(_fieldText(t, 'person_phone'), '+90 532 123 45 67');
      await _tapLast(t, 'Kaydet');
      await settleFor(t);
      expect(auth.createPersonCalls.single['phone'], '+905321234567');
    });

    testWidgets('0532... ve 0090... yapıştırma: son hane kaybolmaz; çift yapıştırma tek numara bırakır', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_phone', '+90 05321234567');
      expect(_fieldText(t, 'person_phone'), '+90 532 123 45 67');
      await _enter(t, 'person_phone', ''); // alanı hazır "+90 " durumuna döndür
      await _enter(t, 'person_phone', '+90 00905321234567');
      expect(_fieldText(t, 'person_phone'), '+90 532 123 45 67');
      await _enter(t, 'person_phone', '+90 532 123 45 67+905321234567');
      expect(_fieldText(t, 'person_phone'), '+90 532 123 45 67');
    });

    testWidgets('11+ hane sessizce kırpılmaz: giriş REDDEDİLİR (alan değişmez), sunucuya yanlış numara gitmez', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_name', 'Ali Veli');
      await _enter(t, 'person_phone', '+90 53212345678');
      expect(_fieldText(t, 'person_phone'), '+90 ', reason: '11 hane girişte reddedilir');
      await _enter(t, 'person_email', 'ali@example.com');
      await _tapLast(t, 'Kaydet');
      await settleFor(t);
      expect(auth.createPersonCalls.single['phone'], isNull, reason: 'telefon boş kaldı; kırpılmış yanlış numara kaydolmadı');
    });
  });

  group('F2 seçici alanı erişilebilirliği', () {
    testWidgets('hata metni ve "Seçimi temizle" düğmesi anlamsal ağaçta kalır', (t) async {
      final handle = t.ensureSemantics();
      await pumpAt(
        t,
        Padding(
          padding: const EdgeInsets.all(16),
          child: CrmPickerField(
            label: 'Daire',
            icon: Icons.apartment_rounded,
            value: 'A Blok - 5',
            errorText: 'Bir daire seçin.',
            onTap: () {},
            onClear: () {},
          ),
        ),
        width: 400,
        height: 600,
        scale: 1.0,
      );
      expect(find.bySemanticsLabel(RegExp('Bir daire seçin')), findsOneWidget,
          reason: 'hata metni ekran okuyucudan gizlenmemeli');
      final clear = t.getSemantics(find.byTooltip('Seçimi temizle'));
      expect(clear.getSemanticsData().tooltip, contains('Seçimi temizle'),
          reason: 'temizle düğmesi erişilebilir kalmalı');
      expect(clear.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
          reason: 'temizle düğmesinin kendi dokunma eylemi var');
      expect(find.bySemanticsLabel(RegExp('A Blok - 5')), findsWidgets);
      handle.dispose();
    });

    testWidgets('formda gerçek akış: daire seçilmeden Kaydet -> hata metni anlamsal ağaçta', (t) async {
      final handle = t.ensureSemantics();
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => ResidencyDialog.show(c, scope: _scope(auth), personId: 1));
      await _tapLast(t, 'Kaydet');
      expect(find.text('Bir daire seçin.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Bir daire seçin')), findsOneWidget);
      handle.dispose();
    });
  });

  group('F3 taşınma tarihi giriş tarihinden önce olamaz', () {
    testWidgets('giriş 05.03.2024: 01.01.2020 reddedilir; giriş günü ve sonrası kabul edilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getPerson(11, 1);
      await _open(
        t,
        (c) => EndResidencyDialog.show(
          c,
          scope: _scope(auth),
          residency: detail.currentResidencies.single,
          personName: detail.fullName,
          hasAccount: false,
        ),
      );
      await _enter(t, 'end_residency_date', '01012020');
      await _tapLast(t, 'Taşındı Olarak İşaretle');
      expect(find.text('Taşınma tarihi giriş tarihinden önce olamaz.'), findsOneWidget);
      expect(auth.endResidencyCalls, isEmpty);

      await _enter(t, 'end_residency_date', '05032024');
      await _tapLast(t, 'Taşındı Olarak İşaretle');
      await settleFor(t);
      expect(auth.endResidencyCalls.single.date, DateTime(2024, 3, 5), reason: 'giriş günü kabul edilir');
    });
  });

  group('F5 hata bildirimi görünür konuma gelir (320x640, yazı 2,0)', () {
    testWidgets('kişi formu: uzun formun altında Kaydet -> hata bildirimi görünür alanda', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..writeError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)), width: 320, height: 640, scale: 2.0);
      await _enter(t, 'person_name', 'Ali Veli');
      await _enter(t, 'person_email', 'ali@example.com');
      await scrollTo(t, find.byKey(const ValueKey<String>('person_note')));
      await _tapLast(t, 'Kaydet');
      await settleFor(t);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      _expectNoticeInViewport(t);
    });

    testWidgets('daire düzenleme: alttan Kaydet -> hata bildirimi görünür alanda', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..writeError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      final detail = await auth.getApartment(11, 301);
      await _open(
        t,
        (c) => ApartmentEditDialog.show(c, scope: _scope(auth), apartment: detail),
        width: 320,
        height: 640,
        scale: 2.0,
      );
      await _enter(t, 'apartment_floor', '4');
      await scrollTo(t, find.byKey(const ValueKey<String>('apartment_party')));
      await _tapLast(t, 'Kaydet');
      await settleFor(t);
      _expectNoticeInViewport(t);
    });

    testWidgets('araç / ilişki / taşındı pencerelerinde de hata bildirimi görünür alanda', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..writeError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _open(
        t,
        (c) => VehicleDialog.show(c, scope: _scope(auth), person: null),
        width: 320,
        height: 640,
        scale: 2.0,
      );
      await _pickPerson(t);
      await _enter(t, 'vehicle_plate', '35 KLM 77');
      await scrollTo(t, find.byKey(const ValueKey<String>('vehicle_note')));
      await _tapLast(t, 'Ekle');
      await settleFor(t);
      _expectNoticeInViewport(t);
    });
  });

  group('F6 çift dokunuş koruması', () {
    testWidgets('seçici satırına çift dokunuş üst formu KAPATMAZ', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      final field = find.byKey(const ValueKey<String>('person_apartment'));
      await scrollTo(t, field);
      await t.tap(field);
      await settleFor(t);
      final row = find.descendant(of: find.byType(AppCard), matching: find.text('B Blok - 2')).last;
      await scrollTo(t, row);
      // Çift dokunuş: iki `onTap` aynı karede (animasyon göstergesi tepki vermeden) çağrılır.
      final onTap = t.widget<AppCard>(find.ancestor(of: row, matching: find.byType(AppCard)).first).onTap!;
      onTap();
      onTap();
      await settleFor(t);
      expect(find.text('Kişi Ekle'), findsOneWidget, reason: 'üst form açık kalmalı');
      expect(find.text('B Blok - 2'), findsOneWidget, reason: 'seçilen daire alana yazıldı');
    });

    testWidgets('Vazgeç\'e çift dokunuş yalnız pencereyi kapatır, altındaki sayfayı değil', (t) async {
      final auth = PeopleFakeAuth.seeded();
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        harnessApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (inner) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () => PersonFormDialog.show(inner, scope: _scope(auth)),
                        child: const Text('Aç'),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('Sayfa'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Sayfa'));
      await settleFor(t);
      await t.tap(find.text('Aç'));
      await settleFor(t);
      expect(find.text('Kişi Ekle'), findsOneWidget);

      // Çift dokunuş: iki `onPressed` aynı karede çağrılır.
      final onPressed = t.widget<TextButton>(find.widgetWithText(TextButton, 'Vazgeç')).onPressed!;
      onPressed();
      onPressed();
      await settleFor(t);
      expect(find.text('Kişi Ekle'), findsNothing, reason: 'pencere kapandı');
      expect(find.text('Aç'), findsOneWidget, reason: 'alttaki sayfa (ikinci pop) kapanmadı');
    });
  });

  group('F7 gönderim sürerken geri tuşu', () {
    testWidgets('kaydetme sürerken geri tuşu pencereyi kapatmaz; bitince kapanır', (t) async {
      final auth = PeopleFakeAuth.seeded()..writeGate = Completer<void>();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_name', 'Ali Veli');
      await _enter(t, 'person_email', 'ali@example.com');
      await _tapLast(t, 'Kaydet');
      expect(find.text('Kaydediliyor...'), findsOneWidget);

      await t.binding.handlePopRoute();
      await settleFor(t);
      expect(find.text('Kişi Ekle'), findsOneWidget, reason: 'gönderim sürerken geri tuşu yok sayıldı');

      auth.writeGate!.complete();
      await settleFor(t);
      await t.pump(const Duration(milliseconds: 500)); // kapanış animasyonu bir sonraki karede başlar
      expect(find.text('Kişi Ekle'), findsNothing);
    });

    testWidgets('gönderim yokken geri tuşu pencereyi kapatır (araç, daire düzenleme ve ilişki pencereleri de korumalı)', (t) async {
      final auth = PeopleFakeAuth.seeded()..writeGate = Completer<void>();
      await _open(t, (c) => VehicleDialog.show(c, scope: _scope(auth)));
      await t.binding.handlePopRoute();
      await settleFor(t);
      expect(find.text('Araç Ekle'), findsNothing);

      final detail = await auth.getApartment(11, 301);
      await _open(t, (c) => ApartmentEditDialog.show(c, scope: _scope(auth), apartment: detail));
      await _enter(t, 'apartment_floor', '5');
      await _tapLast(t, 'Kaydet');
      expect(find.text('Kaydediliyor...'), findsOneWidget);
      await t.binding.handlePopRoute();
      await settleFor(t);
      expect(find.text('Daireyi Düzenle'), findsOneWidget);
      auth.writeGate!.complete();
      await settleFor(t);
    });
  });

  group('F8 hesaplı kişide kilitli telefon olduğu gibi gösterilir', () {
    testWidgets('yabancı numara bozulmaz ve kişi kartıyla aynıdır; boş telefonda "+90 " öneki yok', (t) async {
      final auth = PeopleFakeAuth.seeded();
      auth.peopleJson[6] = pplPersonJson(6, 'Yabancı Hesap', phone: '+4915112345678', account: true);
      auth.peopleJson[7] = pplPersonJson(7, 'Telefonsuz Hesap', account: true);

      final foreign = await auth.getPerson(11, 6);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: foreign));
      expect(_fieldText(t, 'person_phone'), '+4915112345678');
      await t.tap(find.text('Vazgeç'));
      await settleFor(t);

      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 6));
      expect(find.text('+4915112345678'), findsOneWidget, reason: 'kişi kartı da aynı ham değeri gösterir');
      await t.tap(find.text('Kapat'));
      await settleFor(t);

      final empty = await auth.getPerson(11, 7);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: empty));
      expect(_fieldText(t, 'person_phone'), '');
    });
  });

  group('F9 araç kaldır düğmesi', () {
    testWidgets('kişi kartında 48 dp ve "{plaka} plakalı aracı kaldır" ipucu / anlamı', (t) async {
      final handle = t.ensureSemantics();
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1));
      final button = _removeFor('34 ABC 123');
      expect(button, findsOneWidget);
      final size = t.getSize(button);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      final semantics = t.getSemantics(button).getSemanticsData();
      expect(semantics.tooltip, '34 ABC 123 plakalı aracı kaldır');
      expect(semantics.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('araç listesinde 48 dp ve plakalı ipucu', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pumpView(t, auth);
      await tapFinder(t, find.byKey(const ValueKey<String>('people_tab_2')));
      await settleFor(t);
      final button = _removeFor('06 XYZ 789');
      expect(button, findsOneWidget);
      expect(t.getSize(button).height, greaterThanOrEqualTo(48));
      expect(t.getSize(button).width, greaterThanOrEqualTo(48));
    });
  });

  group('F10 daire araması: blok-daire etiketi ve güncel sakin adları', () {
    testWidgets('ipucu "Daire no, blok veya kişi adı"; aile üyesi adıyla da bulunur', (t) async {
      final auth = PeopleFakeAuth.seeded();
      (auth.apartmentsJson[301]!['current_residents'] as List).add(
        pplResidentJson(150, 7, 'Zeynep Aile', ResidencyRelation.familyMember),
      );
      await _pumpView(t, auth);
      await tapFinder(t, find.byKey(const ValueKey<String>('people_tab_1')));
      await settleFor(t);
      expect(find.text('Daire no, blok veya kişi adı'), findsOneWidget);

      await t.enterText(find.byKey(const ValueKey<String>('apartments_search')), 'aile');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(auth.apartmentCalls.last.query, 'aile');
      expect(find.text('A Blok - 5'), findsOneWidget, reason: 'aile üyesi sakin adıyla daire bulundu');
      expect(find.text('A Blok - 6'), findsNothing);
    });
  });

  group('F11 süper kullanıcı site seçici ilk 100 siteyle sınırlı değil', () {
    testWidgets('150 onaylı site iki sayfada toplanır (onaylı süzgeci istekte)', (t) async {
      final sites = [for (var i = 1; i <= 150; i++) pplSite(1000 + i, 'Site $i')];
      final auth = PeopleFakeAuth(sites: sites, role: UserRole.superUser);
      await _pumpView(t, auth);
      expect(auth.listSitesArgs.map((a) => a.page).toList(), <int>[1, 2]);
      expect(auth.listSitesArgs.every((a) => a.approval == 'approved' && a.pageSize == 100), isTrue);
      final dropdown = t.widget<DropdownButton<int>>(find.byType(DropdownButton<int>).first);
      expect(dropdown.items, hasLength(150));
    });
  });

  group('F12 "Kişiyi Aç" iç kartındaki değişiklik dış listeyi tazeler', () {
    testWidgets('mevcut kişinin telefonu iç karttan değişir -> Kişiler listesi yeniden çekilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pumpView(t, auth);
      final before = auth.peopleCalls.length;
      await tapText(t, 'Kişi Ekle');
      await _enter(t, 'person_name', 'Yinelenen');
      await _enter(t, 'person_email', 'ayse@example.com');
      await _tapLast(t, 'Kaydet');
      await settleFor(t);
      expect(find.text('Kişiyi Aç'), findsOneWidget);

      await _tapLast(t, 'Kişiyi Aç');
      await settleFor(t);
      expect(auth.getPersonCalls, <int>[1]);

      await _tapLast(t, 'Düzenle');
      await _enter(t, 'person_phone', '5324445566');
      await _tapLast(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updatePersonCalls.single.fields, <String, Object?>{'phone': '+905324445566'});
      expect(auth.peopleCalls.length, greaterThan(before), reason: 'dış liste yeniden çekildi');
      expect(find.text('+90 532 444 55 66'), findsWidgets);
    });
  });

  group('F13/F14/F22 geçmiş', () {
    testWidgets('denetim süzgecinde "Daire silindi"; etiketler Türkçe', (t) async {
      expect(
        AuditLogView.actionFilters.contains(('apartment.deleted', 'Daire silindi')),
        isTrue,
      );
      expect(pplHistory(1, action: 'apartment.deleted', changes: const []).actionLabel, 'Daire silindi');
      expect(pplHistory(1, action: 'bilinmeyen.eylem', changes: const []).actionLabel, 'Diğer işlem');
    });

    testWidgets('değerler Türkçe gösterilir; telefon / e-posta / not değeri gelse bile gizlenir', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..historyPages = <HistoryPage>[
          HistoryPage(items: <HistoryItem>[
            pplHistory(3, changes: const [
              {'field': 'phone', 'from': '+905551112233', 'to': '+905324445566'},
              {'field': 'email', 'from': 'a@x.co', 'to': 'b@x.co'},
              {'field': 'note', 'from': 'eski', 'to': 'yeni'},
              {'field': 'relation', 'from': 'owner', 'to': 'tenant'},
              {'field': 'is_active', 'from': true, 'to': false},
              {'field': 'responsible_party', 'from': 'both', 'to': 'owner'},
              {'field': 'move_in_date', 'from': '2024-03-05', 'to': '2025-01-02'},
              {'field': 'gross_area_m2', 'from': 120.5, 'to': 100},
            ]),
          ]),
        ];
      await _open(
        t,
        (c) => HistoryDialog.show(c, scope: _scope(auth), targetType: 'person', targetId: 1, title: 'Ayşe'),
      );
      expect(find.text('Telefon güncellendi'), findsOneWidget);
      expect(find.text('E-posta güncellendi'), findsOneWidget);
      expect(find.text('Not güncellendi'), findsOneWidget);
      expect(find.textContaining('+905'), findsNothing);
      expect(find.textContaining('b@x.co'), findsNothing);
      expect(find.text('İlişki: Malik → Kiracı'), findsOneWidget);
      expect(find.text('Durum: Aktif → Pasif'), findsOneWidget);
      expect(find.text('Borç ve bildirim muhatabı: Malik ve kiracı → Malik'), findsOneWidget);
      expect(find.text('Giriş tarihi: 05.03.2024 → 02.01.2025'), findsOneWidget);
      expect(find.text('Brüt m²: 120,5 m² → 100 m²'), findsOneWidget);
      expect(find.textContaining('owner'), findsNothing);
      expect(find.textContaining('true'), findsNothing);
    });

    testWidgets('320 dp x2,0: "Daire bilgisi güncellendi" etiketi KIRPILMAZ (sarar)', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..historyPages = <HistoryPage>[
          HistoryPage(items: <HistoryItem>[pplHistory(3, action: 'apartment.updated', changes: const [])]),
        ];
      await _open(
        t,
        (c) => HistoryDialog.show(c, scope: _scope(auth), targetType: 'apartment', targetId: 301, title: 'A Blok - 5'),
        width: 320,
        height: 640,
        scale: 2.0,
      );
      final text = find.text('Daire bilgisi güncellendi');
      expect(text, findsOneWidget);
      final widget = t.widget<Text>(text);
      expect(widget.maxLines, isNull);
      expect(widget.overflow, isNot(TextOverflow.ellipsis));
      final render = t.renderObject<RenderParagraph>(text);
      expect(render.didExceedMaxLines, isFalse);
    });
  });

  group('F15 bayat yükleme yeni yazma sonucunu ezmez', () {
    testWidgets('kişi kartı: araç kaldırma sonrası yeniden yükleme sürerken not düzenlenir; geç gelen eski yanıt yok sayılır', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1));
      expect(find.text('Kapıcıya haber verildi.'), findsOneWidget);

      // Kaldırma sonrası yeniden yükleme kapıda bekler (anlık görüntü eski notu taşır).
      auth.personGate = Completer<void>();
      await tapFinder(t, _removeFor('34 ABC 123'));
      await _tapLast(t, 'Kaldır');
      await settleFor(t);
      expect(auth.removeVehicleCalls, <int>[1]);

      await _tapLast(t, 'Düzenle');
      await _enter(t, 'person_note', 'Yeni not');
      await _tapLast(t, 'Kaydet');
      await settleFor(t);
      expect(find.text('Yeni not'), findsOneWidget);

      auth.personGate!.complete(); // eski yükleme (eski notlu) geç gelir
      await settleFor(t);
      expect(find.text('Yeni not'), findsOneWidget, reason: 'bayat yanıt yeni yazma sonucunu ezmedi');
      expect(find.text('Kapıcıya haber verildi.'), findsNothing);
    });
  });

  group('F16 ilişki düzenleme gövdesi', () {
    testWidgets('giriş tarihi silinirse açıkça temizlenir; ilişki değişmediği için gönderilmez', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1));
      await _tapLast(t, 'İlişkiyi Düzenle');
      await _enter(t, 'residency_move_in', '');
      await _tapLast(t, 'Kaydet');
      await settleFor(t);
      final call = auth.updateResidencyCalls.single;
      expect(call.clear, isTrue);
      expect(call.date, isNull);
      expect(call.relation, isNull, reason: 'ilişki değişmedi');
      expect(find.text('Giriş: -'), findsOneWidget);
      expect(find.text('İlişki güncellendi.'), findsOneWidget);
    });

    testWidgets('hiçbir şey değişmediyse sunucuya gidilmez, "güncellendi" denmez, pencere kapanır', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1));
      await _tapLast(t, 'İlişkiyi Düzenle');
      await _tapLast(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updateResidencyCalls, isEmpty);
      expect(find.text('İlişki güncellendi.'), findsNothing);
      expect(find.text('Giriş tarihi (isteğe bağlı)'), findsNothing, reason: 'pencere kapandı');
    });

    testWidgets('yeni giriş tarihi gönderilir (ilişki değişmeden)', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1));
      await _tapLast(t, 'İlişkiyi Düzenle');
      await _enter(t, 'residency_move_in', '5.3.2023');
      expect(_fieldText(t, 'residency_move_in'), '05.03.2023');
      await _tapLast(t, 'Kaydet');
      await settleFor(t);
      final call = auth.updateResidencyCalls.single;
      expect(call.date, DateTime(2023, 3, 5));
      expect(call.relation, isNull);
      expect(call.clear, isFalse);
    });
  });

  group('F17 hesap bilgilendirmesi', () {
    testWidgets('kişi kartı: dahili hesapta e-posta düzenlenebilir uyarısı; kayıtlı hesapta eski metin; salt okunurda e-posta uyarısı yok', (t) async {
      final auth = PeopleFakeAuth.seeded();
      auth.peopleJson[4] = pplPersonJson(4, 'Dahili Hesap', account: true, accountKind: 'internal', email: 'i@x.co');
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 4));
      expect(
        find.text('Ad ve telefon kişinin kendi profilinden değişir. İletişim e-postası Düzenle ile değiştirilebilir.'),
        findsOneWidget,
      );
      await t.tap(find.text('Kapat'));
      await settleFor(t);

      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth, canWrite: false), personId: 4));
      expect(find.text('Ad ve telefon kişinin kendi profilinden değişir.'), findsOneWidget);
      await t.tap(find.text('Kapat'));
      await settleFor(t);

      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 2));
      expect(find.text('Kişinin kendi profilinden değişir'), findsOneWidget);
    });
  });

  group('F18 salt okunur kurul üyesi notları görmez', () {
    testWidgets('kişi kartında kişi ve araç notu yalnız yazma yetkisinde görünür', (t) async {
      final auth = PeopleFakeAuth.seeded();
      (auth.peopleJson[1]!['vehicles'] as List).first['note'] = 'gri araç';
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1));
      expect(find.text('Kapıcıya haber verildi.'), findsOneWidget);
      expect(find.text('gri araç'), findsOneWidget);
      await t.tap(find.text('Kapat'));
      await settleFor(t);

      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth, canWrite: false), personId: 1));
      expect(find.text('34 ABC 123'), findsOneWidget);
      expect(find.text('Kapıcıya haber verildi.'), findsNothing);
      expect(find.text('gri araç'), findsNothing);
      expect(find.text('Not'), findsNothing);
    });

    testWidgets('araç listesinde not yalnız yazma yetkisinde görünür', (t) async {
      final auth = PeopleFakeAuth.seeded();
      auth.vehiclesJson.first['note'] = 'gri araç';
      await _pumpView(t, auth);
      await tapFinder(t, find.byKey(const ValueKey<String>('people_tab_2')));
      await settleFor(t);
      expect(find.text('gri araç'), findsOneWidget);

      await _pumpView(
        t,
        auth,
        manage: false,
        readOnly: const <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')],
      );
      await tapFinder(t, find.byKey(const ValueKey<String>('people_tab_2')));
      await settleFor(t);
      expect(find.byType(VehicleCard), findsWidgets);
      expect(find.text('gri araç'), findsNothing);
    });
  });

  group('F19 isimsiz kişi', () {
    testWidgets('malik / kiracı adı boşsa "İsimsiz kişi" (liste, daire kartı, seçici)', (t) async {
      final auth = PeopleFakeAuth.seeded();
      auth.apartmentsJson[303]!['owner'] = <String, dynamic>{'person_id': 9, 'full_name': ''};
      auth.apartmentsJson[303]!['tenant'] = <String, dynamic>{'person_id': 10, 'full_name': '  '};
      await _pumpView(t, auth);
      await tapFinder(t, find.byKey(const ValueKey<String>('people_tab_1')));
      await settleFor(t);
      expect(find.text('Malik: İsimsiz kişi'), findsOneWidget);
      expect(find.text('Kiracı: İsimsiz kişi'), findsOneWidget);
      expect(find.text('Malik: '), findsNothing);

      await _open(t, (c) => ApartmentCardDialog.show(c, scope: _scope(auth), apartmentId: 303));
      expect(find.text('İsimsiz kişi'), findsNWidgets(2), reason: 'kartta malik ve kiracı satırı');
      await t.tap(find.text('Kapat'));
      await settleFor(t);

      await _open(t, (c) async => showApartmentPicker(c, _scope(auth)));
      expect(find.text('Malik: İsimsiz kişi • Kiracı: İsimsiz kişi'), findsOneWidget);
    });
  });

  group('F20 tarih alanı', () {
    testWidgets('formda ayırıcılı yapıştırma GG.AA.YYYY olur; tek haneli gün ve ay 0 alır', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _pickApartment(t, 'person_apartment', 'B Blok - 2');
      await _enter(t, 'person_move_in', '5.3.2024');
      expect(_fieldText(t, 'person_move_in'), '05.03.2024');
      await _enter(t, 'person_name', 'Tarihli Kişi');
      await _enter(t, 'person_email', 'tarihli@example.com');
      await t.tap(find.byKey(const ValueKey<String>('person_relation')));
      await t.pumpAndSettle();
      await t.tap(find.text('Malik').last);
      await t.pumpAndSettle();
      await _tapLast(t, 'Kaydet');
      await settleFor(t);
      expect(auth.createPersonCalls.single['move_in_date'], DateTime(2024, 3, 5));
    });
  });

  group('Kişi formu: plaka listesi (toplu yükleme ile aynı kurallar)', () {
    test('virgül / noktalı virgül / eğik çizgi ile ayrılır, normalize edilir, yinelenen atılır', () {
      final r = parsePlateList('34 abc 123, 06 XY 789; 34ABC123 / 35-DD-4567');
      expect(r.isValid, isTrue);
      expect(r.plates.map((e) => e.plate), ['34ABC123', '06XY789', '35DD4567']);
      expect(r.plates.first.display, '34 ABC 123');
    });
    test('en çok 5 plaka; geçersiz parça ve formül benzeri başlangıç reddedilir; boş serbest', () {
      expect(parsePlateList('11AAA11, 22BBB22, 33CCC33, 44DDD44, 55EEE55, 66FFF66').tooMany, isTrue);
      expect(parsePlateList('34 ABC 123, XY').invalid, ['XY']);
      expect(parsePlateList('=34ABC123').formulaLike, isTrue);
      expect(parsePlateList('  ').plates, isEmpty);
      expect(parsePlateList(null).isValid, isTrue);
    });
  });

  group('F21 alan (m²) girişi', () {
    test('üstel gösterim reddedilir; ayırıcı kuralları', () {
      expect(parseAreaInput('1e3'), isNull);
      expect(parseAreaInput('1E3'), isNull);
      expect(parseAreaInput('-5'), isNull);
      expect(parseAreaInput('abc'), isNull);
      expect(parseAreaInput(''), isNull);
      expect(parseAreaInput(' 12 5 '), isNull);
      expect(parseAreaInput('120'), 120.0);
      expect(parseAreaInput('120,5'), 120.5);
      expect(parseAreaInput('99.25'), 99.25);
      expect(parseAreaInput('1.234'), 1.234, reason: 'tek ayırıcı ondalıktır');
      expect(parseAreaInput('1,234.5'), 1234.5);
      expect(parseAreaInput('1.234,5'), 1234.5);
      expect(parseAreaInput('1.234.567'), 1234567.0, reason: 'aynı ayırıcı tekrarlanırsa binliktir');
      expect(parseAreaInput('1.234.567,89'), 1234567.89);
      expect(parseAreaInput('1,2,3'), isNull, reason: 'binlik grupları 3 hane olmalı');
      expect(parseAreaInput('1.23.456'), isNull);
      expect(parseAreaInput('1,234.56,7'), isNull);
    });
  });

  group('F24 plaka ve e-posta alanları', () {
    testWidgets('plaka yazarken büyük harfe çevrilir; plaka ve e-posta alanlarında otomatik düzeltme / öneri kapalı', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => VehicleDialog.show(c, scope: _scope(auth), person: null));
      await _enter(t, 'vehicle_plate', '34 abc 123');
      expect(_fieldText(t, 'vehicle_plate'), '34 ABC 123');
      expect(_textField(t, 'vehicle_plate').autocorrect, isFalse);
      expect(_textField(t, 'vehicle_plate').enableSuggestions, isFalse);
      await t.tap(find.text('Vazgeç'));
      await settleFor(t);

      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      expect(_textField(t, 'person_email').autocorrect, isFalse);
      expect(_textField(t, 'person_email').enableSuggestions, isFalse);
    });
  });

  group('F23 büyük yazıda avatar gizlenir (kod koşulsuz çizer, bileşen gizler)', () {
    testWidgets('PersonCard: 1,0 yazıda avatar var, 2,0 yazıda yok', (t) async {
      await _pumpView(t, PeopleFakeAuth.seeded(), scale: 1.0);
      expect(find.byType(PersonCard), findsWidgets);
      expect(find.byType(CircleAvatar), findsWidgets);
      await _pumpView(t, PeopleFakeAuth.seeded(), scale: 2.0, width: 320, height: 640);
      expect(find.byType(PersonCard), findsWidgets);
      expect(find.byType(CircleAvatar), findsNothing);
    });
  });
}

/// Araç penceresinde kişi seçicisinden ilk kişiyi seçer.
Future<void> _pickPerson(WidgetTester t) async {
  final field = find.byKey(const ValueKey<String>('vehicle_person'));
  await scrollTo(t, field);
  await t.tap(field);
  await settleFor(t);
  final row = find.descendant(of: find.byType(AppCard), matching: find.text('Mehmet Demir')).last;
  await scrollTo(t, row);
  await t.tap(row);
  await settleFor(t);
}

Finder _removeFor(String plate) => find.byTooltip('$plate plakalı aracı kaldır');
