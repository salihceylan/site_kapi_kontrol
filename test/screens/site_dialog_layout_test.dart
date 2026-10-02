// FAZ 5 / A2-G5: SiteDialog taşma testi (AGENTS.md kural 6).
//
// Yeni site: yönetici listesi yüklenirken ("Yöneticiler yükleniyor...") ve yüklendikten sonra.
// Düzenleme: blok daire sayıları okunamayınca InlineNotice + "Tekrar Dene".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_dialog.dart';

import 'dialog_layout_harness.dart';

class _FakeAuth extends AuthService {
  _FakeAuth({this.managersGate, this.structureError})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  /// Verilirse yönetici listesi bu tamamlanana dek "yükleniyor" kalır.
  final Completer<void>? managersGate;
  final String? structureError;

  @override
  Future<ManagedUserPage> listManagedUsers({
    UserRole? role,
    UserRole? excludeRole,
    required int page,
    int pageSize = 10,
    String? search,
  }) async {
    await managersGate?.future;
    return ManagedUserPage(
      users: <ManagedUserAccount>[
        ManagedUserAccount(
          id: 9,
          fullName: 'Ayşe Yılmaz Uzun Soyadlı',
          email: 'ayse.yilmaz.uzun.eposta@ornek-alan-adi.example.com',
          loginName: 'ayse',
          role: UserRole.siteManager,
          isActive: true,
          phoneNumber: null,
          createdAt: null,
        ),
      ],
      total: 1,
      page: 1,
      pageSize: 100,
    );
  }

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({
    required int siteCode,
  }) async => (null, structureError);
}

SiteRecord _site({bool withCounts = false}) => SiteRecord.fromJson({
  'id': 101,
  'name': 'Güneş Sitesi',
  'city': 'İstanbul',
  'district': 'Kadıköy',
  'block_count': 3,
  'apartment_count': 54,
  'door_count': 2,
  'approval_status': 'approved',
  'block_apartment_counts': withCounts ? [24, 30, 12] : <int>[],
});

void main() {
  layoutMatrix('SiteDialog (yeni site, yönetici listesi yükleniyor)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final gate = Completer<void>();
    await openDialogAt(
      t,
      (context) =>
          SiteDialog.show(context, authService: _FakeAuth(managersGate: gate)),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('Yeni Site Ekle'), findsOneWidget);
    await scrollTo(t, find.text('Yöneticiler yükleniyor...'));
    expect(find.text('Yöneticiler yükleniyor...'), findsOneWidget);

    gate.complete();
    await settleFor(t);
    await scrollTo(t, find.text('Yönetici Atanmadı'));
    await scrollTo(t, find.text('Yönetici Seç / Değiştir'));
    expect(find.text('Kaydet'), findsOneWidget);
  });

  layoutMatrix('SiteDialog (yeni site, çok bloklu liste + doğrulama)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => SiteDialog.show(context, authService: _FakeAuth()),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t);

    await t.enterText(find.widgetWithText(TextFormField, 'Blok Sayısı'), '4');
    await settleFor(t);
    expect(find.text('D Blok'), findsOneWidget);
    expect(find.text('Toplam: 40 Daire'), findsOneWidget);

    await scrollTo(t, find.text('Kaydet'));
    await t.tap(find.text('Kaydet'));
    await settleFor(t);
    expect(find.text('Site adı en az 2 karakter olmalı.'), findsOneWidget);
  });

  layoutMatrix(
    'SiteDialog (düzenleme, daire sayıları okunamadı: InlineNotice)',
    (t, width, height, scale, dark) async {
      await openDialogAt(
        t,
        (context) => SiteDialog.show(
          context,
          authService: _FakeAuth(structureError: 'Sunucuya baglanilamadi.'),
          site: _site(),
        ),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      await settleFor(t);

      expect(find.text('Site Düzenle'), findsOneWidget);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.textContaining('Sunucuya baglanilamadi.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      await scrollTo(t, find.text('Tekrar Dene'));
      // "Güncelle" okunamayan sayılarla kapalıdır.
      await scrollTo(t, find.text('Güncelle'));
      expect(
        t
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Güncelle'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  layoutMatrix('SiteDialog (düzenleme, kayıtlı daire sayıları)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => SiteDialog.show(
        context,
        authService: _FakeAuth(),
        site: _site(withCounts: true),
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t);

    expect(find.text('Toplam: 66 Daire'), findsOneWidget);
    await scrollTo(t, find.text('C Blok'));
    await scrollTo(t, find.text('Güncelle'));
  });
}
