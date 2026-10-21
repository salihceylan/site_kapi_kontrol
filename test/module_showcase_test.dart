// Panel modül vitrininin SAF mantığı (widget yok): kart üretimi, ikincil satır kuralı, görsel eşlemesi, sıralama,
// odak barı satırları, sütun sayısı, kitle ve borç özeti.
//
// Kural (fail-closed): vitrin kartı YALNIZ yan menünün hesapladığı listeden türer; listede olmayan öğenin kartı yoktur.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/module_art.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

List<SirketMenuItem> _menu(
  UserRole role, {
  Set<SirketMenuItem> extras = const <SirketMenuItem>{},
  Set<SirketMenuItem> hidden = const <SirketMenuItem>{},
  bool resident = false,
  bool toggle = false,
}) => YanMenu.visibleItems(
  role: role,
  isResidentMode: resident,
  canToggleMode: toggle,
  additionalItems: extras,
  hiddenItems: hidden,
);

List<SirketMenuItem> _gridOf(ShowcaseModel m) => <SirketMenuItem>[for (final e in m.grid) e.item];

void main() {
  group('SirketMenuItem -> ModuleArtKind eşlemesi', () {
    test('bilinen öğeler beklenen görsele gider', () {
      expect(moduleArtKindFor(SirketMenuItem.kapilar), ModuleArtKind.door);
      expect(moduleArtKindFor(SirketMenuItem.kisiler), ModuleArtKind.people);
      expect(moduleArtKindFor(SirketMenuItem.duyurular), ModuleArtKind.announcements);
      expect(moduleArtKindFor(SirketMenuItem.finans), ModuleArtKind.finance);
      expect(moduleArtKindFor(SirketMenuItem.borcum), ModuleArtKind.myDebt);
      expect(moduleArtKindFor(SirketMenuItem.belgeler), ModuleArtKind.documents);
      expect(moduleArtKindFor(SirketMenuItem.talepler), ModuleArtKind.workTracking);
      expect(moduleArtKindFor(SirketMenuItem.taleplerim), ModuleArtKind.workTracking);
      expect(moduleArtKindFor(SirketMenuItem.rezervasyonlar), ModuleArtKind.reservation);
      expect(moduleArtKindFor(SirketMenuItem.rezervasyon), ModuleArtKind.reservation);
      expect(moduleArtKindFor(SirketMenuItem.anketler), ModuleArtKind.survey);
      expect(moduleArtKindFor(SirketMenuItem.anket), ModuleArtKind.survey);
      expect(moduleArtKindFor(SirketMenuItem.ziyaretciKayitlari), ModuleArtKind.visitor);
      expect(moduleArtKindFor(SirketMenuItem.ziyaretcilerim), ModuleArtKind.visitor);
      expect(moduleArtKindFor(SirketMenuItem.sozlesmeler), ModuleArtKind.contracts);
      expect(moduleArtKindFor(SirketMenuItem.kararDefteri), ModuleArtKind.decisions);
      expect(moduleArtKindFor(SirketMenuItem.kararlar), ModuleArtKind.decisions);
      expect(moduleArtKindFor(SirketMenuItem.siteler), ModuleArtKind.sites);
      expect(moduleArtKindFor(SirketMenuItem.moduller), ModuleArtKind.modules);
      expect(moduleArtKindFor(SirketMenuItem.kayitliCihazlar), ModuleArtKind.devices);
      expect(moduleArtKindFor(SirketMenuItem.kullaniciYonetimi), ModuleArtKind.users);
      expect(moduleArtKindFor(SirketMenuItem.platformAyarlari), ModuleArtKind.settings);
    });

    test('eşlemesi olmayan öğe (Panel) generic olur; öteki her öğenin özel görseli vardır', () {
      expect(moduleArtKindFor(SirketMenuItem.dashboard), ModuleArtKind.generic);
      for (final item in SirketMenuItem.values) {
        if (item == SirketMenuItem.dashboard) continue;
        expect(
          moduleArtKindFor(item),
          isNot(ModuleArtKind.generic),
          reason: '$item için görsel eşlemesi eksik (yeni menü öğesi eklenince eşleme de eklenmeli)',
        );
      }
    });

    test('her kartın açıklaması dolu (Panel hariç), her rolde', () {
      for (final item in SirketMenuItem.values) {
        if (item == SirketMenuItem.dashboard) continue;
        expect(showcaseDescription(item), isNotEmpty, reason: '$item açıklaması eksik');
        for (final role in UserRole.values) {
          expect(showcaseDescription(item, role), isNotEmpty, reason: '$item / $role açıklaması eksik');
        }
      }
    });

    // tasarim-4: açıklama, kullanıcının o sayfada YAPABİLECEĞİNİ söyler (yetki kuralıyla çelişmez).
    test('"Modüller": süper kullanıcıda aç / kapat; site yöneticisinde görüntüle / talep et (rol yoksa vaat yok)', () {
      expect(showcaseDescription(SirketMenuItem.moduller, UserRole.superUser), 'Site modüllerini açın ve kapatın');
      expect(showcaseDescription(SirketMenuItem.moduller, UserRole.siteManager), 'Tanımlı modüller ve modül talebi');
      expect(showcaseDescription(SirketMenuItem.moduller), 'Tanımlı modüller ve modül talebi');
      final manager = buildShowcaseModel(menuItems: _menu(UserRole.siteManager), role: UserRole.siteManager);
      expect(
        manager.grid.firstWhere((e) => e.item == SirketMenuItem.moduller).description,
        'Tanımlı modüller ve modül talebi',
      );
      final superUser = buildShowcaseModel(menuItems: _menu(UserRole.superUser), role: UserRole.superUser);
      expect(
        superUser.grid.firstWhere((e) => e.item == SirketMenuItem.moduller).description,
        'Site modüllerini açın ve kapatın',
      );
    });

    test('"Kapılar": bireysel kullanıcıda bireysel ana ekran (kapılar, daireler, cihazlar); ötekilerde kapı paneli', () {
      expect(showcaseDescription(SirketMenuItem.kapilar, UserRole.individual), 'Kapılar, daireleriniz ve cihazlarınız');
      for (final role in <UserRole>[UserRole.apartmentOwner, UserRole.siteManager, UserRole.superUser]) {
        expect(showcaseDescription(SirketMenuItem.kapilar, role), 'Kapı durumu ve kapıyı aç', reason: '$role');
      }
      final individual = buildShowcaseModel(
        menuItems: _menu(UserRole.individual, extras: {SirketMenuItem.kapilar}),
        role: UserRole.individual,
      );
      expect(individual.grid.first.description, 'Kapılar, daireleriniz ve cihazlarınız');
    });
  });

  group('ikincil satır kuralı (hesap / ayar türü öğeler ızgarada değil)', () {
    test('kural kümesi sabit', () {
      expect(showcaseSecondaryItems, <SirketMenuItem>{
        SirketMenuItem.profilim,
        SirketMenuItem.ellerSerbest,
        SirketMenuItem.bluetoothWifiKur,
        SirketMenuItem.denetimKaydi,
        SirketMenuItem.platformAyarlari,
        SirketMenuItem.istemciHatalari,
      });
    });

    test('Profilim / Eller Serbest ikincil satıra, modüller ızgaraya gider; Panel hiçbirinde yok', () {
      final model = buildShowcaseModel(
        menuItems: _menu(UserRole.apartmentOwner, extras: {SirketMenuItem.kapilar, SirketMenuItem.borcum}),
        role: UserRole.apartmentOwner,
      );
      expect(model.secondary.map((e) => e.item), <SirketMenuItem>[SirketMenuItem.ellerSerbest, SirketMenuItem.profilim]);
      expect(_gridOf(model), contains(SirketMenuItem.kapilar));
      expect(_gridOf(model), contains(SirketMenuItem.borcum));
      expect(_gridOf(model), contains(SirketMenuItem.katilimVeKurulum));
      expect(model.items, isNot(contains(SirketMenuItem.dashboard)));
      for (final e in model.grid) {
        expect(showcaseSecondaryItems.contains(e.item), isFalse, reason: '${e.item} ızgarada olmamalı');
      }
    });
  });

  group('kart üretimi', () {
    test('başlık menüdeki başlıktır, açıklama ve görsel dolu, rozet haritadan gelir', () {
      final model = buildShowcaseModel(
        menuItems: _menu(
          UserRole.apartmentOwner,
          extras: {SirketMenuItem.duyurular, SirketMenuItem.ziyaretcilerim, SirketMenuItem.kapilar},
        ),
        role: UserRole.apartmentOwner,
        badgeCounts: {SirketMenuItem.duyurular: 3, SirketMenuItem.ziyaretcilerim: 0},
        badgeNouns: {SirketMenuItem.duyurular: 'okunmamış'},
      );
      for (final e in [...model.grid, ...model.secondary]) {
        expect(e.title, YanMenu.titleFor(e.item, UserRole.apartmentOwner));
        expect(e.description, isNotEmpty);
      }
      final duyuru = model.grid.firstWhere((e) => e.item == SirketMenuItem.duyurular);
      expect(duyuru.badge, 3);
      expect(duyuru.semanticLabel, 'Duyurular, 3 okunmamış');
      expect(duyuru.art, ModuleArtKind.announcements);
      final ziyaret = model.grid.firstWhere((e) => e.item == SirketMenuItem.ziyaretcilerim);
      expect(ziyaret.badge, 0);
      expect(ziyaret.semanticLabel, 'Ziyaretçilerim', reason: 'rozet yoksa etiket yalnız başlık');
    });

    // tasarim-13: aynı kullanıcıda aynı başlıklı iki kart olmaz (kurul üyesinde yönetim kaydı + sakin ekranı birlikte).
    test('hiçbir rol / modda iki kart aynı başlığı taşımaz (tüm ek öğeler açıkken bile)', () {
      final allExtras = <SirketMenuItem>{...SirketMenuItem.values}..remove(SirketMenuItem.dashboard);
      for (final role in UserRole.values) {
        for (final (resident, toggle) in <(bool, bool)>[(false, false), (true, true), (false, true)]) {
          final model = buildShowcaseModel(
            menuItems: _menu(role, extras: allExtras, resident: resident, toggle: toggle),
            role: role,
          );
          final titles = <String>[for (final e in [...model.grid, ...model.secondary]) e.title];
          expect(titles.toSet().length, titles.length, reason: '$role resident=$resident toggle=$toggle: $titles');
        }
      }
      expect(YanMenu.titleFor(SirketMenuItem.ziyaretciKayitlari), 'Ziyaretçi ve Kargo');
      expect(YanMenu.titleFor(SirketMenuItem.ziyaretcilerim), 'Ziyaretçilerim');
    });

    test('rozet sözcüğü verilmeyen öğede "bekleyen"', () {
      final model = buildShowcaseModel(
        menuItems: _menu(UserRole.superUser),
        role: UserRole.superUser,
        badgeCounts: {SirketMenuItem.modulTalepleri: 2},
      );
      final e = model.grid.firstWhere((e) => e.item == SirketMenuItem.modulTalepleri);
      expect(e.semanticLabel, 'Modül Talepleri, 2 bekleyen');
    });

    test('listede olmayan öğe çizilmez: rozet haritasında sayı olsa bile kart üretilmez', () {
      // Bu SAF test yalnız kart üretiminin listenin DIŞINA çıkmadığını sınar: liste Finans / Borcum ek öğesi VERİLMEDEN
      // kuruldu (HomePage modül kapalıyken bunları eklemez). Modül verisinden listeye giden asıl fail-closed yolu
      // (her modül kodu kapalıyken kart / hızlı işlem yok) HomePage düzeyinde sınanır:
      // test/screens/module_showcase_home_page_test.dart, "fail-closed tablosu".
      final items = _menu(UserRole.siteManager, extras: {SirketMenuItem.kapilar, SirketMenuItem.duyurular});
      expect(items, isNot(contains(SirketMenuItem.finans)), reason: 'ön koşul: liste Finans içermiyor');
      final model = buildShowcaseModel(
        menuItems: items,
        role: UserRole.siteManager,
        badgeCounts: {SirketMenuItem.finans: 9, SirketMenuItem.borcum: 4},
      );
      expect(model.items, isNot(contains(SirketMenuItem.finans)));
      expect(model.items, isNot(contains(SirketMenuItem.borcum)));
      expect(model.items, containsAll(<SirketMenuItem>[SirketMenuItem.kapilar, SirketMenuItem.duyurular]));
    });

    test('Geçiş Kontrol kapalı: "hidden" kümesi kapı kartını da eler', () {
      final items = _menu(
        UserRole.apartmentOwner,
        extras: {SirketMenuItem.kapilar, SirketMenuItem.belgeler},
        hidden: {SirketMenuItem.kapilar, SirketMenuItem.ellerSerbest},
      );
      final model = buildShowcaseModel(menuItems: items, role: UserRole.apartmentOwner);
      expect(model.items, isNot(contains(SirketMenuItem.kapilar)));
      expect(model.items, isNot(contains(SirketMenuItem.ellerSerbest)));
      expect(model.items, contains(SirketMenuItem.belgeler));
    });

    test('aynı öğe iki kez gelse bile tek kart', () {
      final model = buildShowcaseModel(
        menuItems: const <SirketMenuItem>[
          SirketMenuItem.dashboard,
          SirketMenuItem.belgeler,
          SirketMenuItem.belgeler,
        ],
        role: UserRole.apartmentOwner,
      );
      expect(model.grid.length, 1);
    });
  });

  group('sıralama', () {
    test('Kapılar önce, sonra özellik modülleri, sonra yönetim araçları; grup içinde menü sırası', () {
      final items = _menu(
        UserRole.superUser,
        extras: {
          SirketMenuItem.kapilar,
          SirketMenuItem.duyurular,
          SirketMenuItem.finans,
          SirketMenuItem.belgeler,
          SirketMenuItem.talepler,
        },
      );
      final grid = _gridOf(buildShowcaseModel(menuItems: items, role: UserRole.superUser));
      expect(grid.first, SirketMenuItem.kapilar);
      final firstTool = grid.indexOf(SirketMenuItem.kullaniciYonetimi);
      for (final feature in <SirketMenuItem>[
        SirketMenuItem.kisiler,
        SirketMenuItem.duyurular,
        SirketMenuItem.finans,
        SirketMenuItem.belgeler,
        SirketMenuItem.talepler,
      ]) {
        expect(grid.indexOf(feature), inInclusiveRange(1, firstTool - 1), reason: '$feature yönetim araçlarından önce');
      }
      // Grup içinde menü sırası: Kişiler < Duyurular < Finans < Belgeler < Talepler.
      final order = <SirketMenuItem>[
        SirketMenuItem.kisiler,
        SirketMenuItem.duyurular,
        SirketMenuItem.finans,
        SirketMenuItem.belgeler,
        SirketMenuItem.talepler,
      ].map(grid.indexOf).toList();
      expect(order, equals([...order]..sort()));
    });

    test('çekmecede "Kapılar" her zaman "Panel"in hemen altındadır', () {
      for (final role in UserRole.values) {
        final items = _menu(
          role,
          extras: {SirketMenuItem.kapilar, SirketMenuItem.duyurular, SirketMenuItem.belgeler, SirketMenuItem.kisiler},
        );
        expect(items.first, SirketMenuItem.dashboard);
        expect(items[1], SirketMenuItem.kapilar, reason: '$role');
      }
    });
  });

  group('odak barı satırları (yalnız var olan bekleyen sayılar)', () {
    test('sayı sıfırdan büyük ve menüde görünen öğeler, menü sırasıyla', () {
      final items = _menu(UserRole.superUser);
      final focus = buildFocusEntries(
        menuItems: items,
        badgeCounts: {
          SirketMenuItem.siteBasvurulari: 2,
          SirketMenuItem.modulTalepleri: 5,
          SirketMenuItem.duyurular: 7, // menüde yok: satır olmaz
          SirketMenuItem.kisiler: 0,
        },
      );
      expect(focus.map((e) => e.item), <SirketMenuItem>[SirketMenuItem.modulTalepleri, SirketMenuItem.siteBasvurulari]);
      expect(focus[0].text, '5 bekleyen modül talebi');
      expect(focus[0].action, 'İncele');
      expect(focus[1].text, '2 bekleyen site başvurusu');
      expect(focus[1].semanticLabel, '2 bekleyen site başvurusu. İncele');
    });

    test('hiç bekleyen yoksa satır yok (bar çizilmez)', () {
      expect(
        buildFocusEntries(
          menuItems: _menu(UserRole.superUser),
          badgeCounts: {SirketMenuItem.modulTalepleri: 0, SirketMenuItem.siteBasvurulari: 0},
        ),
        isEmpty,
      );
      expect(buildFocusEntries(menuItems: _menu(UserRole.siteManager), badgeCounts: const {}), isEmpty);
    });
  });

  group('sütun sayısı', () {
    test('telefonda 2, tablette 3, geniş ekranda 4', () {
      expect(showcaseColumns(358, 1.0), 2);
      expect(showcaseColumns(288, 1.0), 2);
      expect(showcaseColumns(380, 1.0), 2);
      expect(showcaseColumns(680, 1.0), 3);
      expect(showcaseColumns(820 - 40, 1.0), 3);
      expect(showcaseColumns(1100, 1.0), 4);
    });

    test('büyük yazı ölçeğinde sütun azalır, hiçbir zaman 1\'in altına inmez', () {
      expect(showcaseColumns(358, 1.5), 2);
      expect(showcaseColumns(358, 2.0), 1);
      expect(showcaseColumns(288, 2.0), 1);
      expect(showcaseColumns(100, 2.0), 1);
      expect(showcaseColumns(1100, 2.0), 4);
    });
  });

  group('kitle', () {
    test('süper kullanıcı ve yönetici modundaki yönetici admin; sakin modundaki yönetici ve daire sakini resident', () {
      expect(
        showcaseAudience(role: UserRole.superUser, isResidentMode: false, canToggleMode: true),
        ShowcaseAudience.admin,
      );
      expect(
        showcaseAudience(role: UserRole.siteManager, isResidentMode: false, canToggleMode: true),
        ShowcaseAudience.admin,
      );
      expect(
        showcaseAudience(role: UserRole.siteManager, isResidentMode: true, canToggleMode: true),
        ShowcaseAudience.resident,
      );
      expect(
        showcaseAudience(role: UserRole.apartmentOwner, isResidentMode: false, canToggleMode: false),
        ShowcaseAudience.resident,
      );
      expect(
        showcaseAudience(role: UserRole.individual, isResidentMode: false, canToggleMode: false),
        ShowcaseAudience.individual,
      );
    });

    test('sitesi olan bireysel / daire kullanıcısı (çift mod) yönetici görünümünde admin, sakin modunda sakin', () {
      expect(
        showcaseAudience(role: UserRole.apartmentOwner, isResidentMode: false, canToggleMode: true),
        ShowcaseAudience.admin,
      );
      expect(
        showcaseAudience(role: UserRole.apartmentOwner, isResidentMode: true, canToggleMode: true),
        ShowcaseAudience.resident,
      );
      expect(
        showcaseAudience(role: UserRole.individual, isResidentMode: false, canToggleMode: true),
        ShowcaseAudience.admin,
      );
    });
  });

  group('borç özeti', () {
    MyFinanceApartment apt(int balance, {int? overdue, DateTime? due, String site = 'Gül Sitesi', String label = 'D:3'}) =>
        MyFinanceApartment(
          siteCode: 1,
          siteName: site,
          apartmentId: balance.abs() + 1,
          label: label,
          blockName: 'A Blok',
          balanceMinor: balance,
          overdueMinor: overdue,
          nextDueDate: due,
        );

    test('tek daire: borç, vadesi geçen, en yakın vade, site ve daire başlığı', () {
      final s = summarizeMyFinance(MyFinance(items: [apt(325000, overdue: 100000, due: DateTime(2026, 11, 10))]));
      expect(s.debtMinor, 325000);
      expect(s.creditMinor, 0);
      expect(s.overdueMinor, 100000);
      expect(s.nextDue, DateTime(2026, 11, 10));
      expect(s.siteName, 'Gül Sitesi');
      expect(s.apartmentTitle, 'A Blok / D:3');
      expect(s.hasDebt, isTrue);
    });

    test('çok daire: yalnız borçlular toplanır, alacak ayrı, en erken vade, site/daire boş', () {
      final s = summarizeMyFinance(
        MyFinance(
          items: [
            apt(1000, overdue: 400, due: DateTime(2026, 12, 1)),
            apt(2000, due: DateTime(2026, 11, 1)),
            apt(-700, overdue: 9999, due: DateTime(2026, 10, 1)),
          ],
        ),
      );
      expect(s.debtMinor, 3000);
      expect(s.creditMinor, 700);
      expect(s.overdueMinor, 400, reason: 'alacaklı dairenin vadesi geçen tutarı borca katılmaz');
      expect(s.nextDue, DateTime(2026, 11, 1), reason: 'alacaklı dairenin vadesi sayılmaz');
      expect(s.siteName, isEmpty);
      expect(s.apartmentTitle, isEmpty);
    });

    test('bakiye sıfır: borç da alacak da yok', () {
      final s = summarizeMyFinance(MyFinance(items: [apt(0)]));
      expect(s.hasDebt, isFalse);
      expect(s.hasCredit, isFalse);
    });

    // İP-1A (G12): yalnız KENDİ hesabı sayılır; salt okunur kiracı hesabı (both dairede malike) vitrine eklenmez.
    test('iki hesap: salt okunur kiracı hesabının borcu sayılmaz; tek dairede kendi hesabının adı', () {
      const item = MyFinanceApartment(
        siteCode: 1,
        siteName: 'Gül Sitesi',
        apartmentId: 7,
        label: 'D:3',
        blockName: 'A Blok',
        balanceMinor: -10000,
        overdueMinor: 0,
        accountParty: AccountParty.owner,
        accounts: [
          MyFinanceAccount(accountParty: AccountParty.owner, balanceMinor: -10000, overdueMinor: 0),
          MyFinanceAccount(accountParty: AccountParty.tenant, role: MyFinanceAccountRole.readOnly, balanceMinor: 168000, overdueMinor: 156000),
        ],
      );
      final s = summarizeMyFinance(const MyFinance(items: [item]));
      expect(s.debtMinor, 0);
      expect(s.overdueMinor, 0);
      expect(s.creditMinor, 10000);
      expect(s.accountLabel, 'Ev sahibi hesabı');
    });

    test('eski sunucu (hesap bilgisi yok): hesap adı boş, tutarlar eski alanlardan', () {
      final s = summarizeMyFinance(MyFinance(items: [apt(5000, overdue: 5000)]));
      expect(s.accountLabel, isEmpty);
      expect(s.debtMinor, 5000);
    });

    test('çok daire: hesap adı yazılmaz (her dairenin hesabı farklı olabilir)', () {
      const a = MyFinanceApartment(siteCode: 1, apartmentId: 1, balanceMinor: 100, accountParty: AccountParty.tenant);
      const b = MyFinanceApartment(siteCode: 1, apartmentId: 2, balanceMinor: 200, accountParty: AccountParty.owner);
      final s = summarizeMyFinance(const MyFinance(items: [a, b]));
      expect(s.accountLabel, isEmpty);
      expect(s.debtMinor, 300);
    });
  });
}
