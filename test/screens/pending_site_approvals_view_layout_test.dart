// FAZ 5 / A2-G3: Site Onay Talepleri (PendingSiteApprovalsView, SiteApprovalRequestCard).
//
// AGENTS.md kural 6: taşma YOK (320x640 x2,0 ve 360x640 x1,5; açık + koyu tema). Davranış: Onayla /
// Reddet düğmeleri GÖRÜNÜR (menüye taşınmadı), meşgul kartta düğmeler yerine spinner, yenile ve
// sayfalama geri çağrıları değişmedi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/pending_site_approvals_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_approval_request_card.dart';

import 'list_fixtures.dart';

PendingSiteApprovalsView _view({
  List<String>? log,
  bool loading = false,
  List<SiteRecord>? sites,
  SitePage? page,
  Set<int> busy = const <int>{},
}) {
  final l = log ?? <String>[];
  final list = sites ?? fxSites();
  return PendingSiteApprovalsView(
    pageData: loading ? null : (page ?? fxSitePage(list, total: 25)),
    sites: loading ? const <SiteRecord>[] : list,
    busySiteApprovals: busy,
    isLoading: loading,
    onRefresh: () => l.add('refresh'),
    onLoadPage: (p) => l.add('page:$p'),
    onApprove: (id) => l.add('approve:$id'),
    onReject: (id) => l.add('reject:$id'),
  );
}

void main() {
  group('PendingSiteApprovalsView taşma matrisi', () {
    listMatrix('tam liste: başlık, kartlar, eylemler, sayfalama', (
      t,
      w,
      h,
      scale,
      dark,
    ) async {
      await pumpList(
        t,
        _view(busy: const <int>{5899864116}),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      for (final text in const <String>[
        'Site Onay Talepleri',
        'Bekleyen Siteler (25)',
        'Yeşilvadi Sitesi',
        'Onay Bekleyen Site (E2E) Uzun Adlı Konut Yapı Kooperatifi',
        'ID: 5899864115',
        '2 blok, 12 daire, 3 kapı',
        'Yönetici: Ayşe Yılmaz (64211)',
        'Atatürk Caddesi No: 12',
        'İstanbul / Kadıköy',
        'Oluşturma: 01.10.2026 15:30',
        'Sayfa 1 / 3 | Toplam 25',
      ]) {
        expect(find.text(text), findsWidgets, reason: 'metin korunmalı: $text');
      }
      // 3 kart: biri meşgul (spinner), ikisinde Onayla + Reddet.
      expect(find.byType(SiteApprovalRequestCard), findsNWidgets(3));
      expect(find.text('Onayla'), findsNWidgets(2));
      expect(find.text('Reddet'), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byType(AppCard),
        ),
        findsNothing,
        reason: 'kart-içinde-kart yok',
      );
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
      expect(find.text('Bekleyen Siteler'), findsOneWidget);

      await pumpList(
        t,
        _view(
          sites: const <SiteRecord>[],
          page: fxSitePage(const <SiteRecord>[], total: 0),
        ),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(find.text('Bekleyen site onay talebi yok.'), findsOneWidget);
      expect(find.text('Bekleyen Siteler (0)'), findsOneWidget);
      expect(find.byType(ShimmerScope), findsNothing);
    });
  });

  group('PendingSiteApprovalsView davranış', () {
    testWidgets('Onayla / Reddet: kart kimliğiyle geri çağrı', (t) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      await tapFinder(t, find.text('Onayla').first);
      await tapFinder(t, find.text('Reddet').at(1));
      expect(log, <String>['approve:5899864115', 'reject:5899864116']);
      // Dokunma hedefleri en az 44 dp.
      for (final label in const <String>['Onayla', 'Reddet']) {
        final button = find.ancestor(
          of: find.text(label).first,
          matching: find.bySubtype<ButtonStyleButton>(),
        );
        expect(
          t.getSize(button.first).height,
          greaterThanOrEqualTo(44),
          reason: label,
        );
      }
    });

    testWidgets('yenile: geri çağrı; yüklenirken devre dışı', (t) async {
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

    testWidgets(
      'sayfalama: ipuçları ve sayfa isteği; sayfa verisi yokken 1 / 1',
      (t) async {
        final log = <String>[];
        final sites = fxSites();
        await pumpList(
          t,
          _view(
            log: log,
            sites: sites,
            page: fxSitePage(sites, total: 25, page: 2),
          ),
          width: 360,
          height: 800,
          scale: 1,
          dark: false,
        );
        expect(find.text('Sayfa 2 / 3 | Toplam 25'), findsOneWidget);
        await tapFinder(t, find.byTooltip('Önceki sayfa'));
        await tapFinder(t, find.byTooltip('Sonraki sayfa'));
        expect(log, <String>['page:1', 'page:3']);
        for (final tip in const <String>['Önceki sayfa', 'Sonraki sayfa']) {
          expect(
            t.getSize(find.byTooltip(tip)).shortestSide,
            greaterThanOrEqualTo(44),
          );
        }
      },
    );
  });

  group('PendingSiteApprovalsView kontrast', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        '"Reddet" danger ink, "Onayla" beyaz/success >= 4,5:1 (${dark ? 'koyu' : 'açık'})',
        (t) async {
          await pumpList(
            t,
            _view(),
            width: 360,
            height: 800,
            scale: 1,
            dark: dark,
          );
          final p = dark ? AppPalette.dark : AppPalette.light;
          final reject = t.widget<OutlinedButton>(
            find.ancestor(
              of: find.text('Reddet').first,
              matching: find.byType(OutlinedButton),
            ),
          );
          final fg = reject.style!.foregroundColor!.resolve(<WidgetState>{})!;
          expect(fg, AppTone.danger.ink(p));
          expect(contrastRatio(fg, p.surface), greaterThanOrEqualTo(4.5));

          final approve = t.widget<FilledButton>(
            find.ancestor(
              of: find.text('Onayla').first,
              matching: find.byType(FilledButton),
            ),
          );
          final bg = approve.style!.backgroundColor!.resolve(<WidgetState>{})!;
          expect(bg, AppTone.success.a);
          expect(contrastRatio(Colors.white, bg), greaterThanOrEqualTo(4.5));

          // İkincil satırlar (yönetici/adres/tarih): palet metni, kart yüzeyinde.
          for (final text in const <String>[
            'Yönetici: Ayşe Yılmaz (64211)',
            'Oluşturma: 01.10.2026 15:30',
          ]) {
            final style = t.widget<Text>(find.text(text).first).style!;
            expect(
              contrastRatio(style.color!, p.surface),
              greaterThanOrEqualTo(4.5),
              reason: text,
            );
          }
        },
      );
    }
  });

  group('PendingSiteApprovalsView geniş ekran ve yatay', () {
    testWidgets('820x640 ve 900x400 (yatay), 1,0x/1,5x, açık/koyu: taşma yok', (
      t,
    ) async {
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
            expect(find.text('Onayla'), findsNWidgets(3));
            expect(find.text('Reddet'), findsNWidgets(3));
            expect(t.takeException(), isNull);
          }
        }
      }
    });
  });
}
