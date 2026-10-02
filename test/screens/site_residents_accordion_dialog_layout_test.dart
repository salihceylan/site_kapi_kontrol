// FAZ 5 / A2-G5: SiteResidentsAccordionDialog taşma testi (AGENTS.md kural 6).
//
// `Dialog`: başlık şeridi sabit; sayılar, arama, süzgeç çipleri ve blok/daire/sakin akordiyonları tek
// kaydırma alanında akar. Onay pencereleri (AppDialog) ve kart menüsü de büyük yazıda taşmamalı.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_residents_tree_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_residents_accordion_dialog.dart';

import 'dialog_layout_harness.dart';

Map<String, dynamic> _member(
  int code,
  String name, {
  required bool isActive,
  bool accountIsActive = true,
  String role = 'FAMILY_MEMBER',
  String? phone,
}) => {
  'user_code': code,
  'full_name': name,
  'email': 'u$code@ornek-alan-adi.example.com',
  'phone_number': phone,
  'role': role,
  'is_active': isActive,
  'account_is_active': accountIsActive,
};

Map<String, dynamic> _tree({bool empty = false}) => {
  'site': {
    'id': 101,
    'name': 'Güneş Sitesi Uzun İsimli Konutları Yönetimi',
    'total_blocks': 2,
    'total_apartments': 3,
    'total_residents': 3,
  },
  'blocks': empty
      ? <Map<String, dynamic>>[]
      : [
          {
            'id': 11,
            'block_name': 'A Blok Uzun Adlı Blok İsmi',
            'sort_order': 1,
            'total_apartments': 2,
            'total_residents': 3,
            'apartments': [
              {
                'id': 501,
                'block_id': 11,
                'unit_label': 'Daire 1',
                'sort_order': 1,
                'total_residents': 3,
                'residents': [
                  _member(
                    1,
                    'Ayşe Yılmaz Uzun Soyadlı Kişi',
                    isActive: true,
                    role: 'APARTMENT_ADMIN',
                    phone: '+90 555 000 00 00',
                  ),
                  _member(2, 'Üyeliği Pasif Sakin', isActive: false),
                  _member(
                    3,
                    'Hesabı Pasif Sakin',
                    isActive: false,
                    accountIsActive: false,
                  ),
                ],
              },
              {
                'id': 502,
                'block_id': 11,
                'unit_label': 'Daire 2',
                'sort_order': 2,
                'total_residents': 0,
                'residents': <Map<String, dynamic>>[],
              },
            ],
          },
          {
            'id': 12,
            'block_name': 'B Blok',
            'sort_order': 2,
            'total_apartments': 1,
            'total_residents': 0,
            'apartments': [
              {
                'id': 601,
                'block_id': 12,
                'unit_label': 'Daire 1',
                'sort_order': 1,
                'total_residents': 0,
                'residents': <Map<String, dynamic>>[],
              },
            ],
          },
        ],
};

class _FakeAuth extends AuthService {
  _FakeAuth({this.error, this.empty = false})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? error;
  final bool empty;
  final List<(int, bool)> toggles = [];
  final List<int> deleted = [];

  @override
  Future<(SiteResidentsTreeData?, String?)> getSiteResidentsTree(
    int siteCode,
  ) async {
    if (error != null) return (null, error);
    return (SiteResidentsTreeData.fromJson(_tree(empty: empty)), null);
  }

  @override
  Future<(bool, String?)> toggleApartmentMemberStatus({
    required int apartmentId,
    required int targetUserCode,
    required bool isActive,
  }) async {
    toggles.add((targetUserCode, isActive));
    return (true, 'Durum güncellendi.');
  }

  @override
  Future<(bool, String?)> deleteApartmentMember({
    required int apartmentId,
    required int targetUserCode,
  }) async {
    deleted.add(targetUserCode);
    return (true, 'Sakin silindi.');
  }
}

SiteRecord _site() => SiteRecord.fromJson({
  'id': 101,
  'name': 'Güneş Sitesi Uzun İsimli Konutları Yönetimi',
  'block_count': 2,
  'apartment_count': 3,
  'door_count': 1,
});

Future<void> _open(
  WidgetTester t,
  _FakeAuth auth, {
  required double width,
  required double height,
  required double scale,
  required bool dark,
}) async {
  await openDialogAt(
    t,
    (context) => SiteResidentsAccordionDialog.show(
      context,
      site: _site(),
      authService: auth,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
}

void main() {
  layoutMatrix('SiteResidentsAccordionDialog (bloklar, daireler, sakinler)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await _open(
      t,
      _FakeAuth(),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.byTooltip('Kapat'), findsOneWidget);
    expect(find.byTooltip('Yenile'), findsOneWidget);
    expect(find.text('2 Blok'), findsOneWidget);
    expect(find.text('Tümü'), findsOneWidget);

    // Sakin kartlarına ve en alttaki (boş) daireye kadar kaydır: hiçbir kart taşmaz.
    await scrollIntoBuilt(
      t,
      find.text('Hesabı Pasif Sakin'),
      find.byType(CustomScrollView),
    );
    expect(find.text('Hesap pasif (sistem yöneticisi)'), findsOneWidget);
    await scrollIntoBuilt(
      t,
      find.text('B Blok'),
      find.byType(CustomScrollView),
    );
    expect(find.byType(AppCard), findsAtLeastNWidgets(1));
  });

  layoutMatrix('SiteResidentsAccordionDialog (kart menüsü + üyelik onayı)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final auth = _FakeAuth();
    await _open(
      t,
      auth,
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    // İlk sakinin menüsü: tüm öğeler büyük yazıda taşmadan açılır.
    await scrollIntoBuilt(
      t,
      find.byType(PopupMenuButton<String>),
      find.byType(CustomScrollView),
    );
    await t.tap(find.byType(PopupMenuButton<String>).first);
    await settleFor(t);
    expect(find.text('Üyeliği Pasife Al'), findsOneWidget);
    expect(find.text('Daireden Sil'), findsOneWidget);

    // Üyelik pasife alma onay penceresi (AppDialog) açılır ve onaylanır.
    await t.tap(find.text('Üyeliği Pasife Al'));
    await settleFor(t);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.textContaining('Kullanıcının hesabı etkilenmez'),
      findsOneWidget,
    );
    await scrollTo(t, find.widgetWithText(ElevatedButton, 'Pasife Al'));
    await t.tap(find.widgetWithText(ElevatedButton, 'Pasife Al'));
    await settleFor(t, 800);
    expect(auth.toggles, [(1, false)]);
  });

  layoutMatrix('SiteResidentsAccordionDialog (silme onayı: tehlike tonu)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final auth = _FakeAuth();
    await _open(
      t,
      auth,
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    await scrollIntoBuilt(
      t,
      find.byType(PopupMenuButton<String>),
      find.byType(CustomScrollView),
    );
    await t.tap(find.byType(PopupMenuButton<String>).first);
    await settleFor(t);
    await t.tap(find.text('Daireden Sil'));
    await settleFor(t);
    expect(find.text('Sakini Daireden Sil'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await scrollTo(t, find.widgetWithText(ElevatedButton, 'Daireden Sil'));
  });

  layoutMatrix('SiteResidentsAccordionDialog (yüklenemedi: InlineNotice)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await _open(
      t,
      _FakeAuth(
        error:
            'Sakin listesi şu an alınamadı; lütfen bağlantınızı kontrol edip yeniden deneyin.',
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(InlineNotice), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
    await scrollTo(t, find.text('Tekrar Dene'));
  });

  layoutMatrix('SiteResidentsAccordionDialog (blok yok: EmptyState)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await _open(
      t,
      _FakeAuth(empty: true),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    await scrollIntoBuilt(
      t,
      find.byType(EmptyState),
      find.byType(CustomScrollView),
    );
    expect(
      find.text('Bu sitede henüz tanımlı blok veya daire kaydı bulunmuyor.'),
      findsOneWidget,
    );
  });
}
