// İP-1D / G2: çekmece menüsünün grupları (sözleşme 2.4) ve "Ayarlar" ayrımı. SAF kurallar: her menü öğesi tam bir
// yere eşlenir (8 çekmece başlığından biri ya da sağ üstteki dişliden açılan "Ayarlar"); öğesi olmayan başlık
// görünmez; grup içinde menü sırası korunur.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

/// Beklenen eşleme (karar G2). Yeni bir menü öğesi eklenirse bu tablo ve `menuGroupOf` birlikte güncellenir: tablo
/// eksikse aşağıdaki "her öğe tabloda" testi düşer.
const Map<SirketMenuItem, SirketMenuGroup> _expected = <SirketMenuItem, SirketMenuGroup>{
  SirketMenuItem.dashboard: SirketMenuGroup.anaSayfa,
  SirketMenuItem.siteler: SirketMenuGroup.daireler,
  SirketMenuItem.daireKullanicilariYonetimi: SirketMenuGroup.daireler,
  SirketMenuItem.kisiler: SirketMenuGroup.daireler,
  SirketMenuItem.katilimVeKurulum: SirketMenuGroup.daireler,
  SirketMenuItem.finans: SirketMenuGroup.borclar,
  SirketMenuItem.borcum: SirketMenuGroup.borclar,
  SirketMenuItem.duyurular: SirketMenuGroup.iletisim,
  SirketMenuItem.talepler: SirketMenuGroup.iletisim,
  SirketMenuItem.taleplerim: SirketMenuGroup.iletisim,
  SirketMenuItem.anketler: SirketMenuGroup.iletisim,
  SirketMenuItem.anket: SirketMenuGroup.iletisim,
  SirketMenuItem.kapilar: SirketMenuGroup.siteHizmetleri,
  SirketMenuItem.belgeler: SirketMenuGroup.siteHizmetleri,
  SirketMenuItem.rezervasyonlar: SirketMenuGroup.siteHizmetleri,
  SirketMenuItem.rezervasyon: SirketMenuGroup.siteHizmetleri,
  SirketMenuItem.ziyaretciKayitlari: SirketMenuGroup.siteHizmetleri,
  SirketMenuItem.ziyaretcilerim: SirketMenuGroup.siteHizmetleri,
  SirketMenuItem.sozlesmeler: SirketMenuGroup.siteHizmetleri,
  SirketMenuItem.kararDefteri: SirketMenuGroup.siteHizmetleri,
  SirketMenuItem.kararlar: SirketMenuGroup.siteHizmetleri,
  SirketMenuItem.profilim: SirketMenuGroup.ayarlar,
  SirketMenuItem.ellerSerbest: SirketMenuGroup.ayarlar,
  SirketMenuItem.abonelikTalepleri: SirketMenuGroup.ayarlar,
  SirketMenuItem.siteOnayTalepleri: SirketMenuGroup.ayarlar,
  SirketMenuItem.kullaniciYonetimi: SirketMenuGroup.ayarlar,
  SirketMenuItem.superUserYonetimi: SirketMenuGroup.ayarlar,
  SirketMenuItem.siteYoneticileriYonetimi: SirketMenuGroup.ayarlar,
  SirketMenuItem.cihazEkle: SirketMenuGroup.ayarlar,
  SirketMenuItem.kayitliCihazlar: SirketMenuGroup.ayarlar,
  SirketMenuItem.bluetoothWifiKur: SirketMenuGroup.ayarlar,
  SirketMenuItem.moduller: SirketMenuGroup.ayarlar,
  SirketMenuItem.modulTalepleri: SirketMenuGroup.ayarlar,
  SirketMenuItem.siteBasvurulari: SirketMenuGroup.ayarlar,
  SirketMenuItem.denetimKaydi: SirketMenuGroup.ayarlar,
  SirketMenuItem.platformAyarlari: SirketMenuGroup.ayarlar,
  SirketMenuItem.istemciHatalari: SirketMenuGroup.ayarlar,
};

void main() {
  group('Menü grupları (sözleşme 2.4)', () {
    test('çekmecede 8 başlık, karar G2 sırasıyla; "Ayarlar" çekmece başlığı değildir', () {
      expect(
        SirketMenuGroup.drawerGroups.map((g) => g.title).toList(),
        <String>['Ana sayfa', 'Daireler', 'Borçlar', 'Tahsilat', 'Giderler', 'İletişim', 'Raporlar', 'Site hizmetleri'],
      );
      expect(SirketMenuGroup.drawerGroups, isNot(contains(SirketMenuGroup.ayarlar)));
      expect(SirketMenuGroup.ayarlar.title, 'Ayarlar');
      expect(SirketMenuGroup.values.length, SirketMenuGroup.drawerGroups.length + 1);
    });

    test('her menü öğesi beklenen tabloda (yeni öğe = enum değeri + grup eşlemesi + görünürlük kuralı)', () {
      for (final item in SirketMenuItem.values) {
        expect(_expected.containsKey(item), isTrue, reason: '${item.name} için grup kararı yazılmamış');
      }
    });

    test('her öğe tam bir gruba eşlenir', () {
      for (final entry in _expected.entries) {
        expect(menuGroupOf(entry.key), entry.value, reason: entry.key.name);
      }
    });

    test('"Site hizmetleri" karar G2 listesidir (kapı, ziyaretçi ve kargo, rezervasyon, sözleşme, karar defteri, belge)',
        () {
      final services = <SirketMenuItem>{
        for (final item in SirketMenuItem.values)
          if (menuGroupOf(item) == SirketMenuGroup.siteHizmetleri) item,
      };
      expect(services, <SirketMenuItem>{
        SirketMenuItem.kapilar,
        SirketMenuItem.ziyaretciKayitlari,
        SirketMenuItem.ziyaretcilerim,
        SirketMenuItem.rezervasyonlar,
        SirketMenuItem.rezervasyon,
        SirketMenuItem.sozlesmeler,
        SirketMenuItem.kararDefteri,
        SirketMenuItem.kararlar,
        SirketMenuItem.belgeler,
      });
    });

    test('ayar öğeleri: profil, platform ayarları, modüller, kullanıcılar, cihazlar, denetim kaydı, istemci hataları', () {
      for (final item in const <SirketMenuItem>[
        SirketMenuItem.profilim,
        SirketMenuItem.platformAyarlari,
        SirketMenuItem.moduller,
        SirketMenuItem.kullaniciYonetimi,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.cihazEkle,
        SirketMenuItem.denetimKaydi,
        SirketMenuItem.istemciHatalari,
      ]) {
        expect(menuGroupOf(item), SirketMenuGroup.ayarlar, reason: item.name);
      }
    });
  });

  group('Çekmece bölümleri ve Ayarlar ayrımı', () {
    const items = <SirketMenuItem>[
      SirketMenuItem.dashboard,
      SirketMenuItem.kapilar,
      SirketMenuItem.profilim,
      SirketMenuItem.siteler,
      SirketMenuItem.kisiler,
      SirketMenuItem.duyurular,
      SirketMenuItem.finans,
      SirketMenuItem.belgeler,
      SirketMenuItem.talepler,
      SirketMenuItem.moduller,
      SirketMenuItem.kayitliCihazlar,
      SirketMenuItem.katilimVeKurulum,
      SirketMenuItem.bluetoothWifiKur,
    ];

    test('yalnız öğesi olan başlıklar, çekmece sırasıyla; grup içinde menü sırası korunur', () {
      final sections = YanMenu.drawerSections(items);
      expect(
        sections.map((s) => s.group).toList(),
        <SirketMenuGroup>[
          SirketMenuGroup.anaSayfa,
          SirketMenuGroup.daireler,
          SirketMenuGroup.borclar,
          SirketMenuGroup.iletisim,
          SirketMenuGroup.siteHizmetleri,
        ],
        reason: 'Tahsilat / Giderler / Raporlar boş: görünmez',
      );
      expect(sections[0].items, <SirketMenuItem>[SirketMenuItem.dashboard]);
      expect(sections[1].items, <SirketMenuItem>[
        SirketMenuItem.siteler,
        SirketMenuItem.kisiler,
        SirketMenuItem.katilimVeKurulum,
      ]);
      expect(sections[2].items, <SirketMenuItem>[SirketMenuItem.finans]);
      expect(sections[3].items, <SirketMenuItem>[SirketMenuItem.duyurular, SirketMenuItem.talepler]);
      expect(sections[4].items, <SirketMenuItem>[SirketMenuItem.kapilar, SirketMenuItem.belgeler]);
      for (final section in sections) {
        expect(section.items, isNotEmpty);
        expect(section.group, isNot(SirketMenuGroup.ayarlar));
      }
    });

    test('ayar öğeleri çekmecede değil, Ayarlar panelinde (menü sırasıyla)', () {
      expect(YanMenu.settingsItems(items), <SirketMenuItem>[
        SirketMenuItem.profilim,
        SirketMenuItem.moduller,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.bluetoothWifiKur,
      ]);
      final drawer = YanMenu.drawerItems(items);
      expect(drawer.toSet().intersection(YanMenu.settingsItems(items).toSet()), isEmpty);
      expect(<SirketMenuItem>{...drawer, ...YanMenu.settingsItems(items)}, items.toSet(), reason: 'hiçbir öğe kaybolmaz');
      expect(drawer, <SirketMenuItem>[
        SirketMenuItem.dashboard,
        SirketMenuItem.siteler,
        SirketMenuItem.kisiler,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.finans,
        SirketMenuItem.duyurular,
        SirketMenuItem.talepler,
        SirketMenuItem.kapilar,
        SirketMenuItem.belgeler,
      ]);
    });

    test('rol listeleri: her rolde çekmece + Ayarlar = görünür öğeler (fail-closed: gizli öğe ikisinde de yok)', () {
      for (final (role, resident, toggle) in <(UserRole, bool, bool)>[
        (UserRole.superUser, false, false),
        (UserRole.siteManager, false, true),
        (UserRole.siteManager, true, true),
        (UserRole.apartmentOwner, false, false),
        (UserRole.individual, false, false),
        (UserRole.individual, false, true),
      ]) {
        final visible = YanMenu.visibleItems(
          role: role,
          isResidentMode: resident,
          canToggleMode: toggle,
          additionalItems: const <SirketMenuItem>{SirketMenuItem.kapilar, SirketMenuItem.duyurular},
          hiddenItems: const <SirketMenuItem>{SirketMenuItem.kapilar},
        );
        final drawer = YanMenu.drawerItems(visible);
        final settings = YanMenu.settingsItems(visible);
        expect(<SirketMenuItem>{...drawer, ...settings}, visible.toSet(), reason: '$role');
        expect(drawer, isNot(contains(SirketMenuItem.kapilar)), reason: '$role: gizli öğe çekmecede yok');
        expect(settings, isNot(contains(SirketMenuItem.kapilar)));
        expect(drawer.first, SirketMenuItem.dashboard, reason: '$role: Ana sayfa en üstte');
      }
    });
  });
}
