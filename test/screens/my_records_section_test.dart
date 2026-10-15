// Platform Faz 2a (F2.10): profilde "Kayıtlarım" bölümü (GET /app/my-records), salt okunur.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema. Hata asla "kayıt yok" diye
// gösterilmez; kayıt yoksa ProfileView'da bölüm gizlenir, sakin profilinde açıklama yazılır.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/views/profile_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/my_records_section.dart';

import '../design/harness.dart' show harnessApp;
import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

const UserSession _session = UserSession(
  token: 'tok',
  id: 1,
  fullName: 'Elif Şahin',
  email: 'elif.sahin@e2e.local',
  loginName: 'elif',
  role: UserRole.individual,
  isActive: true,
);

const UserSession _resident = UserSession(
  token: 'tok',
  id: 81,
  fullName: 'Ali Veli',
  email: 'a1.sakin.1.101@ahbu.local',
  loginName: 'a1.sakin',
  role: UserRole.apartmentOwner,
  isActive: true,
);

class _Form {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final TextEditingController fullName = TextEditingController(text: 'Elif Şahin');
  final TextEditingController email = TextEditingController(text: 'elif.sahin@e2e.local');
  final TextEditingController phone = TextEditingController();
  final TextEditingController password = TextEditingController();
  final TextEditingController current = TextEditingController();

  Widget view(PeopleFakeAuth? auth) => ProfileView(
    session: _session,
    formKey: key,
    fullNameController: fullName,
    emailController: email,
    phoneController: phone,
    passwordController: password,
    currentPasswordController: current,
    isSaving: false,
    onSave: () {},
    authService: auth,
  );
}

/// Aynı ağaç yapısı (State korunur): hesap değişimi testleri için.
Widget _host(Widget view) => harnessApp(SingleChildScrollView(child: view));

List<Map<String, dynamic>> _vehicles() => <Map<String, dynamic>>[
  pplVehicleJson(1, '34 ABC 123', note: 'gizli not'),
];

PeopleFakeAuth _auth() => PeopleFakeAuth()
  ..myRecords = <MyRecord>[
    pplMyRecord(vehicles: _vehicles()),
    pplMyRecord(
      apartmentId: 410,
      site: 'Mavi Park Sitesi',
      label: 'C Blok - 12',
      relation: ResidencyRelation.owner,
    ),
  ];

void main() {
  group('taşma matrisi', () {
    listMatrix('ProfileView: Kayıtlarım dolu (iki site, ilişki, giriş tarihi, araçlarım)', (t, w, h, s, dark) async {
      final auth = _auth();
      await pumpList(t, _Form().view(auth), width: w, height: h, scale: s, dark: dark);
      await settleFor(t);

      expect(find.text('Kayıtlarım'), findsOneWidget);
      expect(find.text('Gül Sitesi'), findsOneWidget);
      expect(find.text('Mavi Park Sitesi'), findsOneWidget);
      expect(find.text('A Blok - 5'), findsOneWidget);
      expect(find.text('C Blok - 12'), findsOneWidget);
      expect(find.text('Kiracı'), findsOneWidget);
      expect(find.text('Malik'), findsOneWidget);
      expect(find.text('Giriş: 05.03.2024'), findsNWidgets(2));
      expect(find.text('34 ABC 123'), findsOneWidget);
      expect(find.text('Kayıtlı araç yok.'), findsOneWidget);
      expect(find.text('gizli not'), findsNothing, reason: 'araç notu gösterilmez');
      expect(find.byTooltip('Kayıtlarımı yenile'), findsOneWidget);
      expect(find.text('Profili Kaydet'), findsOneWidget, reason: 'profil formu yerinde');
    });

    listMatrix('ResidentProfileView: Kayıtlarım dolu', (t, w, h, s, dark) async {
      final auth = _auth();
      await pumpList(
        t,
        ResidentProfileView(session: _resident, authService: auth),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await settleFor(t);
      expect(find.text('Hesap Bilgilerim'), findsOneWidget);
      expect(find.text('Kayıtlarım'), findsOneWidget);
      expect(find.text('A Blok - 5'), findsOneWidget);
    });

    listMatrix('yükleniyor: küçük iskelet', (t, w, h, s, dark) async {
      final auth = _auth()..myRecordsGate = Completer<void>();
      await pumpList(t, _Form().view(auth), width: w, height: h, scale: s, dark: dark);
      expect(find.text('Kayıtlarım'), findsOneWidget);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Henüz size ait bir kayıt görünmüyor.'), findsNothing);
    });

    listMatrix('hata: mesaj + Tekrar Dene ("kayıt yok" yazmaz)', (t, w, h, s, dark) async {
      final auth = _auth()..myRecordsError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await pumpList(
        t,
        ResidentProfileView(session: _resident, authService: auth),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await settleFor(t);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.textContaining('Henüz size ait bir kayıt'), findsNothing);
    });

    listMatrix('sakin profilinde kayıt yoksa açıklama', (t, w, h, s, dark) async {
      await pumpList(
        t,
        ResidentProfileView(session: _resident, authService: PeopleFakeAuth()),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await settleFor(t);
      expect(find.text('Kayıtlarım'), findsOneWidget);
      expect(find.textContaining('Henüz size ait bir kayıt görünmüyor.'), findsOneWidget);
    });
  });

  group('davranış', () {
    testWidgets('kayıt yoksa ProfileView\'da bölüm gizlenir (yönetici / bireysel kullanıcı için gürültü yok)', (t) async {
      final auth = PeopleFakeAuth();
      await pumpList(t, _Form().view(auth), width: 400, height: 1600, scale: 1.0, dark: false);
      await settleFor(t);
      expect(auth.myRecordsCalls, 1);
      expect(find.text('Kayıtlarım'), findsNothing);
    });

    testWidgets('authService verilmezse bölüm yok ve istek atılmaz (mevcut ekran davranışı korunur)', (t) async {
      final auth = _auth();
      await pumpList(t, _Form().view(null), width: 400, height: 1600, scale: 1.0, dark: false);
      await settleFor(t);
      expect(find.text('Kayıtlarım'), findsNothing);
      expect(auth.myRecordsCalls, 0);
      await pumpList(
        t,
        const ResidentProfileView(session: _resident),
        width: 400,
        height: 1600,
        scale: 1.0,
        dark: false,
      );
      expect(find.text('Kayıtlarım'), findsNothing);
    });

    testWidgets('Tekrar Dene kayıtları getirir; yenile düğmesi yeniden çeker', (t) async {
      final auth = _auth()..myRecordsError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await pumpList(t, _Form().view(auth), width: 400, height: 1600, scale: 1.0, dark: false);
      await settleFor(t);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);

      auth.myRecordsError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('A Blok - 5'), findsOneWidget);
      expect(auth.myRecordsCalls, 2);

      auth.myRecords = <MyRecord>[pplMyRecord(label: 'D Blok - 1')];
      await tapFinder(t, find.byTooltip('Kayıtlarımı yenile'));
      await settleFor(t);
      expect(auth.myRecordsCalls, 3);
      expect(find.text('D Blok - 1'), findsOneWidget);
      expect(find.text('A Blok - 5'), findsNothing);
    });

    testWidgets('yenileme hatası eski kayıtları silmez: liste + hata birlikte', (t) async {
      final auth = _auth();
      await pumpList(t, _Form().view(auth), width: 400, height: 1600, scale: 1.0, dark: false);
      await settleFor(t);
      auth.myRecordsError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await tapFinder(t, find.byTooltip('Kayıtlarımı yenile'));
      await settleFor(t);
      expect(find.text('A Blok - 5'), findsOneWidget);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
    });

    testWidgets('hesap değişimi: eski hesabın kayıtları yeni hesaba sızmaz, yeni hesap için yeniden yüklenir', (t) async {
      final first = _auth();
      final form = _Form();
      t.view.physicalSize = const Size(400, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(_host(form.view(first)));
      await settleFor(t);
      expect(find.text('Mavi Park Sitesi'), findsOneWidget);

      // Aynı ağaç, yeni hesap (pumpAt ağacı sıfırlar; burada State korunur: didUpdateWidget yolu).
      final second = PeopleFakeAuth()..myRecordsGate = Completer<void>();
      await t.pumpWidget(_host(form.view(second)));
      await t.pump();
      expect(find.text('Mavi Park Sitesi'), findsNothing, reason: 'eski hesabın verisi temizlendi');
      expect(second.myRecordsCalls, 1);
    });

    testWidgets('eski hesabın geç gelen yanıtı yeni hesabın bölümünü ezmez', (t) async {
      final first = _auth()..myRecordsGate = Completer<void>();
      final form = _Form();
      t.view.physicalSize = const Size(400, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(_host(form.view(first)));
      await t.pump();

      final second = PeopleFakeAuth()
        ..myRecords = <MyRecord>[pplMyRecord(label: 'Z Blok - 9', site: 'Yeni Hesap Sitesi')];
      await t.pumpWidget(_host(form.view(second)));
      await settleFor(t);
      expect(find.text('Z Blok - 9'), findsOneWidget);

      first.myRecordsGate!.complete(); // eski hesabın yanıtı geç gelir
      await settleFor(t);
      expect(find.text('Z Blok - 9'), findsOneWidget);
      expect(find.text('Mavi Park Sitesi'), findsNothing);
    });

    testWidgets('MyRecordsSection tek başına: reload() ile çekilir', (t) async {
      final auth = _auth();
      final key = GlobalKey<MyRecordsSectionState>();
      await pumpList(
        t,
        MyRecordsSection(key: key, authService: auth, showWhenEmpty: true),
        width: 400,
        height: 1600,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      await key.currentState!.reload();
      await settleFor(t);
      expect(auth.myRecordsCalls, 2);
    });
  });
}
