// Saha denemesi F2.15: Yönetim Kurulu / Görevli rol atama ekranı Modüller'e gömülüydü, Kişiler ekranından
// bulunamıyordu. Kişiler ekranında (yalnız yazma yetkisinde) "Yönetim Kurulu ve Görevliler" düğmesi, Modüller
// ile AYNI bileşeni ([StaffRolesSection]) bir pencerede açar; kayıtlı olmayan e-posta düz Türkçe, ne yapılacağını
// söyleyen iletiyle reddedilir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/dialogs/staff_role_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/staff_role_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/staff_roles_section.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

class _RolesAuth extends PeopleFakeAuth {
  _RolesAuth() : super();

  final List<StaffRoleRecord> roles = <StaffRoleRecord>[
    StaffRoleRecord(
      userCode: 41,
      fullName: 'Selin Arda',
      email: 'selin@example.com',
      role: 'BOARD_MEMBER',
      createdAt: DateTime(2026, 10, 1),
    ),
  ];
  Object? assignError;
  final List<({int site, String email, String role})> assignCalls = <({int site, String email, String role})>[];
  final List<int> listCalls = <int>[];

  @override
  Future<List<StaffRoleRecord>> listStaffRoles(int siteCode) async {
    listCalls.add(siteCode);
    return List<StaffRoleRecord>.of(roles);
  }

  @override
  Future<StaffRoleRecord> assignStaffRole(int siteCode, String email, String role) async {
    assignCalls.add((site: siteCode, email: email, role: role));
    final error = assignError;
    if (error != null) throw error;
    final record = StaffRoleRecord(
      userCode: 50 + assignCalls.length,
      fullName: 'Yeni Görevli',
      email: email,
      role: role,
      createdAt: DateTime(2026, 10, 2),
    );
    roles.add(record);
    return record;
  }
}

Future<void> _pump(
  WidgetTester t,
  _RolesAuth auth, {
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
  group('Kişiler ekranı: Yönetim Kurulu ve Görevliler', () {
    testWidgets('yazma yetkisinde düğme görünür ve pencere açıklama + mevcut rolleri gösterir', (t) async {
      final auth = _RolesAuth();
      await _pump(t, auth);
      expect(find.byKey(_openButton), findsOneWidget);
      expect(find.text('Yönetim Kurulu ve Görevliler'), findsOneWidget);

      await tapFinder(t, find.byKey(_openButton));
      await settleFor(t);

      expect(find.text(staffRolesIntro), findsOneWidget);
      expect(
        staffRolesIntro,
        'İsterseniz bir kişiye Yönetim Kurulu / Denetçi (yalnız görüntüler) ya da Görevli rolü verebilirsiniz. '
        'Rol vermezseniz bu işlerin hepsi sizde kalır.',
      );
      expect(find.byType(StaffRoleCard), findsOneWidget);
      expect(find.text('Selin Arda'), findsOneWidget);
      expect(find.text('Rol Ekle'), findsOneWidget);
      expect(auth.listCalls, <int>[11]);
    });

    testWidgets('salt okunur (kurul) sitede düğme YOK', (t) async {
      final auth = _RolesAuth();
      await _pump(
        t,
        auth,
        manage: false,
        readOnly: const <PeopleSite>[PeopleSite(code: 12, name: 'Mavi Park')],
      );
      expect(find.byKey(_openButton), findsNothing);
      expect(find.text('Yönetim Kurulu ve Görevliler'), findsNothing);
    });

    testWidgets('kayıtlı olmayan e-posta: düz Türkçe, ne yapılacağını söyleyen ileti; pencere açık kalır; sonra atama olur', (t) async {
      final auth = _RolesAuth()
        ..assignError = ApiException(
          'Bu e-posta ile kayıtlı hesap yok.',
          statusCode: 404,
          code: 'USER_NOT_FOUND',
        );
      await _pump(t, auth);
      await tapFinder(t, find.byKey(_openButton));
      await settleFor(t);
      await tapText(t, 'Rol Ekle');
      await settleFor(t);

      await t.enterText(find.widgetWithText(TextFormField, 'E-posta'), 'yok@example.com');
      await tapFinder(t, find.byType(DropdownButtonFormField<StaffRoleType>));
      await tapFinder(t, find.text('Görevli').last);
      await tapText(t, 'Ata');
      await settleFor(t);

      expect(find.text(StaffRoleDialog.messageFor(auth.assignError! as ApiException)), findsOneWidget);
      expect(
        find.textContaining('Kişinin önce uygulamaya kayıt olması gerekir'),
        findsOneWidget,
      );
      expect(find.text('Ek Rol Ata'), findsOneWidget, reason: 'pencere açık kalır');

      // Kişi kayıt olduktan sonra aynı pencereden tekrar denenir.
      auth.assignError = null;
      await tapText(t, 'Ata');
      await settleFor(t);
      expect(find.text('Ek rol atandı.'), findsOneWidget);
      expect(auth.assignCalls.last.role, 'STAFF');
      expect(find.byType(StaffRoleCard), findsNWidgets(2), reason: 'liste yenilendi');
    });

    test('hesap etkin değil ve diğer kodlar', () {
      expect(
        StaffRoleDialog.messageFor(ApiException('x', code: 'USER_NOT_ACTIVE')),
        contains('tamamlaması gerekir'),
      );
      expect(
        StaffRoleDialog.messageFor(ApiException('Bu kişi zaten site yöneticisi.', code: 'ALREADY_SITE_MANAGER')),
        'Bu kişi zaten site yöneticisi.',
      );
    });

    testWidgets('taşma matrisi: pencere 320x640@2,0 koyu, 360x640@1,5 açık, 640x360@2,0', (t) async {
      for (final cell in const <(double, double, double, bool)>[
        (320, 640, 2.0, true),
        (360, 640, 1.5, false),
        (640, 360, 2.0, true),
        (800, 1280, 1.0, false),
      ]) {
        final auth = _RolesAuth();
        await _pump(t, auth, width: cell.$1, height: cell.$2, scale: cell.$3, dark: cell.$4);
        await tapFinder(t, find.byKey(_openButton));
        await settleFor(t);
        expect(find.text(staffRolesIntro), findsOneWidget);
        expect(t.takeException(), isNull, reason: '${cell.$1}x${cell.$2}@${cell.$3}');
        await t.pumpWidget(const SizedBox());
      }
    });
  });
}
