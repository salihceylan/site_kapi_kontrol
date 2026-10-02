// FAZ 5 / A2-G3: Yeni Abonelik Talepleri (SubscriptionRequestsView, SubscriptionRequestCard).
//
// AGENTS.md kural 6: taşma YOK (320x640 x2,0 ve 360x640 x1,5; açık + koyu tema). Davranış: Reddet /
// Onayla düğmeleri GÖRÜNÜR; meşgul kartta düğmeler devre dışı ve Onayla içinde spinner; yenile ve
// sayfalama geri çağrıları değişmedi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/models/subscription_request_page.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/subscription_requests_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/subscription_request_card.dart';

import 'list_fixtures.dart';

SubscriptionRequestsView _view({
  List<String>? log,
  bool loading = false,
  List<SubscriptionRequest>? requests,
  SubscriptionRequestPage? page,
  Set<int> busy = const <int>{},
}) {
  final l = log ?? <String>[];
  final list = requests ?? fxRequests();
  return SubscriptionRequestsView(
    pageData: loading ? null : (page ?? fxRequestPage(list, total: 25)),
    requests: loading ? const <SubscriptionRequest>[] : list,
    busyRequests: busy,
    isLoading: loading,
    onRefresh: () => l.add('refresh'),
    onLoadPage: (p) => l.add('page:$p'),
    onApprove: (id) => l.add('approve:$id'),
    onReject: (id) => l.add('reject:$id'),
  );
}

void main() {
  group('SubscriptionRequestsView taşma matrisi', () {
    listMatrix('tam liste: başlık, kartlar, eylemler, sayfalama', (
      t,
      w,
      h,
      scale,
      dark,
    ) async {
      await pumpList(
        t,
        _view(busy: const <int>{32}),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      for (final text in const <String>[
        'Yeni Abonelik Talepleri',
        'Bekleyen Talepler (25)',
        'Deniz Yıldız',
        'Çok Uzun Adlı Soyadlı Bir Abonelik Talep Sahibi',
        'Kod: 31',
        'Kod: 32',
        'E-posta: deniz.yildiz@ornek-alan.com',
        'Telefon: +90 532 111 22 33',
        'Talep Tarihi: 01.10.2026 15:30',
        'Sayfa 1 / 3 | Toplam 25',
      ]) {
        expect(find.text(text), findsWidgets, reason: 'metin korunmalı: $text');
      }
      expect(find.byType(SubscriptionRequestCard), findsNWidgets(2));
      expect(find.text('Reddet'), findsNWidgets(2));
      expect(find.text('Onayla'), findsNWidgets(2));
      // Meşgul kartın "Onayla" düğmesinde spinner; telefonsuz kartta Telefon satırı yok.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('Telefon:'), findsOneWidget);
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
      expect(find.text('Bekleyen Talepler'), findsOneWidget);

      await pumpList(
        t,
        _view(
          requests: const <SubscriptionRequest>[],
          page: fxRequestPage(const <SubscriptionRequest>[], total: 0),
        ),
        width: w,
        height: h,
        scale: scale,
        dark: dark,
      );
      expect(
        find.text('Doğrulanmış yeni abonelik talebi yok.'),
        findsOneWidget,
      );
      expect(find.text('Bekleyen Talepler (0)'), findsOneWidget);
      expect(find.byType(ShimmerScope), findsNothing);
    });
  });

  group('SubscriptionRequestsView davranış', () {
    testWidgets('Reddet / Onayla: talep kimliğiyle geri çağrı', (t) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      await tapFinder(t, find.text('Reddet').first);
      await tapFinder(t, find.text('Onayla').at(1));
      expect(log, <String>['reject:31', 'approve:32']);
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

    testWidgets('meşgul kart: düğmeler devre dışı', (t) async {
      final log = <String>[];
      await pumpList(
        t,
        _view(log: log, busy: const <int>{31}),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      final reject = t.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Reddet').first,
          matching: find.byType(OutlinedButton),
        ),
      );
      final approve = t.widget<FilledButton>(
        find.ancestor(
          of: find.text('Onayla').first,
          matching: find.byType(FilledButton),
        ),
      );
      expect(reject.onPressed, isNull);
      expect(approve.onPressed, isNull);
      // Diğer karttaki düğmeler etkin.
      expect(
        t
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Onayla').at(1),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('yenile ve sayfalama', (t) async {
      final log = <String>[];
      final requests = fxRequests();
      await pumpList(
        t,
        _view(
          log: log,
          requests: requests,
          page: fxRequestPage(requests, total: 25, page: 2),
        ),
        width: 360,
        height: 800,
        scale: 1,
        dark: false,
      );
      await tapFinder(t, find.byIcon(Icons.refresh));
      await tapFinder(t, find.byTooltip('Önceki sayfa'));
      await tapFinder(t, find.byTooltip('Sonraki sayfa'));
      expect(log, <String>['refresh', 'page:1', 'page:3']);
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
  });

  group('SubscriptionRequestsView kontrast', () {
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
          expect(contrastRatio(Colors.white, bg), greaterThanOrEqualTo(4.5));
          // Talep tarihi (en soluk satır): palet etiket metni, kart yüzeyinde.
          final date = t.widget<Text>(
            find.text('Talep Tarihi: 01.10.2026 15:30').first,
          );
          expect(
            contrastRatio(date.style!.color!, p.surface),
            greaterThanOrEqualTo(4.5),
          );
        },
      );
    }
  });

  group('SubscriptionRequestsView geniş ekran ve yatay', () {
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
            expect(find.text('Onayla'), findsNWidgets(2));
            expect(find.text('Reddet'), findsNWidgets(2));
            expect(t.takeException(), isNull);
          }
        }
      }
    });
  });
}
