// Yönetim kadrosu (058): Kişiler ekranında yazma yetkisinde "Yönetim Kurulu ve Görevliler" düğmesi "Kadro" sekmesini açar
// (eski Ek Roller penceresinin yerine). Sekme yönetici, kurul/görevliler, eski ek roller ve faydalı telefonları gösterir;
// kurul (salt okur) düğmeyi görmez. Eski ek rol atama penceresinin hata metinleri [StaffRoleDialog.messageFor] ile korunur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/dialogs/staff_role_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

PeopleFakeAuth _auth() {
  final auth = PeopleFakeAuth.seeded();
  auth.staffRoles.add(
    StaffRoleRecord(
      userCode: 41,
      fullName: 'Selin Arda',
      email: 'selin@example.com',
      role: 'BOARD_MEMBER',
      createdAt: DateTime(2026, 10, 1),
    ),
  );
  auth.teamDuties[2] = const TeamDuty(
    personId: 2,
    fullName: 'Mehmet Demir',
    duty: 'doorman',
    showInDirectory: true,
    access: 'no_account',
  );
  auth.teamContacts.add(const DirectoryContact(id: 1, label: 'Su arıza', phone: '186', category: 'utility'));
  return auth;
}

Future<void> _pump(
  WidgetTester t,
  PeopleFakeAuth auth, {
  bool manage = true,
  List<PeopleSite> readOnly = const <PeopleSite>[],
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool dark = false,
}) async {
  await pumpList(
    t,
    PeopleView(authService: auth, manageSites: manage, readOnlySites: readOnly),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
}

const Key _openButton = ValueKey<String>('people_staff_roles');

void main() {
  group('Kişiler ekranı: Kadro sekmesi', () {
    testWidgets('yazma yetkisinde düğme Kadro sekmesini açar: yönetici, görevli, eski ek rol, faydalı telefon', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      expect(find.byKey(_openButton), findsOneWidget);
      expect(find.text('Yönetim Kurulu ve Görevliler'), findsOneWidget);

      await tapFinder(t, find.byKey(_openButton));
      await settleFor(t);

      expect(find.text('Yönetici Kişi'), findsOneWidget);
      expect(find.text('Mehmet Demir'), findsOneWidget);
      expect(find.textContaining('Kişinin uygulama hesabı yok'), findsOneWidget);
      expect(find.text('Eski ek roller'), findsOneWidget);
      expect(find.text('Selin Arda'), findsOneWidget);
      expect(find.text('Su arıza'), findsOneWidget);
      expect(find.textContaining('Rehber modülü kapalı'), findsOneWidget);
      expect(find.text('Telefon Ekle'), findsNothing, reason: 'modül kapalıyken telefon eklenmez');
    });

    testWidgets('boş kadroda "Görev vermezseniz işler sizde kalır" yazar', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await tapFinder(t, find.byKey(_openButton));
      await settleFor(t);
      expect(find.textContaining('Görev vermezseniz işler sizde kalır'), findsOneWidget);
    });

    testWidgets('rehber modülü açıkken "Telefon Ekle" görünür', (t) async {
      final auth = _auth()..teamDirectoryEnabled = true;
      await _pump(t, auth);
      await tapFinder(t, find.byKey(_openButton));
      await settleFor(t);
      expect(find.text('Telefon Ekle'), findsOneWidget);
      expect(find.textContaining('Rehber modülü kapalı'), findsNothing);
    });

    testWidgets('salt okunur (kurul) sitede düğme YOK', (t) async {
      final auth = _auth();
      await _pump(
        t,
        auth,
        manage: false,
        readOnly: const <PeopleSite>[PeopleSite(code: 12, name: 'Mavi Park')],
      );
      expect(find.byKey(_openButton), findsNothing);
      expect(find.text('Yönetim Kurulu ve Görevliler'), findsNothing);
    });

    test('eski atama penceresi hata metinleri: hesap yok / etkin değil / diğer kodlar', () {
      expect(
        StaffRoleDialog.messageFor(ApiException('x', code: 'USER_NOT_FOUND')),
        contains('Kişinin önce uygulamaya kayıt olması gerekir'),
      );
      expect(
        StaffRoleDialog.messageFor(ApiException('x', code: 'USER_NOT_ACTIVE')),
        contains('tamamlaması gerekir'),
      );
      expect(
        StaffRoleDialog.messageFor(ApiException('Bu kişi zaten site yöneticisi.', code: 'ALREADY_SITE_MANAGER')),
        'Bu kişi zaten site yöneticisi.',
      );
    });

    testWidgets('taşma matrisi: sekme 320x640@2,0 koyu, 360x640@1,5 açık, 640x360@2,0', (t) async {
      for (final cell in const <(double, double, double, bool)>[
        (320, 640, 2.0, true),
        (360, 640, 1.5, false),
        (640, 360, 2.0, true),
        (800, 1280, 1.0, false),
      ]) {
        final auth = _auth()..teamDirectoryEnabled = true;
        await _pump(t, auth, width: cell.$1, height: cell.$2, scale: cell.$3, dark: cell.$4);
        await tapFinder(t, find.byKey(_openButton));
        await settleFor(t);
        expect(find.text('Yönetici Kişi'), findsOneWidget);
        expect(t.takeException(), isNull, reason: '${cell.$1}x${cell.$2}@${cell.$3}');
        await t.pumpWidget(const SizedBox());
      }
    });
  });
}
