// FAZ 5 / A2-G3: Süper Kullanıcı / Site Yöneticisi listeleri (ManagedUsersView, ManagedUserCard).
//
// AGENTS.md kural 6: taşma YOK (320x640 x2,0 ve 360x640 x1,5; açık + koyu tema). Davranış: etkinleştirme
// anahtarı, "Düzenle"/"Sil" düğmeleri GÖRÜNÜR, yenile (Icons.refresh) ve sayfalama değişmedi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/managed_users_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/managed_user_card.dart';

import 'list_fixtures.dart';

ManagedUsersView _view({
  List<String>? log,
  UserRole role = UserRole.siteManager,
  bool loading = false,
  List<ManagedUserAccount>? users,
  ManagedUserPage? page,
  Set<int> busy = const <int>{},
  bool withDelete = true,
}) {
  final l = log ?? <String>[];
  final list = users ?? fxUsers();
  return ManagedUsersView(
    role: role,
    session: fxSession,
    pageData: loading ? null : (page ?? fxUserPage(list, total: 25)),
    users: loading ? const <ManagedUserAccount>[] : list,
    loading: loading,
    busyActivationUsers: busy,
    onRefresh: () => l.add('refresh'),
    onLoadPage: (p) => l.add('page:$p'),
    onOpenAddDialog: () => l.add('add'),
    onToggleActivation: (u, v) => l.add('toggle:${u.id}:$v'),
    onShowUserDetails: (u) => l.add('details:${u.id}'),
    onDeleteUser: withDelete ? (u) => l.add('delete:${u.id}') : null,
  );
}

void main() {
  group('ManagedUsersView taşma matrisi', () {
    listMatrix('tam liste: başlık, kartlar, sayfalama', (
      t,
      w,
      h,
      scale,
      dark,
    ) async {
      await pumpList(t, _view(), width: w, height: h, scale: scale, dark: dark);
      for (final text in const <String>[
        'Site Yöneticileri',
        'Yeni Site Yöneticisi',
        'Site Yöneticileri (25)',
        'Ayşe Yılmaz',
        'Mehmet Demir Çok Uzun Bir Soyadı Olan Kullanıcı',
        'Selin Aydın',
        'Site Yoneticisi',
        'Daire Kullanicisi',
        'Bireysel Kullanici',
        'Super User',
        'Sayfa 1 / 2 | Toplam 25',
      ]) {
        expect(find.text(text), findsWidgets, reason: 'metin korunmalı: $text');
      }
      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byType(AppCard),
        ),
        findsNothing,
        reason: 'kart-içinde-kart yok',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    listMatrix('kartlar açılır: bilgi çipleri ve görünür eylemler', (
      t,
      w,
      h,
      scale,
      dark,
    ) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(find.text('Düzenle'), findsNothing);
      await tapText(t, 'Ayşe Yılmaz');
      for (final text in const <String>[
        'Kullanıcı ID: 10',
        'E-posta: kullanici10@e2e.local',
        'Telefon: +90 212 000 00 00',
        'Kayıt: 01.10.2026 16:50',
        'Düzenle',
        'Sil',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      // Uzun adlı / uzun e-postalı pasif kullanıcı da taşmaz.
      await tapText(t, 'Mehmet Demir Çok Uzun Bir Soyadı Olan Kullanıcı');
      expect(
        find.text(
          'E-posta: mehmet.demir.cok.uzun.bir.eposta.adresi@ornek-alan.com',
        ),
        findsOneWidget,
      );
      // Kendi hesabı: silinemez ("Sil" yok), anahtar kapalı.
      await tapText(t, 'Süper Yönetici');
      expect(find.text('Sil'), findsNWidgets(2));
      await tapText(t, 'Düzenle');
      expect(log, <String>['details:10']);
    });

    listMatrix('iskelet ve boş durum', (t, w, h, scale, dark) async {
      await pumpList(
        t,
        _view(loading: true),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(find.byType(ShimmerScope), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Site Yöneticileri'), findsWidgets);

      await pumpList(
        t,
        _view(users: const <ManagedUserAccount>[]),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(
        find.text('Kayıtlı site yöneticileri bulunamadı.'),
        findsOneWidget,
      );
      expect(find.byType(ShimmerScope), findsNothing);
    });
  });

  group('ManagedUsersView davranış', () {
    testWidgets('süper kullanıcı rolü: başlık ve "Yeni ..." düğmesi', (
      t,
    ) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log, role: UserRole.superUser),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      expect(find.text('Süper Kullanıcılar'), findsOneWidget);
      expect(find.text('Süper Kullanıcılar (25)'), findsOneWidget);
      await tapText(t, 'Yeni Süper Kullanıcı');
      expect(log, <String>['add']);
    });

    testWidgets(
      'anahtar: etkinleştirme geri çağrısı; meşgulken anahtar yerine spinner',
      (t) async {
        final log = <String>[];
        await pumpList(
          t,
          _view(log: log),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        expect(find.byType(Switch), findsNWidgets(5));
        await tapFinder(t, find.byType(Switch).first);
        expect(log, <String>['toggle:10:false']);
        // Kendi hesabının anahtarı devre dışı.
        expect(t.widget<Switch>(find.byType(Switch).last).onChanged, isNull);

        await pumpList(
          t,
          _view(busy: const <int>{10}),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        expect(find.byType(Switch), findsNWidgets(4));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets(
      'eylem düğmeleri: Düzenle ve Sil geri çağrıları; silme geri çağrısı yoksa Sil yok',
      (t) async {
        final log = <String>[];
        await pumpList(
          t,
          _view(log: log),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        await tapText(t, 'Ayşe Yılmaz');
        await tapText(t, 'Düzenle');
        await tapText(t, 'Sil');
        expect(log, <String>['details:10', 'delete:10']);

        await pumpList(
          t,
          _view(withDelete: false),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        await tapText(t, 'Ayşe Yılmaz');
        expect(find.text('Düzenle'), findsOneWidget);
        expect(find.text('Sil'), findsNothing);
      },
    );

    testWidgets(
      'erişilebilirlik: kullanıcı kartı açık/kapalı durumunu bildirir',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpList(
          t,
          _view(),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        final card = find.byType(ManagedUserCard).first;
        expect(
          t.getSemantics(card),
          isSemantics(hasExpandedState: true, isExpanded: false),
        );
        await tapText(t, 'Ayşe Yılmaz');
        expect(
          t.getSemantics(card),
          isSemantics(hasExpandedState: true, isExpanded: true),
        );
        handle.dispose();
      },
    );

    testWidgets('yenile (Icons.refresh): geri çağrı; yüklenirken devre dışı', (
      t,
    ) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      await tapFinder(t, find.byIcon(Icons.refresh));
      expect(log, <String>['refresh']);
      await pumpList(
        t,
        _view(loading: true),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      expect(
        t
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNull,
      );
    });

    testWidgets('sayfalama: ipuçları, 44 dp, sınırlarda devre dışı', (t) async {
      final log = <String>[];
      final users = fxUsers();
      await pumpList(
        t,
        _view(
          log: log,
          users: users,
          page: fxUserPage(users, total: 40, page: 2),
        ),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      expect(find.text('Sayfa 2 / 3 | Toplam 40'), findsOneWidget);
      for (final tip in const <String>['Önceki sayfa', 'Sonraki sayfa']) {
        final size = t.getSize(find.byTooltip(tip));
        expect(size.shortestSide, greaterThanOrEqualTo(44), reason: tip);
      }
      await tapFinder(t, find.byTooltip('Önceki sayfa'));
      await tapFinder(t, find.byTooltip('Sonraki sayfa'));
      expect(log, <String>['page:1', 'page:3']);
    });

    testWidgets('rol tonu: avatar rol tonunda; pasif hesap nötr tonlu kart', (
      t,
    ) async {
      await pumpList(
        t,
        _view(),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      final avatars = t
          .widgetList<InitialAvatar>(find.byType(InitialAvatar))
          .toList();
      expect(avatars.map((a) => a.tone).toList(), <AppTone>[
        AppTone.success, // site yöneticisi
        AppTone.success,
        AppTone.violet, // daire kullanıcısı
        AppTone.violet, // bireysel
        AppTone.primary, // süper kullanıcı
      ]);
      final cards = t.widgetList<AppCard>(find.byType(AppCard)).toList();
      // Başlık kartı + 5 kullanıcı kartı; yalnız ikincisi (pasif) nötr tonlu.
      final userCards = cards.where((c) => c.onTap != null).toList();
      expect(userCards.map((c) => c.tone).toList(), <AppTone?>[
        null,
        AppTone.neutral,
        null,
        null,
        null,
      ]);
    });
  });

  group('ManagedUsersView kontrast', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets('"Sil" metni danger ink >= 4,5:1 (${dark ? 'koyu' : 'açık'})', (
        t,
      ) async {
        await pumpList(
          t,
          _view(),
          width: 360,
          height: 800,
          scale: 1,
          dark: dark,
        );
        final p = dark ? AppPalette.dark : AppPalette.light;
        await tapText(t, 'Ayşe Yılmaz');
        final del = t.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('Sil'),
            matching: find.byType(OutlinedButton),
          ),
        );
        final fg = del.style!.foregroundColor!.resolve(<WidgetState>{})!;
        expect(fg, AppTone.danger.ink(p));
        expect(contrastRatio(fg, p.surface), greaterThanOrEqualTo(4.5));
        // Pasif hesap = nötr tonlu kart: açılan "Kayıt" satırı soluk tonlu zeminde de >= 4,5:1.
        await tapText(t, 'Mehmet Demir Çok Uzun Bir Soyadı Olan Kullanıcı');
        final neutralBg = Color.alphaBlend(AppTone.neutral.tint(p), p.surface);
        final dateStyle = t
            .widget<Text>(find.text('Kayıt: 01.10.2026 16:50').last)
            .style!;
        expect(
          contrastRatio(dateStyle.color!, neutralBg),
          greaterThanOrEqualTo(4.5),
        );
        // Alt metinler (rol etiketi) palet ikincil metni: >= 4,5:1.
        final role = t.widget<Text>(find.text('Site Yoneticisi').first);
        final roleColor =
            role.style?.color ??
            Theme.of(
              t.element(find.text('Site Yoneticisi').first),
            ).textTheme.bodyMedium!.color!;
        expect(contrastRatio(roleColor, p.surface), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('ManagedUsersView geniş ekran ve yatay', () {
    testWidgets(
      '820x640 ve 900x400 (yatay), 1,0x/1,5x, açık/koyu: taşma yok; başlık satırı yan yana',
      (t) async {
        for (final (w, h) in const <(double, double)>[(820, 640), (900, 400)]) {
          for (final scale in const <double>[1.0, 1.5]) {
            for (final dark in const <bool>[false, true]) {
              await pumpList(
                t,
                _view(),
                width: w,
                height: h,
                scale: scale,
                dark: dark,
              );
              final title = t.getRect(find.text('Site Yöneticileri').first);
              final button = t.getRect(find.text('Yeni Site Yöneticisi'));
              expect(button.left, greaterThanOrEqualTo(title.right));
              await tapText(t, 'Ayşe Yılmaz');
              expect(find.text('Düzenle'), findsOneWidget);
              expect(t.takeException(), isNull);
            }
          }
        }
      },
    );
  });
}
