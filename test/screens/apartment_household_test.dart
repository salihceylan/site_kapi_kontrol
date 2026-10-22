// Site Yönetimi > Daireler: dairenin TÜM güncel sakinleri (daire admini + "Aile üyeleri (N)" akordiyonu).
// Kök neden: daire satırı eski tek-sakin alanını (apartments.resident_user_code) gösteriyordu; artık sunucudaki
// GET /manager/sites/:siteCode/apartments/:id/household yanıtı çizilir. Taşma matrisi AGENTS.md kural 6.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_household.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/ui/widgets/apartment_card.dart';

import 'list_fixtures.dart' show listMatrix, pumpList, tapFinder, tapText;

ApartmentRecord _apartment({int? householdCount = 5, bool resident = true}) => ApartmentRecord(
  id: 7,
  siteCode: 5899864115,
  blockId: 1,
  blockName: 'A Blok',
  unitLabel: 'Daire 12',
  sortOrder: 12,
  isActive: true,
  residentUserCode: resident ? 4012 : null,
  residentFullName: resident ? 'Ayşe Yılmaz' : null,
  residentLoginName: resident ? 'a_blok_daire12' : null,
  residentEmail: null,
  residentPinCode: null,
  residentPhoneNumber: null,
  residentIsActive: resident ? true : null,
  createdAt: DateTime(2026, 1, 1),
  householdCount: householdCount,
);

ApartmentHousehold _household({bool detailed = true}) => ApartmentHousehold(
  apartmentId: 7,
  label: 'A Blok - Daire 12',
  isDetailed: detailed,
  admin: HouseholdPerson(
    personId: 1,
    name: 'Ayşe Yılmaz',
    relation: ResidencyRelation.tenant,
    isAdmin: true,
    hasAccount: true,
    phone: detailed ? '0555 111 22 33' : null,
  ),
  absentOwner: const HouseholdPerson(
    personId: 2,
    name: 'Mehmet Kaya Cok Uzun Soyadli Malik',
    relation: ResidencyRelation.owner,
  ),
  members: <HouseholdPerson>[
    HouseholdPerson(
      personId: 3,
      name: 'Ali Yılmaz',
      relation: ResidencyRelation.familyMember,
      hasAccount: detailed,
      accessSuspended: detailed,
    ),
    HouseholdPerson(
      personId: 4,
      name: 'Elif Yılmaz',
      relation: ResidencyRelation.familyMember,
      isMinor: detailed,
    ),
    const HouseholdPerson(personId: 5, name: 'Fatma Yılmaz', relation: ResidencyRelation.familyMember),
  ],
  total: 5,
);

ApartmentHousehold _singlePerson() => const ApartmentHousehold(
  apartmentId: 7,
  isDetailed: true,
  admin: HouseholdPerson(personId: 1, name: 'Ayşe Yılmaz', relation: ResidencyRelation.owner, isAdmin: true, hasAccount: true),
  total: 1,
);

Future<void> _pumpCard(
  WidgetTester t,
  ApartmentHousehold household, {
  ApartmentRecord? apartment,
  double width = 360,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
  bool reduce = false,
  Future<void> Function(HouseholdPerson person)? onOpenPerson,
  Future<void> Function()? onOpenApartmentCard,
  List<int>? loads,
}) async {
  final record = apartment ?? _apartment();
  await pumpList(
    t,
    ApartmentCard(
      apartment: record,
      onEdit: () {},
      onDelete: () {},
      householdLoader: () async {
        loads?.add(1);
        return household;
      },
      onOpenHouseholdPerson: onOpenPerson,
      onOpenApartmentCard: onOpenApartmentCard,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
    reduce: reduce,
  );
  await tapText(t, record.label); // daire satırını aç -> sakinler yüklenir
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  group('ApartmentCard: daire admini + Aile üyeleri akordiyonu', () {
    testWidgets('kapalı akordiyon: admin ve oturmayan malik görünür, aile üyeleri gizli; satırda "5 kişi"', (t) async {
      await _pumpCard(t, _household());
      expect(find.text('5 kişi'), findsOneWidget);
      expect(find.text('Daire admini'), findsOneWidget);
      expect(find.text('Ayşe Yılmaz'), findsWidgets);
      expect(find.text('0555 111 22 33'), findsOneWidget, reason: 'yönetici telefonu görür');
      expect(find.text('Malik (oturmuyor)'), findsOneWidget);
      expect(find.text('Mehmet Kaya Cok Uzun Soyadli Malik'), findsOneWidget);
      expect(find.text('Aile üyeleri (3)'), findsOneWidget);
      expect(find.text('Ali Yılmaz'), findsNothing, reason: 'akordiyon kapalıyken aile üyeleri ağaçta yok');
      expect(find.text('Elif Yılmaz'), findsNothing);
      expect(find.text('Daire hesabı (giriş bilgileri)'), findsOneWidget);
    });

    testWidgets('açık akordiyon: tüm aile üyeleri; küçük "Çocuk", hesap durumu, erişim askısı işareti', (t) async {
      await _pumpCard(t, _household());
      await tapText(t, 'Aile üyeleri (3)');
      expect(find.text('Ali Yılmaz'), findsOneWidget);
      expect(find.text('Elif Yılmaz'), findsOneWidget);
      expect(find.text('Fatma Yılmaz'), findsOneWidget);
      expect(find.text('Çocuk'), findsOneWidget);
      expect(find.text('Aile üyesi'), findsNWidgets(2));
      expect(find.text('Hesabı var'), findsWidgets);
      expect(find.text('Erişim askıda'), findsOneWidget);
      // Yeniden dokununca kapanır.
      await tapText(t, 'Aile üyeleri (3)');
      expect(find.text('Ali Yılmaz'), findsNothing);
    });

    testWidgets('tek kişili daire: yalnız admin; "Aile üyesi kaydı yok", akordiyon yok', (t) async {
      await _pumpCard(t, _singlePerson(), apartment: _apartment(householdCount: 1));
      expect(find.text('1 kişi'), findsOneWidget);
      expect(find.text('Daire admini'), findsOneWidget);
      expect(find.text('Aile üyeleri (0)'), findsOneWidget);
      expect(find.text('Aile üyesi kaydı yok.'), findsOneWidget);
      expect(find.text('Malik (oturmuyor)'), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNWidgets(1), reason: 'yalnız daire satırının oku (akordiyon oku yok)');
    });

    testWidgets('kurul görünümü: iletişim, çocuk, hesap durumu ve erişim askısı HİÇ çizilmez', (t) async {
      await _pumpCard(t, _household(detailed: false));
      await tapText(t, 'Aile üyeleri (3)');
      expect(find.text('Ali Yılmaz'), findsOneWidget);
      expect(find.text('0555 111 22 33'), findsNothing);
      expect(find.text('Çocuk'), findsNothing);
      expect(find.text('Hesabı var'), findsNothing);
      expect(find.text('Hesapsız'), findsNothing);
      expect(find.text('Erişim askıda'), findsNothing);
      expect(find.text('Malik'), findsOneWidget);
    });

    testWidgets('hareket azaltma: akordiyon animasyonsuz açılır', (t) async {
      await _pumpCard(t, _household(), reduce: true);
      final header = find.text('Aile üyeleri (3)');
      await t.ensureVisible(header);
      await t.tap(header);
      await t.pump();
      expect(find.text('Ali Yılmaz'), findsOneWidget);
    });

    testWidgets('kişi satırına dokunma kişi kartını açar; "Daire kartı" düğmesi pencereyi açar; veri yenilenir', (t) async {
      final opened = <int?>[];
      var cards = 0;
      final loads = <int>[];
      await _pumpCard(
        t,
        _household(),
        onOpenPerson: (p) async => opened.add(p.personId),
        onOpenApartmentCard: () async => cards += 1,
        loads: loads,
      );
      expect(loads.length, 1);
      await tapText(t, 'Aile üyeleri (3)');
      await tapText(t, 'Ali Yılmaz');
      await t.pump(const Duration(milliseconds: 50));
      expect(opened, <int?>[3]);
      expect(loads.length, 2, reason: 'kişi kartı kapanınca dairenin sakinleri yenilenir');
      await tapText(t, 'Daire kartı');
      await t.pump(const Duration(milliseconds: 50));
      expect(cards, 1);
    });

    testWidgets('daire kapanıp açılınca veri korunur (sunucuya tekrar gidilmez)', (t) async {
      final loads = <int>[];
      await _pumpCard(t, _household(), loads: loads);
      await tapText(t, 'A Blok / Daire 12');
      await tapText(t, 'A Blok / Daire 12');
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Daire admini'), findsOneWidget);
      expect(loads.length, 1);
    });

    testWidgets('sunucu hatası: iskelet yerine uyarı + "Tekrar Dene"', (t) async {
      var calls = 0;
      await pumpList(
        t,
        ApartmentCard(
          apartment: _apartment(),
          onEdit: () {},
          householdLoader: () async {
            calls += 1;
            throw Exception('boom');
          },
        ),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await tapText(t, 'A Blok / Daire 12');
      await t.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Daire sakinleri yüklenemedi'), findsOneWidget);
      await tapFinder(t, find.text('Tekrar Dene'));
      expect(calls, 2);
    });

    testWidgets('eski sunucu (yükleyici yok): eski tek-sakin görünüm aynen', (t) async {
      await pumpList(
        t,
        ApartmentCard(apartment: _apartment(householdCount: null), onEdit: () {}),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      expect(find.textContaining('kişi'), findsNothing);
      await tapText(t, 'A Blok / Daire 12');
      expect(find.text('Sakin: Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Daire admini'), findsNothing);
      expect(find.text('Daire kartı'), findsNothing);
    });

    listMatrix('açık akordiyon, uzun adlar', (t, w, h, s, dark) async {
      await _pumpCard(t, _household(), width: w, height: h, scale: s, dark: dark);
      await tapText(t, 'Aile üyeleri (3)');
      expect(find.text('Ali Yılmaz'), findsOneWidget);
    });
  });

  group('HouseholdPerson ayrıştırma', () {
    test('is_minor "Çocuk" etiketidir; ilişki ayrımı sunucuda yoksa "Aile üyesi"', () {
      final minor = HouseholdPerson.fromJson(<String, dynamic>{
        'person_id': 4,
        'name': ' Elif ',
        'relation': 'family_member',
        'is_minor': true,
      });
      expect(minor.name, 'Elif');
      expect(minor.relationLabel, 'Çocuk');
      final adult = HouseholdPerson.fromJson(<String, dynamic>{'name': 'Ali', 'relation': 'family_member'});
      expect(adult.relationLabel, 'Aile üyesi');
      expect(adult.personId, isNull);
      expect(HouseholdPerson.fromJson(<String, dynamic>{'name': '', 'relation': 'tenant'}).name, 'İsimsiz kişi');
    });

    test('ApartmentHousehold: eski/eksik alanlar güvenli varsayılan; toplam hesaplanır', () {
      final h = ApartmentHousehold.fromJson(<String, dynamic>{
        'apartment_id': 7,
        'detail': 'basic',
        'admin': <String, dynamic>{'name': 'A', 'is_admin': true, 'relation': 'owner'},
        'members': <dynamic>[
          <String, dynamic>{'name': 'B', 'relation': 'family_member'},
        ],
      });
      expect(h.isDetailed, isFalse);
      expect(h.total, 2);
      expect(h.admin!.isAdmin, isTrue);
      expect(h.absentOwner, isNull);
      expect(ApartmentHousehold.fromJson(<String, dynamic>{}).members, isEmpty);
    });
  });
}
