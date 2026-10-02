// FAZ 5 / A2-G3: Kullanıcı Yönetimi (tüm kullanıcı dizini: AllUsersView).
//
// AGENTS.md kural 6: taşma YOK (320x640 x2,0 ve 360x640 x1,5; açık + koyu tema) - ana sayfa, detay alt
// sayfası, silme onayı ve veritabanı bakım diyaloğu dahil. Davranış: arama (400 ms bekleme), rol çipleri,
// sayfa boyutu/sayfalama ve satır -> detay -> düzenle/sil akışı değişmedi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/all_users_view.dart';

import 'list_fixtures.dart';

AllUsersView _view({
  List<String>? log,
  bool loading = false,
  List<ManagedUserAccount>? users,
  ManagedUserPage? page,
  UserSession? session,
  Set<int> busy = const <int>{},
  bool maintenance = true,
}) {
  final l = log ?? <String>[];
  final list = users ?? fxUsers();
  return AllUsersView(
    session: session ?? fxSession,
    pageData: page ?? fxUserPage(list, total: 25),
    users: list,
    isLoading: loading,
    busyActivationUsers: busy,
    onLoadPage: ({role, page = 1, pageSize = 15, search}) async {
      l.add('load:${role?.apiValue}:$page:$pageSize:$search');
    },
    onRefresh: () => l.add('refresh'),
    onUpdateUser: (u, r) async => l.add('update:${u.id}'),
    onToggleActivation: (u, v) async => l.add('toggle:${u.id}:$v'),
    onDeleteUser: (u) async => l.add('delete:${u.id}'),
    onGetDatabaseHealth: maintenance
        ? () async {
            l.add('health');
            return <String, dynamic>{
              'isClean': false,
              'users': <String, dynamic>{
                'real': 12,
                'dummy': 2,
                'superUsers': 1,
                'siteManagers': 3,
              },
              'structure': <String, dynamic>{
                'sites': 3,
                'apartments': 36,
                'doors': 5,
              },
              'devices': <String, dynamic>{'online': 2, 'total': 6},
            };
          }
        : null,
    onRunDatabaseCleanup: maintenance
        ? () async {
            l.add('cleanup');
            return <String, dynamic>{'totalCleaned': 4};
          }
        : null,
  );
}

/// Ayşe Yılmaz (id 10, site yöneticisi) oturumu: "Siz" rozeti ve kendi hesabı kısıtları.
const UserSession _selfSession = UserSession(
  id: 10,
  fullName: 'Ayşe Yılmaz',
  email: 'kullanici10@e2e.local',
  loginName: null,
  role: UserRole.siteManager,
  isActive: true,
  token: 'tok',
);

void main() {
  group('AllUsersView taşma matrisi', () {
    listMatrix('ana sayfa: başlık, arama, rol çipleri, satırlar, sayfalama', (
      t,
      w,
      h,
      scale,
      dark,
    ) async {
      await pumpList(t, _view(), width: w, height: h, scale: scale, dark: dark);
      for (final text in const <String>[
        'Kullanıcı Yönetimi',
        'Toplam 25 kayıtlı kullanıcı',
        'Tüm Roller',
        'Site Yöneticileri',
        'Daire Sakinleri',
        'Bireysel Kullanıcılar',
        'Ayşe Yılmaz',
        'Selin Aydın',
        'Sayfa 1 / 2 (Toplam 25 kişi)',
        '15 / sf',
      ]) {
        expect(find.text(text), findsWidgets, reason: 'metin korunmalı: $text');
      }
      // Süper kullanıcılar dizinde listelenmez (önceki davranış).
      expect(find.text('Süper Yönetici'), findsNothing);
      // Rol çipleri yatay kaydırılmaz: hepsi ekran genişliği içinde (sığmayan çip alta iner).
      final chips = find.byType(FilterChip);
      expect(chips, findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        expect(
          t.getRect(chips.at(i)).right,
          lessThanOrEqualTo(w + 0.5),
          reason: 'çip #$i ekran dışına taşmamalı',
        );
        expect(t.getRect(chips.at(i)).left, greaterThanOrEqualTo(0));
      }
      // Tüm simge düğmeleri en az 44 dp.
      for (final e in find.byType(IconButton).evaluate()) {
        final size = t.getSize(find.byElementPredicate((x) => x == e));
        expect(size.shortestSide, greaterThanOrEqualTo(44));
      }
      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byType(AppCard),
        ),
        findsNothing,
        reason: 'kart-içinde-kart yok',
      );
    });

    listMatrix('detay alt sayfası: satır -> bilgiler, anahtar, Düzenle/Sil', (
      t,
      w,
      h,
      scale,
      dark,
    ) async {
      await pumpList(t, _view(), width: w, height: h, scale: scale, dark: dark);
      await tapText(t, 'Ayşe Yılmaz');
      for (final text in const <String>[
        'Kullanıcı ID',
        '#10',
        'Rolü',
        'E-posta Onayı',
        'Doğrulandı',
        'Telefon',
        'Kayıt Tarihi',
        'Hesap Durumu',
        'Düzenle',
        'Sil',
      ]) {
        expect(find.text(text), findsWidgets, reason: 'alt sayfa: $text');
      }
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    listMatrix('silme onayı ve veritabanı bakım diyaloğu', (
      t,
      w,
      h,
      scale,
      dark,
    ) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      // Alt sayfa -> Sil -> onay diyaloğu (AlertDialog tipi korunur).
      await tapText(t, 'Mehmet Demir Çok Uzun Bir Soyadı Olan Kullanıcı');
      await tapText(t, 'Sil');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Kullanıcıyı Sil'), findsOneWidget);
      expect(
        find.textContaining('adlı kullanıcıyı kalıcı olarak silmek'),
        findsOneWidget,
      );
      expect(find.text('Vazgeç'), findsOneWidget);
      expect(find.text('Evet, Sil'), findsOneWidget);
      await tapText(t, 'Evet, Sil');
      expect(log, contains('delete:11'));
      expect(find.byType(AlertDialog), findsNothing);

      // Veritabanı bakım diyaloğu: sağlık yüklenir, istatistikler görünür, temizlik çalışır.
      await tapFinder(t, find.byTooltip('Veritabanı Sağlığı & Çöp Temizliği'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Veritabanı Sağlığı & Bakım'), findsOneWidget);
      for (final text in const <String>[
        'Veritabanında atık kayıtlar veya temizlenecek öğeler var.',
        'Gerçek Kayıtlı Kullanıcı',
        'Kukla / Sahte Kullanıcı',
        'Kayıtlı Siteler',
        'Daireler & Kapılar',
        '36 daire, 5 kapı',
        'ESP32 Donanımları',
        '2 çevrimiçi / 6 kayıtlı',
        'Kapat',
        'Çöp Temizliği Yap',
      ]) {
        expect(
          find.text(text),
          findsOneWidget,
          reason: 'bakım diyaloğu: $text',
        );
      }
      await tapText(t, 'Çöp Temizliği Yap');
      await t.pump(const Duration(milliseconds: 500));
      expect(
        find.text(
          'Temizlik tamamlandı: Toplam 4 adet gereksiz/süresi dolmuş kayıt temizlendi.',
        ),
        findsOneWidget,
      );
      expect(log, containsAllInOrder(<String>['health', 'cleanup']));
    });

    listMatrix('iskelet ve boş durum (filtre temizleme düğmesi)', (
      t,
      w,
      h,
      scale,
      dark,
    ) async {
      await pumpList(
        t,
        _view(loading: true, users: const <ManagedUserAccount>[]),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(find.byType(ShimmerScope), findsOneWidget);
      // Yenile düğmesi yüklenirken küçük spinner gösterir (işlevsel gösterge; iskelet değil).
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await pumpList(
        t,
        _view(
          users: const <ManagedUserAccount>[],
          page: fxUserPage(const <ManagedUserAccount>[], total: 0),
        ),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(find.text('Kullanıcı Bulunamadı'), findsOneWidget);
      expect(
        find.text('Sistemde henüz kayıtlı kullanıcı bulunmuyor.'),
        findsOneWidget,
      );
      expect(find.text('Filtreleri Temizle'), findsNothing);
      // Filtre varken: farklı mesaj + "Filtreleri Temizle".
      await t.enterText(find.byType(TextField), 'zzz');
      await t.pump();
      expect(
        find.text(
          'Arama kriterlerinize veya filtreye uygun kullanıcı kaydı bulunamadı.',
        ),
        findsOneWidget,
      );
      expect(find.text('Filtreleri Temizle'), findsOneWidget);
      // Bekleyen arama zamanlayıcısını (400 ms) bitir.
      await t.pump(const Duration(milliseconds: 500));
    });
  });

  group('AllUsersView davranış', () {
    testWidgets('arama 400 ms bekletilir ve tek yükleme isteği gönderir', (
      t,
    ) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      await t.enterText(find.byType(TextField), 'Ay');
      await t.pump(const Duration(milliseconds: 200));
      await t.enterText(find.byType(TextField), 'Ayşe');
      await t.pump(const Duration(milliseconds: 300));
      expect(log.where((e) => e.startsWith('load')), isEmpty);
      await t.pump(const Duration(milliseconds: 200));
      expect(log, <String>['load:null:1:15:Ayşe']);
    });

    testWidgets('rol çipleri ve sayfa boyutu: istek parametreleri', (t) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      await tapText(t, 'Site Yöneticileri');
      await tapText(t, 'Daire Sakinleri');
      await tapText(t, 'Tüm Roller');
      expect(log, <String>[
        'load:site_manager:1:15:null',
        'load:apartment_owner:1:15:null',
        'load:null:1:15:null',
      ]);
      log.clear();
      await tapText(t, '15 / sf');
      await tapText(t, '25 / sf');
      expect(log, <String>['load:null:1:25:null']);
    });

    testWidgets(
      'sayfalama: dört düğme ipucuyla, sayfa göstergesi, istek sayfası',
      (t) async {
        final log = <String>[];
        final users = fxUsers();
        await pumpList(
          t,
          _view(log: log, users: users, page: fxUserPage(users, total: 60)),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        expect(find.text('Sayfa 1 / 4 (Toplam 60 kişi)'), findsOneWidget);
        for (final tip in const <String>[
          'İlk Sayfa',
          'Önceki Sayfa',
          'Sonraki Sayfa',
          'Son Sayfa',
        ]) {
          expect(
            t.getSize(find.byTooltip(tip)).shortestSide,
            greaterThanOrEqualTo(44),
            reason: tip,
          );
        }
        await tapFinder(t, find.byTooltip('Sonraki Sayfa'));
        await tapFinder(t, find.byTooltip('Son Sayfa'));
        expect(log, <String>['load:null:2:15:null', 'load:null:4:15:null']);
        expect(find.text('Sayfa 4 / 4 (Toplam 60 kişi)'), findsOneWidget);
      },
    );

    testWidgets('kendi hesabı: "Siz" rozeti, anahtar kapalı, "Sil" yok', (
      t,
    ) async {
      await pumpList(
        t,
        _view(session: _selfSession),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      expect(find.text('Siz'), findsOneWidget);
      await tapText(t, 'Ayşe Yılmaz');
      expect(find.text('Siz'), findsNWidgets(2));
      expect(find.text('Sil'), findsNothing);
      expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    });

    testWidgets(
      'alt sayfadaki anahtar: etkinleştirme çağrılır, alt sayfa kapanır',
      (t) async {
        final log = <String>[];
        await pumpList(
          t,
          _view(log: log),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        await tapText(t, 'Ayşe Yılmaz');
        await tapFinder(t, find.byType(Switch));
        expect(log, contains('toggle:10:false'));
        expect(find.byType(BottomSheet), findsNothing);
      },
    );

    testWidgets('silme onayında Vazgeç: silme çağrılmaz', (t) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      await tapText(t, 'Ayşe Yılmaz');
      await tapText(t, 'Sil');
      await tapText(t, 'Vazgeç');
      expect(log.where((e) => e.startsWith('delete')), isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets(
      'bakım düğmesi yalnız sağlık/temizlik işlevleri verilince görünür',
      (t) async {
        await pumpList(
          t,
          _view(maintenance: false),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        expect(
          find.byTooltip('Veritabanı Sağlığı & Çöp Temizliği'),
          findsNothing,
        );
        expect(find.byTooltip('Listeyi Yenile'), findsOneWidget);
      },
    );
  });

  group('AllUsersView kontrast', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        'rol çipleri ve alt metinler >= 4,5:1 (${dark ? 'koyu' : 'açık'})',
        (t) async {
          await pumpList(
            t,
            _view(),
            width: 360,
            height: 800,
            scale: 1,
            dark: dark,
          );
          final p = dark ? AppPalette.dark : AppPalette.light;
          // Seçili çip (Tüm Roller): ink metni, kendi tint'li zemininde.
          final selected = t.widget<FilterChip>(
            find.widgetWithText(FilterChip, 'Tüm Roller'),
          );
          final bg = selected.selectedColor!;
          final fg = selected.labelStyle!.color!;
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
          // Seçili olmayan çip: ikincil metin, yüzey üstünde.
          final other = t.widget<FilterChip>(
            find.widgetWithText(FilterChip, 'Site Yöneticileri'),
          );
          expect(
            contrastRatio(other.labelStyle!.color!, p.surface),
            greaterThanOrEqualTo(4.5),
          );
          // E-posta satırı: ikincil metin.
          final email = t.widget<Text>(find.text('kullanici10@e2e.local'));
          expect(
            contrastRatio(email.style!.color!, p.surface),
            greaterThanOrEqualTo(4.5),
          );
        },
      );
    }
  });

  group('AllUsersView geniş ekran ve yatay', () {
    testWidgets(
      '820x640 ve 900x400 (yatay), 1,0x/1,5x, açık/koyu: taşma yok; çipler tek satırda',
      (t) async {
        for (final (w, h) in const <(double, double)>[(820, 640), (900, 400)]) {
          for (final scale in const <double>[1.0, 1.5]) {
            for (final dark in const <bool>[false, true]) {
              await pumpList(
                t,
                _view(),
                width: w,
                height: h,
                scale: scale,
                dark: dark,
              );
              // Rol çipleri yatay kaydırılmaz: hepsi ekran içinde (sığmayan çip alta iner).
              for (var i = 0; i < 4; i++) {
                expect(
                  t.getRect(find.byType(FilterChip).at(i)).right,
                  lessThanOrEqualTo(w + 0.5),
                );
              }
              // Normal yazıda başlık eylemleri (veritabanı sağlığı + yenile) başlıkla aynı satırda;
              // büyük yazıda başlığın altına iner.
              final title = t.getRect(find.text('Kullanıcı Yönetimi'));
              final refresh = t.getRect(find.byTooltip('Listeyi Yenile'));
              if (scale == 1.0) {
                expect(refresh.left, greaterThanOrEqualTo(title.right));
              } else {
                expect(refresh.top, greaterThanOrEqualTo(title.bottom));
              }
              expect(t.takeException(), isNull);
            }
          }
        }
      },
    );
  });
}
