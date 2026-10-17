// Kişi kartındaki "Roller" bölümü (PersonRolesPanel): tanıtımdaki beş rolün hepsi kartta; mevcut roller
// rozetle görünür; ek rol ver / kaldır, yönetici daveti, daireye bağlama ve geçiş bağlantısı kartın içinden;
// hesapsız / daire hesabı / zaten yönetici kişide ek rol düğmesi yok, nedeni yazılır; salt okur bölümü görmez;
// dar ekranda büyük yazıda taşmaz.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
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
  testWidgets('beş rolün hepsi kartta; rolsüz kişide açıklama; hesaplı kişiye "Rol Ver" -> onay -> atanır', (t) async {
    final auth = PeopleFakeAuth.seeded();
    await _open(t, auth, 2); // Mehmet Demir: hesaplı kiracı (user_code 702)

    for (final title in const <String>[
      'Roller',
      'Site yöneticisi',
      'Yönetim kurulu ve denetçi',
      'Görevli',
      'Daire sakini',
      'Misafir ve kurye',
    ]) {
      await scrollTo(t, find.text(title).first);
      expect(find.text(title), findsWidgets, reason: title);
    }
    expect(find.text('Yönetici Olarak Davet Et'), findsOneWidget);
    expect(find.text('Rol Ver'), findsNWidgets(2));
    expect(find.text('Geçiş Bağlantısı Oluştur'), findsOneWidget);

    await scrollTo(t, find.text('Rol Ver').first);
    await t.tap(find.text('Rol Ver').first);
    await settleFor(t);
    await t.tap(find.text('Rol Ver').last); // onay penceresindeki düğme (en üstte)
    await settleFor(t);

    expect(auth.staffAssignCalls.single, (email: 'mehmet@example.com', role: 'BOARD_MEMBER'));
    await scrollTo(t, find.text('Rolü Kaldır'));
    expect(find.text('Rolü Kaldır'), findsOneWidget);
    expect(find.text('Önce kişinin mevcut rolünü kaldırın.'), findsOneWidget); // Görevli satırı
    expect(t.takeException(), isNull);
  });

  testWidgets('rolü olan kişide rozet + "Rolü Kaldır" -> onay -> kaldırılır', (t) async {
    final auth = PeopleFakeAuth.seeded();
    auth.staffRoles.add(
      const StaffRoleRecord(userCode: 702, fullName: 'Mehmet Demir', email: 'mehmet@example.com', role: 'STAFF'),
    );
    await _open(t, auth, 2);
    expect(find.text('Görevli'), findsWidgets); // rozet + satır başlığı
    await _tapText(t, 'Rolü Kaldır');
    await t.tap(find.text('Rolü Kaldır').last);
    await settleFor(t);
    expect(auth.staffRemoveCalls, <int>[702]);
  });

  testWidgets('hesapsız kişide ek rol düğmesi yok, nedeni yazılır; yönetici daveti ve daireye bağlama var', (t) async {
    final auth = PeopleFakeAuth.seeded();
    await _open(t, auth, 1); // Ayşe Yılmaz: hesapsız malik
    expect(find.text('Rol Ver'), findsNothing);
    expect(
      find.textContaining('Bu rol için kişinin uygulamada kendi hesabı olmalı'),
      findsNWidgets(2),
    );
    expect(find.text('Daire sakini'), findsWidgets); // rozet (bağlı daire var) + satır
    expect(find.text('Başka Bir Daireye Bağla'), findsOneWidget);

    await _tapText(t, 'Yönetici Olarak Davet Et');
    await t.tap(find.text('Davet Gönder'));
    await settleFor(t);
    expect(auth.managerInviteCalls, <String>['ayse@example.com']);
  });

  testWidgets('zaten yönetici olan kişi: rozet, davet ve ek rol düğmesi yok', (t) async {
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
    expect(find.text('Rol Ver'), findsNothing);
    expect(find.text('Kişi zaten site yöneticisi; bu rol gerekmez.'), findsNWidgets(2));
  });

  testWidgets('salt okur (kurul üyesi) "Roller" bölümünü görmez', (t) async {
    final auth = PeopleFakeAuth.seeded();
    await _open(t, auth, 2, canWrite: false);
    expect(find.text('Roller'), findsNothing);
    expect(find.text('Rol Ver'), findsNothing);
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
