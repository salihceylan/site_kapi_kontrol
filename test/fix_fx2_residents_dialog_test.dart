import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_residents_tree_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_residents_accordion_dialog.dart';

Map<String, dynamic> _member(
  int code,
  String name, {
  required bool isActive,
  bool? accountIsActive,
  String role = 'FAMILY_MEMBER',
}) =>
    {
      'user_code': code,
      'full_name': name,
      'email': 'u$code@example.com',
      'role': role,
      'is_active': isActive,
      'account_is_active': ?accountIsActive,
    };

Map<String, dynamic> _treeJson() => {
      'site': {'id': 101, 'name': 'Güneş Sitesi', 'total_blocks': 1, 'total_apartments': 1, 'total_residents': 3},
      'blocks': [
        {
          'id': 11,
          'block_name': 'A Blok',
          'sort_order': 1,
          'total_apartments': 1,
          'total_residents': 3,
          'apartments': [
            {
              'id': 501,
              'block_id': 11,
              'unit_label': 'Daire 1',
              'sort_order': 1,
              'total_residents': 3,
              'residents': [
                _member(1, 'Aktif Sakin', isActive: true, accountIsActive: true, role: 'APARTMENT_ADMIN'),
                _member(2, 'Üyeliği Pasif Sakin', isActive: false, accountIsActive: true),
                _member(3, 'Hesabı Pasif Sakin', isActive: false, accountIsActive: false),
              ],
            },
          ],
        },
      ],
    };

class _ResidentsAuth extends AuthService {
  _ResidentsAuth(this.json) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final Map<String, dynamic> json;
  final List<(int, bool)> toggles = [];

  @override
  Future<(SiteResidentsTreeData?, String?)> getSiteResidentsTree(int siteCode) async {
    return (SiteResidentsTreeData.fromJson(json), null);
  }

  @override
  Future<(bool, String?)> toggleApartmentMemberStatus({
    required int apartmentId,
    required int targetUserCode,
    required bool isActive,
  }) async {
    toggles.add((targetUserCode, isActive));
    return (true, 'Tamam');
  }
}

SiteRecord _site() => SiteRecord.fromJson({
      'id': 101,
      'name': 'Güneş Sitesi',
      'block_count': 1,
      'apartment_count': 1,
      'door_count': 1,
    });

void main() {
  test('SiteResidentMember: account_is_active okunur; alan yoksa true sayılır', () {
    expect(SiteResidentMember.fromJson({'user_code': 1, 'account_is_active': false}).accountIsActive, isFalse);
    expect(SiteResidentMember.fromJson({'user_code': 1, 'account_is_active': true}).accountIsActive, isTrue);
    expect(SiteResidentMember.fromJson({'user_code': 1}).accountIsActive, isTrue,
        reason: 'eski sunucu alanı göndermez');
    final inactiveMembership = SiteResidentMember.fromJson({
      'user_code': 2,
      'is_active': false,
      'account_is_active': true,
    });
    expect(inactiveMembership.isActive, isFalse);
    expect(inactiveMembership.accountIsActive, isTrue);
  });

  testWidgets('hesabı pasif sakinde rozet ve bilgi satırı gösterilir, üyelik işlemi sunulmaz (320 px taşmasız)', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final auth = _ResidentsAuth(_treeJson());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SiteResidentsAccordionDialog.show(context, site: _site(), authService: auth),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();

    expect(find.text('Hesap pasif (sistem yöneticisi)'), findsOneWidget);
    expect(find.text('İnaktif'), findsOneWidget, reason: 'yalnız üyeliği pasif olan sakin');
    expect(tester.takeException(), isNull);

    final menus = find.byType(PopupMenuButton<String>);
    expect(menus, findsNWidgets(3));

    // Hesabı pasif sakinin menüsü: işlem yerine bilgi
    await tester.tap(menus.at(2));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hesap sistem yöneticisi tarafından pasife alındı'), findsOneWidget);
    expect(find.text('Üyeliği Aktif Et'), findsNothing);
    expect(find.text('Üyeliği Pasife Al'), findsNothing);
    expect(find.text('Hesabı Aktif Et'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(5, 5)); // menüyü kapat
    await tester.pumpAndSettle();

    // Yalnız üyeliği pasif sakin: üyelik/kapı erişimi diliyle aktif etme
    await tester.tap(menus.at(1));
    await tester.pumpAndSettle();
    expect(find.text('Üyeliği Aktif Et'), findsOneWidget);
    expect(find.text('Hesabı Aktif Et'), findsNothing);
    await tester.tap(find.text('Üyeliği Aktif Et'));
    await tester.pumpAndSettle();
    expect(find.textContaining('daire üyeliğini ve kapı erişimini aktif etmek'), findsOneWidget);
    expect(find.textContaining('hesabını'), findsNothing);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Aktif Et'));
    await tester.pumpAndSettle();
    expect(auth.toggles, [(2, true)]);

    // Aktif sakin: pasife alma metni üyelik/kapı erişimi diliyle
    await tester.tap(menus.at(0));
    await tester.pumpAndSettle();
    expect(find.text('Üyeliği Pasife Al'), findsOneWidget);
    await tester.tap(find.text('Üyeliği Pasife Al'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kullanıcının hesabı etkilenmez'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
