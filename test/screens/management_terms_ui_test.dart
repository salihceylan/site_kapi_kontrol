// F9 terim katmanı, ekran tarafı: Modüller ekranında "Bu tür için önerilir" çipi, yönetim türü seçicide
// tür açıklaması + terim özeti, Kişiler ekranında Daireler sekmesi / başlık / arama / boş durum metinlerinin
// türün terimiyle yazılması ve site kartı tür çipinin terim ipucu.
//
// AGENTS.md kural 2: eski sunucu (alan yok) varsayılan terimlerle ("Daireler", çip yok) çalışır.
// Kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; uzun terimler ("Kiracı firmalar") taşmaz.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/management_terms.dart';
import 'package:site_kapi_kontrol/models/management_type.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/views/modules_view.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/management_type_selector.dart';
import 'package:site_kapi_kontrol/ui/widgets/module_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_card.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'modules_fixtures.dart';
import 'people_fixtures.dart';

/// Uzun terimler (taşma denemesi): birim "Kiracı firma / Kiracı firmalar", blok "Kat / Katlar".
const Map<String, dynamic> _longTerms = <String, dynamic>{
  'unit': 'Kiracı firma',
  'unit_plural': 'Kiracı firmalar',
  'resident': 'Kiracı firma',
  'resident_plural': 'Kiracı firmalar',
  'owner': 'Mal sahibi',
  'fee': 'Ortak gider',
  'block': 'Kat',
  'block_plural': 'Katlar',
};

SiteRecord _mallSite({Map<String, dynamic>? terms}) => SiteRecord.fromJson(<String, dynamic>{
      'id': 11,
      'name': 'Çok Uzun Adlı Alışveriş Merkezi Yönetimi',
      'block_count': 1,
      'apartment_count': 10,
      'door_count': 1,
      'approval_status': 'approved',
      'block_apartment_counts': <int>[10],
      'management_type': 'shopping_mall',
      'management_type_label': 'Alışveriş Merkezi',
      'created_at': '2026-10-01T12:30:00Z',
      'management_terms': ?terms,
    });

/// `Daire → ...` ile başlayan terim özeti metinleri.
final Finder _termSummaries = find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? '').startsWith('Daire → '),
);

Future<void> _pumpPeople(
  WidgetTester t,
  PeopleFakeAuth auth, {
  required double w,
  required double h,
  required double s,
  required bool dark,
}) async {
  await pumpList(
    t,
    PeopleView(authService: auth, manageSites: true),
    width: w,
    height: h,
    scale: s,
    dark: dark,
  );
  // Önce siteler gelir, sekme sonra kurulur ve kendi verisini çeker: iki aşama.
  await settleFor(t, 100);
  await settleFor(t, 100);
}

Future<void> _openApartmentsTab(WidgetTester t) async {
  await tapFinder(t, find.byKey(const ValueKey<String>('people_tab_1')));
  await settleFor(t);
}

void main() {
  group('Modüller ekranı: önerilen modül çipi (F9)', () {
    listMatrix('recommended: true modüllerde "Bu tür için önerilir"; uzun terimlerle taşma yok', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = ModulesFakeAuth(
        states: <int, SiteModulesState>{
          11: mdState(
            11,
            'Alışveriş Merkezi',
            recommended: <String>{'door_control', 'finance'},
            terms: _longTerms,
          ),
          12: mdState(12, 'Mavi Park'),
        },
      );
      await pumpList(
        t,
        ModulesView(authService: auth),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await t.pump();
      await t.pump();
      expect(find.widgetWithText(StatusChip, ModuleCard.recommendedLabel), findsNWidgets(2));
      expect(auth.states[11]!.managementTerms.unitPlural, 'Kiracı firmalar');
    });

    testWidgets('eski sunucu (recommended alanı yok): çip hiç çıkmaz', (t) async {
      final auth = ModulesFakeAuth();
      await pumpList(
        t,
        ModulesView(authService: auth),
        width: 400,
        height: 1600,
        scale: 1.0,
        dark: false,
      );
      await t.pump();
      await t.pump();
      expect(find.widgetWithText(StatusChip, ModuleCard.recommendedLabel), findsNothing);
      expect(auth.states[11]!.managementTerms, ManagementTerms.defaults);
    });
  });

  group('ManagementTypeSelector: tür açıklaması + terim özeti (F9)', () {
    listMatrix('her türde tek cümlelik açıklama; terimleri farklı üç türde özet; taşma yok', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      await pumpList(
        t,
        ManagementTypeSelector(value: ManagementType.shoppingMall, onChanged: (_) {}),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      for (final type in ManagementType.values) {
        final info = ManagementTypeInfo.builtIn(type);
        expect(find.text(info.summary), findsOneWidget, reason: type.apiValue);
      }
      expect(_termSummaries, findsNWidgets(3));
      expect(
        find.text('Daire → Mağaza, Sakin → Kiracı firma, Malik → Mal sahibi, Aidat → Ortak gider, Blok → Kat'),
        findsOneWidget,
      );
      expect(find.text('Daire → Ofis, Sakin → Firma, Malik → Mal sahibi, Aidat → Ortak gider, Blok → Kat'),
          findsOneWidget);
      expect(find.text('Daire → Hisse, Sakin → Üye, Malik → Üye, Aidat → Üye aidatı'), findsOneWidget);
      expect(find.text('Yakında…'), findsNothing);
    });

    testWidgets('sunucu tanımları (types) yerleşik özeti ve terimleri geçersiz kılar', (t) async {
      final server = <ManagementTypeInfo>[
        ManagementTypeInfo(
          type: ManagementType.apartmentSite,
          label: 'Apartman ve Site',
          terms: ManagementTerms.fromJson(<String, dynamic>{'unit': 'Kiracı firma'}),
          summary: 'Sunucudan gelen özet.',
        ),
      ];
      await pumpList(
        t,
        ManagementTypeSelector(
          value: ManagementType.apartmentSite,
          onChanged: (_) {},
          types: server,
        ),
        width: 400,
        height: 1200,
        scale: 1.0,
        dark: false,
      );
      expect(find.text('Sunucudan gelen özet.'), findsOneWidget);
      expect(find.text('Daire → Kiracı firma'), findsOneWidget);
      // Listede olmayan türler yerleşik tanımla gösterilir.
      expect(find.text(ManagementTypeInfo.builtIn(ManagementType.residence).summary), findsOneWidget);
      expect(_termSummaries, findsNWidgets(4));
    });

    listMatrix('salt okunur: terimleri farklı türde özet + kilit notu; apartmanda yalnız not', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      await pumpList(
        t,
        const Column(
          children: [
            ManagementTypeSelector(value: ManagementType.businessCenter, onChanged: null),
            SizedBox(height: 12),
            ManagementTypeSelector(value: ManagementType.apartmentSite, onChanged: null),
          ],
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.widgetWithText(StatusChip, 'İş Merkezi'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Apartman ve Site'), findsOneWidget);
      expect(find.text(ManagementTypeSelector.lockedNote), findsNWidgets(2));
      expect(_termSummaries, findsOneWidget);
      expect(
        find.text('Daire → Ofis, Sakin → Firma, Malik → Mal sahibi, Aidat → Ortak gider, Blok → Kat'),
        findsOneWidget,
      );
    });
  });

  group('Kişiler ekranı: Daireler sekmesi terimle (F9)', () {
    listMatrix('uzun terimler: sekme "Kiracı firmalar", başlık, arama ve boş durum; taşma yok', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = PeopleFakeAuth(sites: <SiteRecord>[_mallSite(terms: _longTerms)]);
      await _pumpPeople(t, auth, w: w, h: h, s: s, dark: dark);
      expect(find.text('Kiracı firmalar'), findsOneWidget);
      expect(find.text('Daireler'), findsNothing);

      await _openApartmentsTab(t);
      // Sekme etiketi + bölüm başlığı.
      expect(find.text('Kiracı firmalar'), findsAtLeastNWidgets(2));
      expect(find.text('Kiracı firma ara'), findsOneWidget);
      expect(find.text('Bu sitede kiracı firma bulunamadı.'), findsOneWidget);
      expect(find.text('Daire ara'), findsNothing);
      expect(find.text('Bu sitede daire bulunamadı.'), findsNothing);
    });

    testWidgets('eski sunucu (management_terms yok): "Daireler", "Daire ara", "Bu sitede daire bulunamadı."', (
      t,
    ) async {
      final auth = PeopleFakeAuth(sites: <SiteRecord>[_mallSite()]);
      await _pumpPeople(t, auth, w: 400, h: 1600, s: 1.0, dark: false);
      expect(find.text('Daireler'), findsOneWidget);
      await _openApartmentsTab(t);
      expect(find.text('Daireler'), findsAtLeastNWidgets(2));
      expect(find.text('Daire ara'), findsOneWidget);
      expect(find.text('Bu sitede daire bulunamadı.'), findsOneWidget);
      expect(find.text('Kiracı firmalar'), findsNothing);
    });
  });

  group('Site kartı: tür çipi terim ipucu (F9)', () {
    listMatrix('AVM kartında "Terimler: Mağaza, ..."; varsayılan sitede Daire terimleri', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final mall = _mallSite(terms: ManagementTerms.forType(ManagementType.shoppingMall).toJsonForTest());
      await pumpList(
        t,
        Column(
          children: [
            SiteCard(
              site: fxSite(),
              selected: false,
              formattedCreatedAt: '01.10.2026 12:30',
              deleteBusy: false,
              approvalBusy: false,
              onTap: () {},
            ),
            const SizedBox(height: 12),
            SiteCard(
              site: mall,
              selected: false,
              formattedCreatedAt: '01.10.2026 12:30',
              deleteBusy: false,
              approvalBusy: false,
              onTap: () {},
            ),
          ],
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.widgetWithText(StatusChip, 'Alışveriş Merkezi'), findsOneWidget);
      expect(find.byTooltip('Terimler: Mağaza, Kiracı firma, Mal sahibi, Ortak gider, Kat'), findsOneWidget);
      expect(find.byTooltip(ManagementTerms.defaults.tooltipText), findsOneWidget);
    });
  });
}

extension on ManagementTerms {
  /// Sunucu biçimi (`management_terms` nesnesi) — yalnız denemede.
  Map<String, dynamic> toJsonForTest() => <String, dynamic>{
        'unit': unit,
        'unit_plural': unitPlural,
        'resident': resident,
        'resident_plural': residentPlural,
        'owner': owner,
        'fee': fee,
        'block': block,
        'block_plural': blockPlural,
      };
}
