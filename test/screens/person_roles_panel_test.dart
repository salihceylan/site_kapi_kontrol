// Kişi kartındaki "Roller" bölümü (PersonRolesPanel): tanıtımdaki beş rolün hepsi kartta; mevcut roller
// rozetle görünür; ek rol ver / kaldır, yönetici daveti, daireye bağlama ve geçiş bağlantısı kartın içinden;
// hesapsız / daire hesabı / zaten yönetici kişide ek rol düğmesi yok, nedeni yazılır; salt okur bölümü görmez;
// dar ekranda büyük yazıda taşmaz.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

import 'dialog_layout_harness.dart';
import 'people_fixtures.dart';

PeopleScope _scope(PeopleFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

Future<void> _open(
  WidgetTester t,
  PeopleFakeAuth auth,
  int personId, {
  bool canWrite = true,
  double width = 400,
  double height = 900,
  double scale = 1.0,
}) async {
  await openDialogAt(
    t,
    (c) => PersonCardDialog.show(c, scope: _scope(auth, canWrite: canWrite), personId: personId),
    width: width,
    height: height,
    scale: scale,
    dark: false,
  );
  await settleFor(t);
}

Future<void> _tapText(WidgetTester t, String text) async {
  await scrollTo(t, find.text(text));
  await t.tap(find.text(text));
  await settleFor(t);
}

void main() {
  testWidgets('rol bölümü: yönetici, görev, daire sakini, misafir; hesaplı kişiye "Görev Ver" -> pencere -> kaydedilir', (t) async {
    final auth = PeopleFakeAuth.seeded();
    await _open(t, auth, 2); // Mehmet Demir: hesaplı kiracı (user_code 702)

    for (final title in const <String>['Roller', 'Site yöneticisi', 'Görev', 'Daire sakini', 'Misafir ve kurye']) {
      await scrollTo(t, find.text(title).first);
      expect(find.text(title), findsWidgets, reason: title);
    }
    expect(find.text('Yönetici Olarak Davet Et'), findsOneWidget);
    expect(find.text('Uygulamaya davet'), findsNothing); // hesabı olana davet gösterilmez
    expect(find.text('Geçiş Bağlantısı Oluştur'), findsOneWidget);

    await _tapText(t, 'Görev Ver');
    expect(find.text('Rehberde göster'), findsOneWidget);
    expect(find.textContaining('kişinin onayını alın'), findsOneWidget);
    await t.tap(find.text('Kaydet'));
    await settleFor(t);

    expect(auth.dutyCalls.single.personId, 2);
    expect(auth.dutyCalls.single.duty, 'doorman');
    await scrollTo(t, find.text('Görevi Düzenle'));
    expect(find.text('Görevi Düzenle'), findsOneWidget);
    expect(find.textContaining('Uygulama yetkisi açık'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('"Diğer" görev unvansız kaydedilmez; unvanla kaydedilir', (t) async {
    final auth = PeopleFakeAuth.seeded();
    await _open(t, auth, 2);
    await _tapText(t, 'Görev Ver');
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await settleFor(t);
    await t.tap(find.text('Diğer').last);
    await settleFor(t);
    await t.tap(find.text('Kaydet'));
    await settleFor(t);
    expect(find.textContaining('unvan yazın'), findsOneWidget);
    expect(auth.dutyCalls, isEmpty);
    await t.enterText(find.byType(TextField).first, 'Bahçıvan');
    await t.tap(find.text('Kaydet'));
    await settleFor(t);
    expect(auth.dutyCalls.single.title, 'Bahçıvan');
  });

  testWidgets('görevi olan kişide "Görevi Kaldır" -> onay -> kaldırılır', (t) async {
    final auth = PeopleFakeAuth.seeded();
    auth.teamDuties[2] = const TeamDuty(
      personId: 2,
      fullName: 'Mehmet Demir',
      duty: 'board_member',
      showInDirectory: true,
      access: 'granted',
    );
    await _open(t, auth, 2);
    expect(find.text('Yönetim kurulu üyesi'), findsWidgets); // rozet + not
    await _tapText(t, 'Görevi Kaldır');
    await t.tap(find.text('Görevi Kaldır').last);
    await settleFor(t);
    expect(auth.dutyEndCalls, <int>[2]);
  });

  testWidgets('eski ek rol kadroda değilse "Eski ek rol" satırı ve "Rolü Kaldır" çalışır', (t) async {
    final auth = PeopleFakeAuth.seeded();
    auth.staffRoles.add(
      const StaffRoleRecord(userCode: 702, fullName: 'Mehmet Demir', email: 'mehmet@example.com', role: 'STAFF'),
    );
    await _open(t, auth, 2);
    expect(find.text('Eski ek rol'), findsOneWidget);
    await _tapText(t, 'Rolü Kaldır');
    await t.tap(find.text('Rolü Kaldır').last);
    await settleFor(t);
    expect(auth.staffRemoveCalls, <int>[702]);
  });

  testWidgets('hesapsız kişide görev verilir (yetki yok notu) ve uygulamaya davet gönderilir / iptal edilir', (t) async {
    final auth = PeopleFakeAuth.seeded();
    await _open(t, auth, 1); // Ayşe Yılmaz: hesapsız malik, e-postalı
    expect(find.text('Daire sakini'), findsWidgets);
    expect(find.text('Başka Bir Daireye Bağla'), findsOneWidget);

    await _tapText(t, 'Görev Ver');
    await t.tap(find.text('Kaydet'));
    await settleFor(t);
    expect(find.textContaining('Kişinin uygulama hesabı yok'), findsOneWidget);

    await _tapText(t, 'Uygulamaya Davet Et');
    expect(auth.inviteSendCalls, <int>[1]);
    expect(find.textContaining('Davet gönderildi (1/5)'), findsOneWidget);
    expect(find.text('Yeniden Gönder'), findsOneWidget);

    await _tapText(t, 'Daveti İptal Et');
    expect(auth.inviteRevokeCalls, <int>[1]);

    await _tapText(t, 'Yönetici Olarak Davet Et');
    await t.tap(find.text('Davet Gönder'));
    await settleFor(t);
    expect(auth.managerInviteCalls, <String>['ayse@example.com']);
  });

  testWidgets('zaten yönetici olan kişi: rozet, davet ve görev düğmesi yok', (t) async {
    final auth = PeopleFakeAuth.seeded();
    auth.siteManagers.add(
      const SiteManagerRecord(
        userCode: 702,
        fullName: 'Mehmet Demir',
        email: 'mehmet@example.com',
        userRole: 'site_manager',
        siteRole: 'manager',
        isOwner: false,
      ),
    );
    await _open(t, auth, 2);
    expect(find.text('Site yöneticisi'), findsWidgets);
    expect(find.text('Yönetici Olarak Davet Et'), findsNothing);
    expect(find.text('Görev Ver'), findsNothing);
    expect(find.text('Kişi zaten site yöneticisi; görev gerekmez.'), findsOneWidget);
  });

  testWidgets('salt okur (kurul üyesi) "Roller" bölümünü görmez', (t) async {
    final auth = PeopleFakeAuth.seeded();
    await _open(t, auth, 2, canWrite: false);
    expect(find.text('Roller'), findsNothing);
    expect(find.text('Görev Ver'), findsNothing);
  });

  testWidgets('kapı yoksa geçiş bağlantısı dürüst uyarı verir', (t) async {
    final auth = PeopleFakeAuth.seeded();
    await _open(t, auth, 2);
    await _tapText(t, 'Geçiş Bağlantısı Oluştur');
    expect(find.textContaining('geçiş bağlantısı oluşturulabilecek kapı yok'), findsOneWidget);
  });

  for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (412, 915, 1.0)]) {
    testWidgets('taşma yok: ${w.toInt()}x${h.toInt()} yazı $s', (t) async {
      final auth = PeopleFakeAuth.seeded();
      auth.staffRoles.add(
        const StaffRoleRecord(userCode: 702, fullName: 'Mehmet Demir', email: 'mehmet@example.com', role: 'BOARD_MEMBER'),
      );
      await _open(t, auth, 2, width: w, height: h, scale: s);
      await scrollTo(t, find.text('Misafir ve kurye'));
      expect(t.takeException(), isNull);
    });
  }
}
