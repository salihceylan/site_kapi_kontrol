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
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_dialog.dart';

import '../design/harness.dart' show recordHaptics;
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
  // --- Görsel sözleşme (cilalı safir): iskelet, R8 açılır liste, ikon rozetleri, haptik ---

  testWidgets(
    'SiteDialog: yönetici listesi yüklenirken iskelet (spinner yok); yüklenince iskelet kalkar',
    (t) async {
      final gate = Completer<void>();
      await openDialogAt(
        t,
        (context) =>
            SiteDialog.show(context, authService: _FakeAuth(managersGate: gate)),
        width: 400,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      expect(find.byType(SkeletonBox), findsAtLeastNWidgets(1));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Yöneticiler yükleniyor...'), findsOneWidget);

      gate.complete();
      await settleFor(t);
      expect(find.byType(SkeletonBox), findsNothing);
      expect(find.text('Yönetici Atanmadı'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'SiteDialog: il/ilçe listeleri R8 (yuvarlak köşe, yüzey rengi, 320 dp menü, yuvarlak ok)',
    (t) async {
      await openDialogAt(
        t,
        (context) => SiteDialog.show(context, authService: _FakeAuth()),
        width: 400,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);

      final dropdowns = t
          .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .toList();
      expect(dropdowns, hasLength(2));
      for (final d in dropdowns) {
        expect(d.borderRadius, BorderRadius.circular(AppRadius.md));
        expect(d.dropdownColor, AppPalette.light.surface);
        expect(d.menuMaxHeight, 320);
        expect(
          (d.icon! as Icon).icon,
          Icons.keyboard_arrow_down_rounded,
        );
      }
    },
  );

  testWidgets(
    'SiteDialog: başlık + bölüm başlıkları cilalı ikon rozetidir; blok satırı hap + alan',
    (t) async {
      await openDialogAt(
        t,
        (context) => SiteDialog.show(context, authService: _FakeAuth()),
        width: 400,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);

      // Diyalog başlığı + "Blok Daireleri" + "Site Yöneticisi".
      expect(find.byType(IconOrb), findsAtLeastNWidgets(3));
      expect(find.text('Blok Daireleri'), findsOneWidget);
      expect(find.text('Site Yöneticisi'), findsOneWidget);
      expect(find.text('A Blok'), findsOneWidget);
      expect(find.text('Toplam: 10 Daire'), findsOneWidget);
      // Eylemler korunur: tonlu "seç / değiştir" hâlâ OutlinedButton'dır (düğme tipi değişmedi).
      expect(
        find.ancestor(
          of: find.text('Yönetici Seç / Değiştir'),
          matching: find.bySubtype<OutlinedButton>(),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SiteDialog: geçerli formda Kaydet hafif haptik verir ve sonucu döndürür',
    (t) async {
      final haptics = recordHaptics(t);
      SiteFormResult? result;
      await openDialogAt(
        t,
        (context) async {
          result = await SiteDialog.show(context, authService: _FakeAuth());
        },
        width: 400,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);

      // Geçersiz form: haptik YOK, diyalog açık kalır.
      await scrollTo(t, find.text('Kaydet'));
      await t.tap(find.text('Kaydet'));
      await settleFor(t);
      expect(haptics, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);

      await t.enterText(
        find.widgetWithText(TextFormField, 'Site Adı'),
        'Güneş Sitesi',
      );
      await scrollTo(t, find.text('Kaydet'));
      await t.tap(find.text('Kaydet'));
      await settleFor(t);

      expect(haptics, contains('HapticFeedbackType.lightImpact'));
      expect(result?.name, 'Güneş Sitesi');
      expect(result?.blockApartmentCounts, [10]);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
