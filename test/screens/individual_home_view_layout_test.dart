// FAZ 5 / A2-G4: IndividualHomeView (bireysel ana görünüm) taşma ve davranış testleri.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema (pumpAt). Kural 7: yenile
// düğmeleri ve işlem sonrası otomatik yenileme korunur. Davranış: ilk yükleme iskeleti, site filtre
// çipleri (yatay kaydırma yok), kapı açma başarı tiki, "Üyeyi Çıkar" (44 dp + onay diyaloğu).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart';

import '../design/harness.dart';
import 'g4_test_support.dart';

UserSession _session([UserRole role = UserRole.individual]) => UserSession(
  token: 'test_token',
  id: 1,
  fullName: 'Ahmet Ceylan',
  email: 'ahmet@example.com',
  loginName: 'ahmet',
  role: role,
  isActive: true,
);

Future<void> _pumpView(
  WidgetTester t,
  G4Auth auth, {
  double width = 360,
  double height = 1200,
  double scale = 1.0,
  bool dark = false,
  bool reduce = false,
  UserRole role = UserRole.individual,
}) {
  return pumpAt(
    t,
    IndividualHomeView(
      session: _session(role),
      authService: auth,
      onRefreshAll: () {},
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
    reduce: reduce,
  );
}

/// Ekran dışındaki widget'ı görünür kılıp dokunur (sayfa harness'ın kaydırma görünümünde uzar).
Future<void> _tapVisible(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pump();
  await t.tap(finder);
}

/// Ağacı boşaltır (yoklama zamanlayıcısı iptal olur).
Future<void> _dispose(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

/// Dolu görünüm: 2 site, 3 kapı, 2 daire, 2 sahiplenilmiş cihaz, 3 başvuru.
G4Auth _fullAuth() {
  return G4Auth(
    doors: [
      g4Door(geofence: true),
      g4Door(
        id: 2,
        name: 'B Blok Giriş',
        scope: 'BLOCK',
        block: 'B Blok',
        hardware: 'esp32_c3',
        qrReader: false,
        online: false,
      ),
      g4Door(
        id: 3,
        name: 'Kuzey Cephe Otopark Giriş Kapısı',
        siteName: 'Yeşilvadi Konutları Doğu Etap Sitesi',
        siteCode: 102,
        scope: 'CUSTOM',
        deviceUid: null,
        hardware: null,
        qrReader: false,
        online: null,
      ),
    ],
    apartments: [
      g4Apartment(),
      g4Apartment(
        id: 20,
        siteName: 'Yeşilvadi Konutları Doğu Etap Sitesi',
        siteCode: 102,
        block: '',
        unit: 'Daire 5',
        admin: false,
        members: const [],
      ),
    ],
    devices: <Map<String, dynamic>>[
      <String, dynamic>{
        'device_uid': 'ESP32_WROOM_ABCDEF1234567890',
        'hardware_type': 'esp32_wroom',
        'claimed_at': '2026-01-05T10:30:00Z',
        'site_code': 101,
      },
      <String, dynamic>{
        'device_uid': 'ESP32_C3_0011',
        'hardware_type': 'esp32_c3',
        'claimed_at': '2026-01-06T08:15:00Z',
      },
    ],
    requests: g4Requests(),
  );
}

void main() {
  group('taşma matrisi', () {
    g4LayoutMatrix('dolu görünüm (kapılar, daireler, cihazlar, başvurular)', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final auth = _fullAuth();
      await _pumpView(
        t,
        auth,
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Yetkili Kapılarım'), findsOneWidget);
      expect(find.text('Kayıtlı Dairelerim'), findsOneWidget);
      expect(find.text('Katılım Başvurularım'), findsOneWidget);
      expect(find.text('Sahiplendiğim Cihazlar (2)'), findsOneWidget);
      expect(find.text('Tüm Siteler'), findsOneWidget);
      expect(find.text('Siteyi Kur'), findsOneWidget);
      expect(find.text('Onay Bekliyor'), findsOneWidget);
      expect(find.text('Onaylandı'), findsOneWidget);
      expect(find.text('Reddedildi'), findsOneWidget);
      await _dispose(t);
    });

    g4LayoutMatrix('ilk açılış (içerik yok): karşılama + iki kurulum kartı', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      await _pumpView(
        t,
        G4Auth(),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Hoş Geldiniz!'), findsOneWidget);
      expect(find.text('Site Sakini Girişi'), findsOneWidget);
      expect(find.text('Yönetici & Cihaz Kurulumu'), findsOneWidget);
      expect(find.text('Site Sakini Olarak Devam Et'), findsOneWidget);
      expect(find.text('Yönetici Olarak Cihaz Ekle'), findsOneWidget);
      expect(find.text('HIZLI KATILIM'), findsOneWidget);
      expect(find.text('YÖNETİCİ'), findsOneWidget);
      await _dispose(t);
    });

    g4LayoutMatrix('ilk yükleme iskeleti (veri bekleniyor)', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final auth = G4Auth(gate: Completer<void>());
      await _pumpView(
        t,
        auth,
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.byType(ShimmerScope), findsOneWidget);
      expect(find.byType(SkeletonBox), findsWidgets);
      await _dispose(t);
    });

    g4LayoutMatrix(
      'tek site, kapı yok, sahip olunan cihaz yok: yalnız başvurular',
      (t, width, height, scale, dark) async {
        final auth = G4Auth(requests: g4Requests());
        await _pumpView(
          t,
          auth,
          width: width,
          height: height,
          scale: scale,
          dark: dark,
        );

        expect(find.text('Katılım Başvurularım'), findsOneWidget);
        expect(
          find.text('Hoş Geldiniz!'),
          findsNothing,
          reason: 'başvurusu olan kullanıcıya karşılama kartı gösterilmez',
        );
        expect(
          find.text('Tüm Siteler'),
          findsNothing,
          reason: 'tek (ya da hiç) sitede filtre çipi yok',
        );
        await _dispose(t);
      },
    );
  });

  group('ilk yükleme iskeleti', () {
    testWidgets(
      'veri gelene kadar iskelet; gelince iskelet kalkar, içerik görünür ve animasyon biter',
      (t) async {
        final gate = Completer<void>();
        final auth = G4Auth(doors: [g4Door()], gate: gate);
        await _pumpView(t, auth);

        expect(find.byType(ShimmerScope), findsOneWidget);
        expect(find.text('Yetkili Kapılarım'), findsNothing);
        expect(
          find.text('Hoş Geldiniz!'),
          findsNothing,
          reason: 'yükleme sürerken karşılama kartı yanıp sönmez',
        );

        gate.complete();
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));

        expect(find.byType(ShimmerScope), findsNothing);
        expect(find.text('Yetkili Kapılarım'), findsOneWidget);
        expect(find.text('Ana Giriş Kapısı'), findsOneWidget);
        await t.pumpAndSettle();
        await _dispose(t);
      },
    );

    testWidgets('hareket azaltma: iskelet durağan, tek pump ile içerik', (
      t,
    ) async {
      final gate = Completer<void>();
      final auth = G4Auth(doors: [g4Door()], gate: gate);
      await _pumpView(t, auth, reduce: true);

      expect(find.byType(ShimmerScope), findsOneWidget);
      gate.complete();
      await t.pump();
      await t.pump();
      expect(find.text('Ana Giriş Kapısı'), findsOneWidget);
      expect(find.byType(ShimmerScope), findsNothing);
      await _dispose(t);
    });

    testWidgets(
      'yenileme sırasında (içerik varken) iskelet değil mevcut liste kalır',
      (t) async {
        final auth = G4Auth(doors: [g4Door()]);
        await _pumpView(t, auth);
        expect(find.text('Ana Giriş Kapısı'), findsOneWidget);

        // Cihaz listesi yenilenirken (devices çağrısı bekler) içerik ekranda kalır.
        final gate = Completer<void>();
        auth.gate = gate;
        final state = t.state<IndividualHomeViewState>(
          find.byType(IndividualHomeView),
        );
        unawaited(state.loadAll());
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));

        expect(find.byType(ShimmerScope), findsNothing);
        expect(find.text('Ana Giriş Kapısı'), findsOneWidget);
        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason: 'yenileme göstergesi (eski davranış) sürer',
        );

        gate.complete();
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await _dispose(t);
      },
    );
  });

  group('site filtre çipleri', () {
    testWidgets(
      'hepsi görünür (yatay kaydırma yok), >= 44 dp; seçim kapı listesini ve sayaçları filtreler',
      (t) async {
        final auth = _fullAuth();
        await _pumpView(t, auth, width: 320, scale: 1.0);

        expect(
          find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
          findsNothing,
          reason: 'çipler Wrap: yatay kaydırma çipi gizlemez',
        );
        expect(find.text('Tüm Siteler'), findsOneWidget);
        expect(find.text('Güneş Sitesi'), findsWidgets);
        expect(find.text('Yeşilvadi Konutları Doğu Etap Sitesi'), findsWidgets);

        // 'Tüm Siteler' çipi (ilk) >= 44 dp yüksekliğinde.
        final chipFinder = find.ancestor(
          of: find.text('Tüm Siteler'),
          matching: find.byType(InkWell),
        );
        expect(t.getSize(chipFinder.first).height, greaterThanOrEqualTo(44));

        expect(find.text('3 Kapı'), findsOneWidget);

        // Yeşilvadi'yi seç: yalnız 3 numaralı kapı.
        await _tapVisible(
          t,
          find.text('Yeşilvadi Konutları Doğu Etap Sitesi').first,
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 400)); // sayaç 320 ms akar
        expect(find.text('1 Kapı'), findsOneWidget);
        expect(find.text('Kuzey Cephe Otopark Giriş Kapısı'), findsOneWidget);
        expect(find.text('B Blok Giriş'), findsNothing);
        expect(
          find.text('Kayıtlı Dairem'),
          findsOneWidget,
          reason: 'tek daire: tekil başlık',
        );

        // Tüm Siteler'e dön.
        await _tapVisible(t, find.text('Tüm Siteler'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('3 Kapı'), findsOneWidget);
        expect(find.text('B Blok Giriş'), findsOneWidget);
        expect(t.takeException(), isNull);
        await _dispose(t);
      },
    );
  });

  group('kapı açma', () {
    testWidgets(
      '"Kapıyı Aç" -> komut gider, başarı tiki ("Gönderildi") + başarı SnackBar; 1,4 sn sonra eski etiket',
      (t) async {
        final auth = G4Auth(
          doors: [g4Door(hardware: 'esp32_c3', qrReader: false)],
        );
        await _pumpView(t, auth);
        expect(find.text('Kapıyı Aç'), findsOneWidget);

        await t.tap(find.text('Kapıyı Aç'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));

        expect(auth.openedDoorIds, [1]);
        expect(find.text('Gönderildi'), findsOneWidget);
        expect(
          find.text('"Ana Giriş Kapısı" kapısı açılıyor...'),
          findsOneWidget,
        );

        await t.pump(const Duration(milliseconds: 1500));
        expect(find.text('Gönderildi'), findsNothing);
        expect(find.text('Kapıyı Aç'), findsOneWidget);
        await _dispose(t);
      },
    );

    testWidgets('sunucu hatası: hata SnackBar\'ı, başarı tiki YOK', (t) async {
      final auth = G4Auth(
        doors: [g4Door(hardware: 'esp32_c3', qrReader: false)],
        openError: 'Cihaz yanıt vermedi.',
      );
      await _pumpView(t, auth);

      await t.tap(find.text('Kapıyı Aç'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(auth.openedDoorIds, [1]);
      expect(find.text('Cihaz yanıt vermedi.'), findsOneWidget);
      expect(find.text('Gönderildi'), findsNothing);
      await _dispose(t);
    });

    testWidgets(
      'kapı başına ayrı başarı sayacı: yalnız açılan kapının düğmesi tik gösterir',
      (t) async {
        final auth = G4Auth(
          doors: [
            g4Door(
              id: 1,
              name: 'Birinci Kapı',
              hardware: 'esp32_c3',
              qrReader: false,
            ),
            g4Door(
              id: 2,
              name: 'İkinci Kapı',
              hardware: 'esp32_c3',
              qrReader: false,
            ),
          ],
        );
        await _pumpView(t, auth);
        expect(find.text('Kapıyı Aç'), findsNWidgets(2));

        await t.tap(find.text('Kapıyı Aç').first);
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));

        expect(auth.openedDoorIds, [1]);
        expect(find.text('Gönderildi'), findsOneWidget);
        expect(find.text('Kapıyı Aç'), findsOneWidget);
        await _dispose(t);
      },
    );
  });

  group('Kural 7: yenile düğmeleri ve işlem sonrası otomatik yenileme', () {
    testWidgets('bölüm yenile düğmeleri ilgili listeyi yeniden çeker', (
      t,
    ) async {
      final auth = _fullAuth();
      await _pumpView(t, auth);
      final doors = auth.doorCalls;
      final apartments = auth.apartmentCalls;
      final requests = auth.requestCalls;
      final devices = auth.deviceCalls;

      await _tapVisible(t, find.byTooltip('Kapıları Yenile'));
      await t.pump();
      await _tapVisible(t, find.byTooltip('Daireleri Yenile'));
      await t.pump();
      // 'Yenile' tooltip'i iki bölümde (başvurular, cihazlar): sırayla ikisine de bas.
      final refresh = find.byTooltip('Yenile');
      expect(refresh, findsNWidgets(2));
      await _tapVisible(t, refresh.at(0));
      await t.pump();
      await _tapVisible(t, refresh.at(1));
      await t.pump(const Duration(milliseconds: 300));

      expect(auth.doorCalls, doors + 1);
      expect(auth.apartmentCalls, apartments + 1);
      expect(auth.requestCalls, requests + 1);
      expect(auth.deviceCalls, devices + 1);
      await _dispose(t);
    });
  });

  group('Üyeyi Çıkar', () {
    testWidgets(
      'düğme yalnız çıkarılabilir üyede, >= 44 dp; onay diyaloğu AlertDialog; çıkarınca liste yenilenir',
      (t) async {
        final auth = _fullAuth();
        await _pumpView(t, auth, width: 360, scale: 1.0);

        final remove = find.byTooltip('Üyeyi Çıkar');
        expect(
          remove,
          findsOneWidget,
          reason:
              'kendisi ve başka yönetici için düğme yok; yalnız aile üyesinde',
        );
        final size = t.getSize(remove);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));

        final apartmentCalls = auth.apartmentCalls;
        await _tapVisible(t, remove);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Üyeyi Çıkar'), findsWidgets);
        expect(
          find.textContaining('Fatma Nur Kaya Yıldırım isimli sakin'),
          findsOneWidget,
        );
        expect(find.text('İptal'), findsOneWidget);
        expect(find.text('Çıkar'), findsOneWidget);

        // Vazgeç: hiçbir şey olmaz.
        await t.tap(find.text('İptal'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(auth.removedMembers, isEmpty);
        expect(find.byType(AlertDialog), findsNothing);

        // Onayla.
        await _tapVisible(t, remove);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await t.tap(find.text('Çıkar'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));

        expect(auth.removedMembers, [(10, 1002)]);
        expect(find.text('Üye çıkarıldı.'), findsOneWidget);
        expect(
          auth.apartmentCalls,
          apartmentCalls + 1,
          reason: 'işlem sonrası daireler otomatik yenilenir',
        );
        await _dispose(t);
      },
    );

    testWidgets('aile üyesi (yönetici olmayan) hesapta çıkar düğmesi yoktur', (
      t,
    ) async {
      final auth = G4Auth(
        doors: [g4Door()],
        apartments: [g4Apartment(admin: false)],
      );
      await _pumpView(t, auth);
      expect(find.byTooltip('Üyeyi Çıkar'), findsNothing);
      await _dispose(t);
    });
  });

  group('yinelenen/eksik kimlik güvenliği', () {
    testWidgets(
      'aynı kimlikli kapı/daire/başvuru ve UID bilgisi olmayan cihazlar çerçeve hatası (yinelenen anahtar) üretmez',
      (t) async {
        final door = g4Door();
        final auth = G4Auth(
          doors: [door, door],
          apartments: [
            g4Apartment(id: 0, siteName: 'Güneş Sitesi'),
            g4Apartment(id: 0, siteName: 'Güneş Sitesi', unit: 'Daire 14'),
          ],
          devices: <Map<String, dynamic>>[
            <String, dynamic>{'hardware_type': 'esp32_c3'},
            <String, dynamic>{'hardware_type': 'esp32_wroom'},
          ],
          requests: [g4Requests().first, g4Requests().first],
        );
        await _pumpView(t, auth, height: 3600);

        expect(
          find.text('Ana Giriş Kapısı'),
          findsNWidgets(2),
          reason: 'yinelenen kayıt sessizce gösterilir (eski davranış)',
        );
        expect(find.text('A Blok • Daire 12'), findsOneWidget);
        expect(find.text('A Blok • Daire 14'), findsOneWidget);
        expect(find.text('ESP32-C3 Süper Mini'), findsOneWidget);
        expect(find.text('ESP32-WROOM-32E Röle Kartı'), findsOneWidget);
        expect(t.takeException(), isNull);
        await _dispose(t);
      },
    );
  });

  group('rol: yönetici sakin modunda', () {
    testWidgets(
      'site yöneticisi (Sakin Modu): içerik yokken bile kurulum kartları gösterilmez',
      (t) async {
        await _pumpView(t, G4Auth(), role: UserRole.siteManager);
        expect(find.text('Hoş Geldiniz!'), findsNothing);
        expect(find.text('Site Sakini Girişi'), findsNothing);
        await _dispose(t);
      },
    );
  });
}
