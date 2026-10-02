// FAZ 5 / A2-G2: DoorLogsAccordion (geçiş günlükleri akordiyonu) tasarım yenileme testleri.
//
// - Taşma matrisi: 320x640 x2,0 ve 360x640 x1,5; açık + koyu; tüm durumlar (kapalı, yükleniyor,
//   hata, boş, liste + sayfalama, uzun adlar).
// - Davranış korunur: kapalı başlangıç, açınca ilk sayfa, sayfalama, yenile, PDF, tekrar dene.
// - Tasarım: OutlinedButton başlık (ton info), SkeletonBox (4 satır), EmptyState(kompakt), InlineNotice,
//   StaggeredEntry, AnimatedCount, IconButton >= 44 dp, kontrast >= 4,5:1 (yöntem rozetleri dahil).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/door_logs_accordion.dart';

import '../design/harness.dart';
import 'g2_support.dart';

Widget _acc({
  G2LogsAuth? auth,
  VoidCallback? onDownloadPdf,
  bool isOpeningDoor = false,
  String doorName = 'Ana Giriş Kapısı',
}) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: SizedBox(
      width: double.infinity,
      child: DoorLogsAccordion(
        selectedSite: g2Site(),
        selectedDoor: g2Door(name: doorName),
        authService: auth,
        onDownloadPdf: onDownloadPdf,
        isOpeningDoor: isOpeningDoor,
      ),
    ),
  );
}

final Finder _header = find.textContaining('Geçiş Logları');

Future<void> _expand(WidgetTester t) async {
  await t.tap(_header);
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 700));
}

typedef _Scenario = ({
  String name,
  G2LogsAuth Function() auth,
  bool expand,
  VoidCallback? pdf,
  String doorName,
});

final List<_Scenario> _scenarios = <_Scenario>[
  (
    name: 'kapalı (varsayılan)',
    auth: () => G2LogsAuth(),
    expand: false,
    pdf: null,
    doorName: 'Ana Giriş Kapısı',
  ),
  (
    name: 'açık: ilk yükleme (iskelet)',
    auth: () => G2LogsAuth(never: true),
    expand: true,
    pdf: null,
    doorName: 'Ana Giriş Kapısı',
  ),
  (
    name: 'açık: hata + tekrar dene',
    auth: () => G2LogsAuth(error: 'Loglar yüklenirken bir hata oluştu.'),
    expand: true,
    pdf: null,
    doorName: 'Ana Giriş Kapısı',
  ),
  (
    name: 'açık: boş',
    auth: () =>
        G2LogsAuth(pages: [g2LogPage(count: 0, total: 0, totalPages: 1)]),
    expand: true,
    pdf: null,
    doorName: 'Ana Giriş Kapısı',
  ),
  (
    name: 'açık: liste + sayfalama + PDF',
    auth: () => G2LogsAuth(pages: [g2LogPage(count: 5)]),
    expand: true,
    pdf: () {},
    doorName: 'Ana Giriş Kapısı',
  ),
  (
    name: 'açık: uzun kapı adı ve kullanıcı adları',
    auth: () => G2LogsAuth(pages: [g2LogPage(count: 4)]),
    expand: true,
    pdf: () {},
    doorName:
        'Çok Uzun İsimli Ana Giriş Kapısı ve Otopark Bariyeri Geçiş Noktası',
  ),
];

void main() {
  group('taşma matrisi (320x640 x2,0 ve 360x640 x1,5; açık + koyu)', () {
    for (final s in _scenarios) {
      testWidgets(s.name, (t) async {
        for (final cell in kG2Cells) {
          for (final dark in const <bool>[false, true]) {
            await pumpAt(
              t,
              _acc(auth: s.auth(), onDownloadPdf: s.pdf, doorName: s.doorName),
              width: cell.width,
              height: 640,
              scale: cell.scale,
              dark: dark,
            );
            if (s.expand) {
              await _expand(t);
            }
            expect(
              t.takeException(),
              isNull,
              reason: '${s.name}: ${g2CellLabel(cell.width, cell.scale, dark)}',
            );
          }
        }
      });
    }
  });

  group('açılış ve yükleme (mevcut davranış korunur)', () {
    testWidgets(
      'kapalı başlar: başlık, aşağı ok, istek yok; dokununca açılır ve ilk sayfa istenir',
      (t) async {
        final auth = G2LogsAuth(pages: [g2LogPage(count: 3)]);
        await pumpAt(t, _acc(auth: auth), width: 360, scale: 1.0);
        expect(find.text('📊 Ana Giriş Kapısı Geçiş Logları'), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);
        expect(auth.calls, 0);
        expect(
          t
              .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
              .crossFadeState,
          CrossFadeState.showFirst,
        );

        await _expand(t);
        expect(auth.requestedPages, [1]);
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
        expect(
          t
              .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
              .crossFadeState,
          CrossFadeState.showSecond,
        );
        expect(
          t.widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade)).duration,
          AppMotion.base,
        );

        await t.tap(_header);
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
        expect(auth.calls, 1, reason: 'kapatmak yeniden yüklemez');
      },
    );

    testWidgets(
      'oturum yokken (authService null) hata cümlesi ve "Geçiş Geçmişi" başlığı birebir',
      (t) async {
        await pumpAt(t, _acc(), width: 360, scale: 1.0);
        await _expand(t);
        expect(find.text('Geçiş Geçmişi'), findsOneWidget);
        expect(find.text('Giriş oturumu bulunamadı.'), findsOneWidget);
        expect(find.byType(InlineNotice), findsOneWidget);
      },
    );

    testWidgets(
      'ilk yükleme: 4 satır iskelet (tek ShimmerScope) + metin; yenilemede liste kalır',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpAt(
          t,
          _acc(auth: G2LogsAuth(never: true)),
          width: 360,
          scale: 1.0,
        );
        await _expand(t);
        expect(find.byType(ShimmerScope), findsOneWidget);
        expect(
          find.byType(SkeletonBox),
          findsNWidgets(16),
          reason: '4 satır x (simge + 2 satır + saat)',
        );
        expect(find.text('Geçiş logları getiriliyor...'), findsOneWidget);
        expect(find.bySemanticsLabel('Yükleniyor'), findsOneWidget);
        expect(find.byType(EmptyState), findsNothing);
        handle.dispose();
      },
    );

    testWidgets(
      'iskelet bitince kalkar (kararlı durumda ticker yok: pumpAndSettle biter)',
      (t) async {
        await pumpAt(
          t,
          _acc(auth: G2LogsAuth(pages: [g2LogPage(count: 3)])),
          width: 360,
          scale: 1.0,
        );
        await _expand(t);
        expect(find.byType(ShimmerScope), findsNothing);
        expect(find.byType(SkeletonBox), findsNothing);
        await t.pumpAndSettle();
      },
    );

    testWidgets(
      'kapı açma bitince (isOpeningDoor true -> false) açıksa ilk sayfa yeniden yüklenir',
      (t) async {
        final auth = G2LogsAuth(
          pages: [g2LogPage(count: 3), g2LogPage(count: 3)],
        );
        final opening = ValueNotifier<bool>(false);
        addTearDown(opening.dispose);
        await pumpAt(
          t,
          ValueListenableBuilder<bool>(
            valueListenable: opening,
            builder: (c, v, _) => _acc(auth: auth, isOpeningDoor: v),
          ),
          width: 360,
          scale: 1.0,
        );
        await _expand(t);
        expect(auth.calls, 1);
        opening.value = true;
        await t.pump();
        opening.value = false;
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(auth.calls, 2);
        expect(auth.requestedPages.last, 1);
      },
    );
  });

  group('liste, sayaç ve sayfalama', () {
    testWidgets(
      'satırlar, "Toplam N geçiş kaydı", sayaç rozeti, sayfa metni; her satır StaggeredEntry',
      (t) async {
        final auth = G2LogsAuth(pages: [g2LogPage(count: 5, total: 23)]);
        await pumpAt(
          t,
          _acc(auth: auth, onDownloadPdf: () {}),
          width: 360,
          scale: 1.0,
        );
        await _expand(t);
        expect(find.text('Toplam 23 geçiş kaydı'), findsOneWidget);
        expect(
          find.text('23'),
          findsOneWidget,
          reason: 'başlıktaki sayaç rozeti',
        );
        expect(find.text('Sayfa 1 / 3'), findsOneWidget);
        expect(find.byType(StaggeredEntry), findsNWidgets(5));
        expect(find.text('Ali Veli 1'), findsOneWidget);
        expect(find.text('Mobil Bulut'), findsOneWidget);
        expect(find.text('Yerel Wi-Fi'), findsOneWidget);
        expect(find.text('Sesli Komut'), findsOneWidget);
        expect(find.text('Misafir Linki'), findsOneWidget);
        expect(find.text('GM60 QR Okuyucu'), findsOneWidget);
        // Zaman metni kalıbı (yerel saat dilimine bağlı olduğundan yalnız biçim): SS:DD ve GG.AA.YYYY
        expect(find.textContaining(RegExp(r'^\d\d:\d\d$')), findsNWidgets(5));
        expect(
          find.textContaining(RegExp(r'^\d\d\.\d\d\.\d{4}$')),
          findsNWidgets(5),
        );
      },
    );

    testWidgets(
      'sayfalama: Önceki ilk sayfada devre dışı; Sonraki 2. sayfayı ister; sonra Önceki 1. sayfayı',
      (t) async {
        final auth = G2LogsAuth(
          pages: [
            g2LogPage(count: 3, page: 1),
            g2LogPage(count: 2, total: 23, page: 2),
            g2LogPage(count: 3, page: 1),
          ],
        );
        await pumpAt(t, _acc(auth: auth), width: 360, scale: 1.0);
        await _expand(t);
        TextButton button(String label) => t.widget<TextButton>(
          find
              .ancestor(of: find.text(label), matching: find.byType(TextButton))
              .first,
        );
        expect(button('Önceki').onPressed, isNull);
        expect(button('Sonraki').onPressed, isNotNull);
        expect(
          t
              .getSize(
                find
                    .ancestor(
                      of: find.text('Sonraki'),
                      matching: find.byType(TextButton),
                    )
                    .first,
              )
              .height,
          greaterThanOrEqualTo(44),
        );

        await t.tap(find.text('Sonraki'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(auth.requestedPages, [1, 2]);
        expect(find.text('Sayfa 2 / 3'), findsOneWidget);
        expect(button('Önceki').onPressed, isNotNull);

        await t.tap(find.text('Önceki'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(auth.requestedPages, [1, 2, 1]);
        expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      },
    );

    testWidgets('son sayfada Sonraki devre dışı', (t) async {
      final auth = G2LogsAuth(
        pages: [g2LogPage(count: 3, total: 3, page: 1, totalPages: 1)],
      );
      await pumpAt(t, _acc(auth: auth), width: 360, scale: 1.0);
      await _expand(t);
      expect(
        t
            .widget<TextButton>(
              find
                  .ancestor(
                    of: find.text('Sonraki'),
                    matching: find.byType(TextButton),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('sayaç değişince (yenile) AnimatedCount son değere akar', (
      t,
    ) async {
      final auth = G2LogsAuth(
        pages: [g2LogPage(count: 3, total: 23), g2LogPage(count: 3, total: 30)],
      );
      await pumpAt(t, _acc(auth: auth), width: 360, scale: 1.0);
      await _expand(t);
      expect(find.text('23'), findsOneWidget);
      await t.tap(find.byTooltip('Yenile'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('30'), findsOneWidget);
      expect(find.text('Toplam 30 geçiş kaydı'), findsOneWidget);
    });

    testWidgets(
      'boş liste: EmptyState(kompakt) ve mevcut cümle; sayfalama yok',
      (t) async {
        final auth = G2LogsAuth(
          pages: [g2LogPage(count: 0, total: 0, totalPages: 1)],
        );
        await pumpAt(t, _acc(auth: auth), width: 360, scale: 1.0);
        await _expand(t);
        expect(find.byType(EmptyState), findsOneWidget);
        expect(t.widget<EmptyState>(find.byType(EmptyState)).compact, isTrue);
        expect(
          find.text('Kayıtlı kapı geçiş kaydı bulunamadı.'),
          findsOneWidget,
        );
        expect(find.text('Önceki'), findsNothing);
      },
    );
  });

  group('düğmeler: yenile, PDF, tekrar dene', () {
    testWidgets(
      'IconButton\'lar >= 44 dp; PDF yalnız callback varken; yenile aynı sayfayı ister',
      (t) async {
        var pdf = 0;
        final auth = G2LogsAuth(pages: [g2LogPage(count: 3)]);
        await pumpAt(
          t,
          _acc(auth: auth, onDownloadPdf: () => pdf++),
          width: 360,
          scale: 1.0,
        );
        await _expand(t);
        for (final tip in const <String>['PDF Raporu İndir', 'Yenile']) {
          final size = t.getSize(find.byTooltip(tip));
          expect(size.width, greaterThanOrEqualTo(44), reason: tip);
          expect(size.height, greaterThanOrEqualTo(44), reason: tip);
        }
        await t.tap(find.byTooltip('PDF Raporu İndir'));
        expect(pdf, 1);
        await t.tap(find.byTooltip('Yenile'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(auth.requestedPages, [1, 1]);

        await pumpAt(
          t,
          _acc(auth: G2LogsAuth(pages: [g2LogPage(count: 3)])),
          width: 360,
          scale: 1.0,
        );
        await _expand(t);
        expect(find.byTooltip('PDF Raporu İndir'), findsNothing);
      },
    );

    testWidgets(
      'yenilerken düğme devre dışı + aynı küçük CircularProgressIndicator',
      (t) async {
        await pumpAt(
          t,
          _acc(auth: G2LogsAuth(never: true)),
          width: 360,
          scale: 1.0,
        );
        await _expand(t);
        // IconButton, ipucu (Tooltip) sarmalayıcısının atasıdır.
        final refresh = t.widget<IconButton>(
          find
              .ancestor(
                of: find.byTooltip('Yenile'),
                matching: find.byType(IconButton),
              )
              .first,
        );
        expect(refresh.onPressed, isNull);
        expect(
          find.descendant(
            of: find.byTooltip('Yenile'),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'hata: InlineNotice + "Tekrar Dene" aynı sayfayı yeniden ister',
      (t) async {
        final auth = G2LogsAuth(error: 'Loglar yüklenirken bir hata oluştu.');
        await pumpAt(t, _acc(auth: auth), width: 360, scale: 1.0);
        await _expand(t);
        expect(
          find.text('Loglar yüklenirken bir hata oluştu.'),
          findsOneWidget,
        );
        expect(
          t.widget<InlineNotice>(find.byType(InlineNotice)).tone,
          AppTone.danger,
        );
        await t.tap(find.text('Tekrar Dene'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(auth.requestedPages, [1, 1]);
      },
    );
  });

  group('düzen: dar ekranda tarih/saat adın altına iner', () {
    testWidgets(
      'geniş (412 px x 1,0): saat sağda; dar (320 px x 2,0): saat adın altında',
      (t) async {
        final auth = G2LogsAuth(pages: [g2LogPage(count: 2)]);
        await pumpAt(t, _acc(auth: auth), width: 412, scale: 1.0);
        await _expand(t);
        var name = t.getRect(find.text('Ali Veli 1'));
        var time = t.getRect(find.textContaining(RegExp(r'^\d\d:\d\d$')).at(1));
        expect(
          time.left,
          greaterThan(name.right),
          reason: 'tablo gibi: saat sağ sütunda',
        );

        await pumpAt(
          t,
          _acc(auth: G2LogsAuth(pages: [g2LogPage(count: 2)])),
          width: 320,
          scale: 2.0,
        );
        await _expand(t);
        name = t.getRect(find.text('Ali Veli 1'));
        time = t.getRect(find.textContaining(RegExp(r'^\d\d:\d\d$')).at(1));
        expect(
          time.top,
          greaterThan(name.bottom - 1),
          reason: 'dar ekranda alt satır',
        );
        expect(t.takeException(), isNull);
      },
    );
  });

  group('kontrast >= 4,5:1', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        'yöntem rozetleri (ink / tint), başlık düğmesi, ikincil metinler ${dark ? 'koyu' : 'açık'} temada',
        (t) async {
          final p = dark ? AppPalette.dark : AppPalette.light;
          final logs = DoorAccessLogPage.fromJson(<String, dynamic>{
            'logs': [
              for (final trigger in const <String>[
                'cloud_app',
                'local_wifi',
                'ble',
                'guest_pass',
                'voice',
                'display_btn',
                'physical_btn',
                'serial_btn',
                'offline_sync',
                'screen_qr',
                'qr_scanner',
              ])
                {
                  'id': trigger.hashCode,
                  'site_code': 101,
                  'door_name': 'K',
                  'user_name': 'U $trigger',
                  'user_role': 'apartment_owner',
                  'trigger_type': trigger,
                  'opened_at': '2026-05-01T08:00:00Z',
                },
            ],
            'total': 11,
            'page': 1,
            'page_size': 10,
            'total_pages': 2,
          });
          await pumpAt(
            t,
            _acc(auth: G2LogsAuth(pages: [logs])),
            width: 412,
            scale: 1.0,
            dark: dark,
          );
          await _expand(t);

          final surface = p.surface;
          for (final log in logs.logs) {
            final label = log.triggerTypeDisplay;
            final badge = find.text(label).first;
            final ink = g2TextColor(t, badge);
            // Rozet zemini: satır yüzeyi + yöntem tint'i (tint, ink'in tonuna aittir).
            final tone = AppTone.values.firstWhere(
              (tn) => tn.ink(p) == ink,
              orElse: () => throw StateError('$label: ink bir ton rengi değil'),
            );
            expect(
              g2Contrast(ink, g2Over(tone.tint(p), surface)),
              greaterThanOrEqualTo(4.5),
              reason: '$label dark=$dark',
            );
          }

          // Başlık düğmesi: info ink'i, açıkken info tint'i üstünde.
          final headerColor = g2TextColor(
            t,
            find.textContaining('Geçiş Logları'),
          );
          expect(headerColor, AppTone.info.ink(p));
          expect(
            g2Contrast(headerColor, g2Over(AppTone.info.tint(p), p.surface)),
            greaterThanOrEqualTo(4.5),
          );

          // İkincil metinler: panel (surfaceMuted) ve satır (surface) yüzeyinde.
          final caption = g2TextColor(t, find.text('Toplam 11 geçiş kaydı'));
          expect(caption, p.textSecondary);
          expect(
            g2Contrast(caption, p.surfaceMuted),
            greaterThanOrEqualTo(4.5),
          );
          final role = find.textContaining('Daire Sakini').first;
          final roleColor = g2TextColor(t, role);
          expect(
            g2Contrast(roleColor, surface),
            greaterThanOrEqualTo(4.5),
            reason: 'rol/daire satırı',
          );
        },
      );
    }
  });

  group('hareket azaltma', () {
    testWidgets(
      'liste girişi ve açılış tek pump ile son durumda; pumpAndSettle biter',
      (t) async {
        final auth = G2LogsAuth(pages: [g2LogPage(count: 5)]);
        await pumpAt(t, _acc(auth: auth), width: 360, scale: 1.0, reduce: true);
        await t.tap(_header);
        await t.pump();
        await t.pump();
        await t.pumpAndSettle();
        expect(find.text('Ali Veli 1'), findsOneWidget);
      },
    );
  });

  group(
    'geniş ekranlar (412 / 820 / 1100 px) ve yatay telefon (640x360); yazı 1,0',
    () {
      for (final s in _scenarios) {
        testWidgets(s.name, (t) async {
          for (final size in const <({double w, double h})>[
            (w: 412, h: 640),
            (w: 820, h: 1180),
            (w: 1100, h: 800),
            (w: 640, h: 360),
          ]) {
            for (final dark in const <bool>[false, true]) {
              await pumpAt(
                t,
                _acc(
                  auth: s.auth(),
                  onDownloadPdf: s.pdf,
                  doorName: s.doorName,
                ),
                width: size.w,
                height: size.h,
                scale: 1.0,
                dark: dark,
              );
              if (s.expand) {
                await _expand(t);
              }
              expect(
                t.takeException(),
                isNull,
                reason: '${s.name}: ${size.w}x${size.h} koyu=$dark',
              );
            }
          }
        });
      }
    },
  );
}
