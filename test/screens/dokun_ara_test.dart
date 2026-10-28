// "Dokun-ara" (P2-23, K13): büyük 112 düğmesi ve "Yöneticiyi ara" kutusu.
//  - 112: tel:112 açılır; KURU MOD (arama açılamayan ortam): numara büyük gösterilir + kopyalanır; Semantics.
//  - Yöneticiyi ara: telefon yokken (ölü düğme yok, nedeni söyler, hiçbir şey aranmaz), telefon varken tel: açılır, çok site,
//    kendi sitesinin yöneticisi, kuru mod; Panel bağlantısı (veri gelince / hata / 404 / yalnız sakin); yönetici ipucu.
//  - Dairem > Güvenlik ve destek bölümünde 112 düğmesi.
//  - Taşma: 320 / 360 dp x yazı 1,5 / 2,0 x açık / koyu.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_management.dart';
import 'package:site_kapi_kontrol/models/manager_contact.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/ui/helpers/dial_call.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/views/my_apartment_view.dart';
import 'package:site_kapi_kontrol/ui/views/profile_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/dial_fallback.dart';
import 'package:site_kapi_kontrol/ui/widgets/emergency_call_button.dart';
import 'package:site_kapi_kontrol/ui/widgets/manager_call_tile.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../design/harness.dart';
import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

/// Sahte telefon uygulaması açıcısı: çağrıları kaydeder; [opens] false iken "açılamadı" (kuru mod).
class _Phone {
  _Phone({this.opens = true});

  bool opens;
  final List<Uri> calls = <Uri>[];

  Future<bool> launch(Uri uri) async {
    calls.add(uri);
    return opens;
  }
}

/// Pano yazımlarını yakalar (Clipboard.setData).
List<String> _recordClipboard(WidgetTester t) {
  final copied = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

const _contact = ManagerContact(
  siteCode: 1,
  siteName: 'Gül Sitesi',
  managerName: 'Ali Yönetici',
  phone: '0532 123 45 67',
);
const _noPhone = ManagerContact(siteCode: 1, siteName: 'Gül Sitesi', managerName: 'Ali Yönetici');

Future<void> _pump(
  WidgetTester t,
  Widget w, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) => pumpList(t, w, width: width, height: height, scale: scale, dark: dark);

const _tileKey = ValueKey<String>('panel_hizli_yoneticiyiAra');
const _emergencyKey = ValueKey<String>('acil_112_dugme');

void main() {
  group('112 düğmesi', () {
    testWidgets('görünen metin 112 + "Acil Çağrı Merkezi\'ni ara"; dokununca tel:112 açılır, kuru mod kartı çıkmaz', (t) async {
      final phone = _Phone();
      final haptics = recordHaptics(t);
      await _pump(t, EmergencyCallButton(launcher: phone.launch));
      expect(find.text('112'), findsOneWidget);
      expect(find.text("Acil Çağrı Merkezi'ni ara"), findsOneWidget);

      await t.tap(find.byKey(_emergencyKey));
      await settleFor(t);
      expect(phone.calls.single.toString(), 'tel:112');
      expect(phone.calls.single.scheme, 'tel');
      expect(find.byType(DialFallbackCard), findsNothing, reason: 'arama açıldı: numara kartına gerek yok');
      expect(haptics, isNotEmpty, reason: 'dokunuşta haptik geri bildirim');
    });

    testWidgets('KURU MOD: arama açılamazsa numara büyük gösterilir ve kopyalanır; sonraki başarılı dokunuş kartı kaldırır', (
      t,
    ) async {
      final copied = _recordClipboard(t);
      final phone = _Phone(opens: false);
      await _pump(t, EmergencyCallButton(launcher: phone.launch));
      expect(find.byType(DialFallbackCard), findsNothing, reason: 'dokunmadan önce kart yok');

      await t.tap(find.byKey(_emergencyKey));
      await settleFor(t);
      expect(phone.calls.single.toString(), 'tel:112');
      expect(find.byType(DialFallbackCard), findsOneWidget);
      expect(find.text('Bu cihazdan arama başlatılamadı'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('arama_kuru_mod_numara')), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const ValueKey<String>('arama_kuru_mod_numara'))).data,
        '112',
        reason: 'kuru modda numara görünür',
      );

      await t.tap(find.byKey(const ValueKey<String>('arama_kuru_mod_kopyala')));
      await settleFor(t);
      expect(copied, <String>['112']);
      expect(find.text('Numara kopyalandı.'), findsOneWidget);

      // Cihaz aramayı açabilir hale gelirse (ör. SIM takıldı): ikinci dokunuş kartı kaldırır.
      phone.opens = true;
      await t.tap(find.byKey(_emergencyKey));
      await settleFor(t);
      expect(phone.calls, hasLength(2));
      expect(find.byType(DialFallbackCard), findsNothing);
    });

    testWidgets('Semantics: tek düğüm; ad görünen metni içerir, ipucu dokununca olanı söyler; kuru mod kartı canlı bölge', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final phone = _Phone(opens: false);
      await _pump(t, EmergencyCallButton(launcher: phone.launch));
      expect(
        t.getSemantics(find.byKey(_emergencyKey)),
        isSemantics(
          label: "112 Acil Çağrı Merkezi'ni ara",
          hint: 'Telefon uygulamasını 112 numarasıyla açar',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // Dokunma hedefi >= 48 dp (büyük düğme en az 72 dp).
      expect(t.getSize(find.byKey(_emergencyKey)).height, greaterThanOrEqualTo(72));

      // Anlamsal eylemle de çalışır (ekran okuyucu çift dokunuşu).
      t.semantics.tap(find.semantics.byLabel("112 Acil Çağrı Merkezi'ni ara"));
      await settleFor(t);
      expect(phone.calls, hasLength(1));
      expect(
        t.getSemantics(find.byType(DialFallbackCard)),
        isSemantics(isLiveRegion: true),
        reason: 'kuru mod kartı belirince ekran okuyucu duyurur',
      );
      expect(find.bySemanticsLabel('Numarayı kopyala'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('çift dokunuş aramayı iki kez denemez (uçuştayken yoksayılır)', (t) async {
      final gate = Completer<bool>();
      var launches = 0;
      await _pump(t, EmergencyCallButton(launcher: (_) {
        launches++;
        return gate.future;
      }));
      await t.tap(find.byKey(_emergencyKey));
      await t.pump();
      await t.tap(find.byKey(_emergencyKey));
      await t.pump();
      expect(launches, 1);
      gate.complete(true);
      await settleFor(t);
    });

    for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5), (412, 915, 1.0)]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('taşma yok: 112 düğmesi (+ kuru mod) ${w.toInt()}x${h.toInt()} yazı $s ${dark ? 'koyu' : 'açık'}', (t) async {
          final phone = _Phone(opens: false);
          await _pump(t, EmergencyCallButton(launcher: phone.launch), width: w, height: h, scale: s, dark: dark);
          await t.tap(find.byKey(_emergencyKey));
          await settleFor(t);
          expect(find.byType(DialFallbackCard), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('Yöneticiyi ara kutusu', () {
    testWidgets('telefon KAYITLIYSA: yönetici adı görünür, dokununca tel: yönetici numarasıyla açılır', (t) async {
      final phone = _Phone();
      await _pump(t, ManagerCallTile(contacts: const [_contact], launcher: phone.launch));
      expect(find.text('Yöneticiyi ara'), findsOneWidget);
      expect(find.text('Ali Yönetici'), findsOneWidget);

      await t.tap(find.byKey(_tileKey));
      await settleFor(t);
      expect(phone.calls.single.toString(), 'tel:05321234567');
      expect(find.byType(DialFallbackCard), findsNothing);
    });

    testWidgets('telefon YOKKEN: kutu görünür kalır, "Telefon kayıtlı değil" der; dokununca nedeni söyler, HİÇBİR ŞEY aranmaz', (
      t,
    ) async {
      final phone = _Phone();
      await _pump(t, ManagerCallTile(contacts: const [_noPhone], launcher: phone.launch));
      expect(find.text('Yöneticiyi ara'), findsOneWidget);
      expect(find.text('Telefon kayıtlı değil'), findsOneWidget);
      expect(find.text('Ali Yönetici'), findsNothing, reason: 'numarası yoksa alt satır durumu söyler');

      await t.tap(find.byKey(_tileKey));
      await settleFor(t);
      expect(phone.calls, isEmpty, reason: 'numara yok: telefon uygulaması açılmaz');
      expect(find.textContaining('henüz telefon numarası eklememiş'), findsOneWidget);
      expect(find.byType(DialFallbackCard), findsNothing);
    });

    testWidgets('geçersiz (aranamayan) kayıt numara sayılmaz: "Telefon kayıtlı değil"', (t) async {
      final phone = _Phone();
      const bad = ManagerContact(siteCode: 1, siteName: 'Gül Sitesi', managerName: 'Ali', phone: '*123#');
      await _pump(t, ManagerCallTile(contacts: const [bad], launcher: phone.launch));
      expect(find.text('Telefon kayıtlı değil'), findsOneWidget);
      await t.tap(find.byKey(_tileKey));
      await settleFor(t);
      expect(phone.calls, isEmpty);
    });

    testWidgets('KURU MOD: telefon uygulaması açılamazsa numara alt sayfada gösterilir ve kopyalanır', (t) async {
      final copied = _recordClipboard(t);
      final phone = _Phone(opens: false);
      await _pump(t, ManagerCallTile(contacts: const [_contact], launcher: phone.launch));
      await t.tap(find.byKey(_tileKey));
      await settleFor(t);
      expect(phone.calls, hasLength(1));
      expect(find.byType(DialFallbackCard), findsOneWidget);
      expect(find.text('0532 123 45 67'), findsOneWidget, reason: 'numara gruplu gösterilir');
      expect(find.text('Ali Yönetici'), findsWidgets);

      await t.tap(find.byKey(const ValueKey<String>('arama_kuru_mod_kopyala')));
      await settleFor(t);
      expect(copied, <String>['05321234567'], reason: 'kopyalanan değer aranabilir biçim');
      await t.tap(find.text('Kapat'));
      await settleFor(t);
      expect(find.byType(DialFallbackCard), findsNothing);
    });

    testWidgets('birden çok site: dokununca siteler listelenir; telefonu olanın yanında Ara, olmayanda "Telefon kayıtlı değil"', (
      t,
    ) async {
      final phone = _Phone();
      const second = ManagerContact(siteCode: 2, siteName: 'Lale Sitesi', managerName: 'Can Yönetici');
      await _pump(t, ManagerCallTile(contacts: const [_contact, second], launcher: phone.launch));
      expect(find.text('2 site'), findsOneWidget);

      await t.tap(find.byKey(_tileKey));
      await settleFor(t);
      expect(find.text('Gül Sitesi'), findsOneWidget);
      expect(find.text('Lale Sitesi'), findsOneWidget);
      expect(find.text('Telefon kayıtlı değil'), findsOneWidget, reason: 'yalnız ikinci satırda');
      expect(find.text('Ara'), findsOneWidget, reason: 'numarası olmayan satırda düğme yok');

      await t.tap(find.byKey(const ValueKey<String>('yonetici_ara_1')));
      await settleFor(t);
      expect(phone.calls.single.toString(), 'tel:05321234567');
      expect(find.text('Lale Sitesi'), findsNothing, reason: 'arama açılınca sayfa kapanır');
    });

    testWidgets('birden çok site + açılamayan arama: sayfanın altında kuru mod kartı', (t) async {
      final phone = _Phone(opens: false);
      const second = ManagerContact(siteCode: 2, siteName: 'Lale Sitesi', managerName: 'Can', phone: '+90 212 555 12 34');
      await _pump(t, ManagerCallTile(contacts: const [_contact, second], launcher: phone.launch));
      await t.tap(find.byKey(_tileKey));
      await settleFor(t);
      await t.tap(find.byKey(const ValueKey<String>('yonetici_ara_2')));
      await settleFor(t);
      expect(find.byType(DialFallbackCard), findsOneWidget);
      expect(find.text('+90 212 555 12 34'), findsOneWidget);
    });

    testWidgets('callable: kendi sitesinin yöneticisi olan satır süzülür', (t) async {
      const self = ManagerContact(siteCode: 3, siteName: 'Benim Sitem', isSelf: true);
      expect(ManagerCallTile.callable(const [self]), isEmpty);
      expect(ManagerCallTile.callable(const [self, _contact]), const [_contact]);
    });

    testWidgets('Semantics: tek düğme; etiket = başlık + alt satır, ipucu dokununca olanı söyler; telefon yokken de ad doğru', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final phone = _Phone();
      await _pump(t, ManagerCallTile(contacts: const [_contact], launcher: phone.launch));
      expect(
        t.getSemantics(find.byKey(_tileKey)),
        isSemantics(
          label: 'Yöneticiyi ara. Ali Yönetici',
          hint: ManagerCallTexts.hintCall,
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(t.getSize(find.byKey(_tileKey)).height, greaterThanOrEqualTo(56));

      await _pump(t, ManagerCallTile(contacts: const [_noPhone], launcher: phone.launch));
      expect(
        t.getSemantics(find.byKey(_tileKey)),
        isSemantics(
          label: 'Yöneticiyi ara. Telefon kayıtlı değil',
          hint: ManagerCallTexts.hintNoPhone,
          isButton: true,
          hasTapAction: true,
        ),
      );

      await _pump(t, ManagerCallTile(contacts: const [_contact, _noPhone], launcher: phone.launch));
      expect(
        t.getSemantics(find.byKey(_tileKey)),
        isSemantics(
          label: 'Yöneticiyi ara. 2 site',
          hint: ManagerCallTexts.hintMany,
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('Semantics (çok site): satır düğmesinin adı siteyi söyler ve anlamsal eylemle aranır', (t) async {
      final handle = t.ensureSemantics();
      final phone = _Phone();
      await _pump(t, ManagerCallTile(contacts: const [_contact, _noPhone], launcher: phone.launch));
      await t.tap(find.byKey(_tileKey));
      await settleFor(t);
      expect(
        t.getSemantics(find.byKey(const ValueKey<String>('yonetici_ara_1'))),
        isSemantics(label: 'Gül Sitesi yöneticisini ara', isButton: true, hasTapAction: true),
      );
      t.semantics.tap(find.semantics.byLabel('Gül Sitesi yöneticisini ara'));
      await settleFor(t);
      expect(phone.calls, hasLength(1));
      handle.dispose();
    });

    for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5), (412, 915, 1.0)]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('taşma yok: kutu + kuru mod sayfası ${w.toInt()}x${h.toInt()} yazı $s ${dark ? 'koyu' : 'açık'}', (t) async {
          final phone = _Phone(opens: false);
          const long = ManagerContact(
            siteCode: 9,
            siteName: 'Çok Uzun Adlı Güneşli Vadi Konutları Sitesi',
            managerName: 'Muhammed Abdurrahman Karaoğlanoğulları',
            phone: '+90 532 123 45 67',
          );
          await _pump(
            t,
            Row(children: [Expanded(child: ManagerCallTile(contacts: const [long], launcher: phone.launch))]),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          await t.tap(find.byKey(_tileKey));
          await settleFor(t);
          expect(find.byType(DialFallbackCard), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('Panel (ModuleShowcaseView) bağlantısı', () {
    UserSession session(UserRole role, {String? phone}) => UserSession(
      id: 7,
      fullName: 'Ayşe Yılmaz',
      email: 'a@example.com',
      loginName: null,
      role: role,
      isActive: true,
      token: 't',
      phoneNumber: phone,
    );

    Widget showcase({
      required ShowcaseAudience audience,
      UserRole role = UserRole.apartmentOwner,
      Future<List<ManagerContact>> Function()? fetch,
      DialLauncher? launcher,
      bool phoneMissing = false,
      ValueChanged<SirketMenuItem>? onOpen,
      List<SirketMenuItem>? items,
    }) => ModuleShowcaseView(
      key: const ValueKey<String>('vitrin'),
      session: session(role),
      audience: audience,
      menuItems:
          items ??
          YanMenu.visibleItems(
            role: role,
            isResidentMode: audience == ShowcaseAudience.resident,
            canToggleMode: false,
            additionalItems: <SirketMenuItem>{SirketMenuItem.kapilar, SirketMenuItem.belgeler},
            hiddenItems: const <SirketMenuItem>{},
          ),
      onOpen: onOpen ?? (_) {},
      fetchManagerContacts: fetch,
      dialLauncher: launcher,
      managerPhoneMissing: phoneMissing,
    );

    testWidgets('sakin: veri gelince "Yöneticiyi ara" hızlı işlemlerin SONUNA eklenir ve aranır', (t) async {
      final phone = _Phone();
      await _pump(
        t,
        showcase(audience: ShowcaseAudience.resident, fetch: () async => const [_contact], launcher: phone.launch),
        height: 1600,
      );
      await settleFor(t);
      expect(find.byKey(_tileKey), findsOneWidget);
      final quickTiles = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('panel_hizli_') && w is Material,
      );
      expect(quickTiles.evaluate().last.widget.key, _tileKey, reason: 'öteki kutuların yeri kaymasın: sona eklenir');
      await t.ensureVisible(find.byKey(_tileKey));
      await t.tap(find.byKey(_tileKey));
      await settleFor(t);
      expect(phone.calls.single.toString(), 'tel:05321234567');
    });

    testWidgets('sakin: yükleme sürerken / hata verince / eski sunucuda (404) kutu ÇİZİLMEZ ("numara yok" denmez)', (t) async {
      final gate = Completer<List<ManagerContact>>();
      await _pump(t, showcase(audience: ShowcaseAudience.resident, fetch: () => gate.future), height: 1600);
      expect(find.byKey(_tileKey), findsNothing, reason: 'yüklenirken yok');
      expect(find.text('Telefon kayıtlı değil'), findsNothing);
      gate.complete(const [_contact]);
      await settleFor(t);
      expect(find.byKey(_tileKey), findsOneWidget);

      await _pump(
        t,
        showcase(audience: ShowcaseAudience.resident, fetch: () async => throw ApiException('Sunucu yanıt vermiyor.')),
        height: 1600,
      );
      await settleFor(t);
      expect(find.byKey(_tileKey), findsNothing, reason: 'hata: kutu yok, yanlış "numara yok" mesajı da yok');
      expect(find.text('Telefon kayıtlı değil'), findsNothing);

      await _pump(
        t,
        showcase(
          audience: ShowcaseAudience.resident,
          fetch: () async => throw ApiException('Bulunamadı.', statusCode: 404),
        ),
        height: 1600,
      );
      await settleFor(t);
      expect(find.byKey(_tileKey), findsNothing, reason: 'eski sunucu (uç yok): özellik yok sayılır');
    });

    testWidgets('sakin: kendi sitesinin yöneticisiyse (sakin modundaki yönetici) kutu çizilmez; başka sitesi varsa o çizilir', (
      t,
    ) async {
      const self = ManagerContact(siteCode: 3, siteName: 'Benim Sitem', isSelf: true);
      await _pump(
        t,
        showcase(role: UserRole.siteManager, audience: ShowcaseAudience.resident, fetch: () async => const [self]),
        height: 1600,
      );
      await settleFor(t);
      expect(find.byKey(_tileKey), findsNothing);

      await _pump(
        t,
        showcase(
          role: UserRole.siteManager,
          audience: ShowcaseAudience.resident,
          fetch: () async => const [self, _contact],
        ),
        height: 1600,
      );
      await settleFor(t);
      expect(find.byKey(_tileKey), findsOneWidget);
      expect(find.text('Ali Yönetici'), findsOneWidget);
    });

    testWidgets('yönetici ve bireysel vitrinde kaynak verilse bile sakin kutusu çizilmez ve kaynak ÇAĞRILMAZ', (t) async {
      var calls = 0;
      Future<List<ManagerContact>> fetch() async {
        calls++;
        return const [_contact];
      }

      await _pump(t, showcase(role: UserRole.siteManager, audience: ShowcaseAudience.admin, fetch: fetch), height: 1600);
      await settleFor(t);
      await _pump(t, showcase(role: UserRole.individual, audience: ShowcaseAudience.individual, fetch: fetch), height: 1600);
      await settleFor(t);
      expect(find.byKey(_tileKey), findsNothing);
      expect(calls, 0);
    });

    testWidgets('kaynak verilmezse (varsayılan) kutu yok; geçici hatada eldeki bilgi korunur, 404 kutuyu kaldırır', (t) async {
      await _pump(t, showcase(audience: ShowcaseAudience.resident), height: 1600);
      await settleFor(t);
      expect(find.byKey(_tileKey), findsNothing);

      var round = 0;
      Future<List<ManagerContact>> fetch() async {
        round++;
        if (round == 1) return const [_contact];
        if (round == 2) throw ApiException('Ağ hatası.');
        throw ApiException('Yok.', statusCode: 404);
      }

      await _pump(t, showcase(audience: ShowcaseAudience.resident, fetch: fetch), height: 1600);
      await settleFor(t);
      expect(find.byKey(_tileKey), findsOneWidget);
      final state = t.state<ModuleShowcaseViewState>(find.byKey(const ValueKey<String>('vitrin')));
      await state.reload();
      await settleFor(t);
      expect(find.byKey(_tileKey), findsOneWidget, reason: 'geçici hata: eski bilgi kalır');
      await state.reload();
      await settleFor(t);
      expect(find.byKey(_tileKey), findsNothing, reason: '404: özellik kapanır');
    });

    testWidgets('yönetici: profilinde telefon yoksa "Telefon numaranızı ekleyin" ipucu; Profilim\'e git menüyü açar', (t) async {
      final opened = <SirketMenuItem>[];
      await _pump(
        t,
        showcase(
          role: UserRole.siteManager,
          audience: ShowcaseAudience.admin,
          phoneMissing: true,
          onOpen: opened.add,
        ),
        height: 1600,
      );
      expect(find.text(ManagerPhoneHint.title), findsOneWidget);
      expect(find.textContaining('sakinlere, kurul üyelerine ve görevlilere'), findsOneWidget, reason: 'numaranın kime görüneceği yazılır');
      await t.tap(find.byKey(const ValueKey<String>('panel_telefon_ipucu_profil')));
      await settleFor(t);
      expect(opened, <SirketMenuItem>[SirketMenuItem.profilim]);
    });

    testWidgets('yönetici: telefon varsa ipucu yok; sakin vitrininde de ipucu çizilmez', (t) async {
      await _pump(t, showcase(role: UserRole.siteManager, audience: ShowcaseAudience.admin), height: 1600);
      expect(find.text(ManagerPhoneHint.title), findsNothing);
      await _pump(t, showcase(audience: ShowcaseAudience.resident, phoneMissing: true), height: 1600);
      expect(find.text(ManagerPhoneHint.title), findsNothing, reason: 'ipucu yalnız yönetici kitlesine');
    });

    testWidgets('yönetici ipucu: Profilim menüde yoksa düğmesiz; Semantics başlık + düğme', (t) async {
      final handle = t.ensureSemantics();
      await _pump(
        t,
        showcase(
          role: UserRole.siteManager,
          audience: ShowcaseAudience.admin,
          phoneMissing: true,
          items: const <SirketMenuItem>[SirketMenuItem.siteler],
        ),
        height: 1600,
      );
      expect(find.text(ManagerPhoneHint.title), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_telefon_ipucu_profil')), findsNothing);

      await _pump(
        t,
        showcase(role: UserRole.siteManager, audience: ShowcaseAudience.admin, phoneMissing: true),
        height: 1600,
      );
      expect(
        t.getSemantics(find.byKey(const ValueKey<String>('panel_telefon_ipucu_profil'))),
        isSemantics(label: "Profilim'e git", isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5)]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('taşma yok: sakin vitrini + Yöneticiyi ara, yönetici ipucu ${w.toInt()}x${h.toInt()} yazı $s ${dark ? 'koyu' : 'açık'}', (
          t,
        ) async {
          await _pump(
            t,
            showcase(audience: ShowcaseAudience.resident, fetch: () async => const [_contact, _noPhone]),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          await settleFor(t);
          expect(find.byKey(_tileKey), findsOneWidget);
          expect(t.takeException(), isNull);

          await _pump(
            t,
            showcase(role: UserRole.siteManager, audience: ShowcaseAudience.admin, phoneMissing: true),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          await settleFor(t);
          expect(find.text(ManagerPhoneHint.title), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('Dairem > Güvenlik ve destek', _apartmentTests);

  group('Profilim telefon alanı (aydınlatma)', () {
    Future<void> pumpProfile(WidgetTester t, UserRole role) async {
      final phone = TextEditingController();
      addTearDown(phone.dispose);
      final other = <TextEditingController>[for (var i = 0; i < 4; i++) TextEditingController()];
      addTearDown(() {
        for (final c in other) {
          c.dispose();
        }
      });
      await pumpList(
        t,
        ProfileView(
          session: UserSession(
            id: 7,
            fullName: 'Ayşe Yılmaz',
            email: 'a@example.com',
            loginName: null,
            role: role,
            isActive: true,
            token: 't',
          ),
          formKey: GlobalKey<FormState>(),
          fullNameController: other[0],
          emailController: other[1],
          phoneController: phone,
          passwordController: other[2],
          currentPasswordController: other[3],
          isSaving: false,
          onSave: () {},
        ),
        width: 400,
        height: 1800,
        scale: 1.0,
        dark: false,
      );
    }

    testWidgets('site yöneticisi: numaranın kimlere görüneceği yazılır', (t) async {
      await pumpProfile(t, UserRole.siteManager);
      expect(find.textContaining('sakinlere, kurul üyelerine ve görevlilere'), findsOneWidget);
      expect(find.textContaining('"Yöneticiyi ara" kutusunda görünür'), findsOneWidget);
    });

    testWidgets('sakin ve süper kullanıcı: yalnız biçim ipucu, yönetici uyarısı yok', (t) async {
      for (final role in <UserRole>[UserRole.apartmentOwner, UserRole.superUser, UserRole.individual]) {
        await pumpProfile(t, role);
        expect(find.text('Cep telefonu: +90 5XX XXX XX XX'), findsOneWidget, reason: '$role');
        expect(find.textContaining('Yöneticiyi ara'), findsNothing, reason: '$role');
      }
    });
  });
}

// --- Dairem fixture'ı (my_apartment_view_test.dart'taki sahte servisin en küçük hâli) ---------------------------------

class _FakeApt extends ApartmentManagementService {
  _FakeApt(this.data) : super(authService: PeopleFakeAuth(), api: ApartmentManagementApi(baseUrl: 'http://localhost'));

  final MyApartmentsData data;

  @override
  Future<MyApartmentsData> mine() async => data;
}

MyApartmentsData _aptData() => MyApartmentsData(
  apartments: <MyApartment>[
    MyApartment(
      apartmentId: 5,
      siteCode: 11,
      siteName: 'Gül Sitesi',
      label: 'A Blok - 5',
      myRole: 'family_member',
      isAdmin: false,
      isOwner: false,
      adminName: 'Veli Kaya',
      adminSide: 'owner',
      delegated: false,
      owner: AptPerson(personId: 1, name: 'Veli Kaya', hasAccount: true),
      family: <AptFamilyMember>[],
      can: AptCan(),
      proxies: <AptProxy>[],
    ),
  ],
  canSearch: false,
);

void _apartmentTests() {
  testWidgets('bölüm açılınca büyük 112 düğmesi var; dokununca tel:112; kuru modda numara + kopyala', (t) async {
    final copied = _recordClipboard(t);
    final phone = _Phone(opens: false);
    await pumpList(
      t,
      MyApartmentView(authService: PeopleFakeAuth(), service: _FakeApt(_aptData()), dialLauncher: phone.launch),
      width: 400,
      height: 1800,
      scale: 1.0,
      dark: false,
    );
    await settleFor(t);
    expect(find.byKey(_emergencyKey), findsNothing, reason: 'gizli bölüm varsayılan kapalı');

    await t.tap(find.text('Güvenlik ve destek'));
    await settleFor(t);
    expect(find.byKey(_emergencyKey), findsOneWidget);
    expect(find.textContaining('ALO 183'), findsOneWidget);
    expect(find.textContaining('KADES'), findsOneWidget);

    await t.ensureVisible(find.byKey(_emergencyKey));
    await t.tap(find.byKey(_emergencyKey));
    await settleFor(t);
    expect(phone.calls.single.toString(), 'tel:112');
    expect(find.byType(DialFallbackCard), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey<String>('arama_kuru_mod_kopyala')));
    await t.tap(find.byKey(const ValueKey<String>('arama_kuru_mod_kopyala')));
    await settleFor(t);
    expect(copied, <String>['112']);
  });

  for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5)]) {
    testWidgets('taşma yok: Dairem güvenlik bölümü ${w.toInt()}x${h.toInt()} yazı $s', (t) async {
      final phone = _Phone(opens: false);
      await pumpList(
        t,
        MyApartmentView(authService: PeopleFakeAuth(), service: _FakeApt(_aptData()), dialLauncher: phone.launch),
        width: w,
        height: 2400,
        scale: s,
        dark: false,
      );
      await settleFor(t);
      await t.tap(find.text('Güvenlik ve destek'));
      await settleFor(t);
      await t.ensureVisible(find.byKey(_emergencyKey));
      await t.tap(find.byKey(_emergencyKey));
      await settleFor(t);
      expect(find.byType(DialFallbackCard), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
