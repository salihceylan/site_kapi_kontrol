// P2-21: StateView (boş / hata / bağlı değil üçlüsü) ve P2-26: "Son güncelleme" altyazısı.
//
// Üç durum ayrı görünür (ton + ikon + metin): boş = nötr rozet, hata = mercan, bağlı değil = kehribar bulut-yok. Satır içi
// görünüm eski EmptyCard / InlineNotice ile aynı tiplerdedir (listelerin testleri onlara bağlı); tam ekran (prominent)
// görünüm EmptyState'tir. Taşma matrisi: 320/360/412/820 dp x yazı ölçeği 1,0/1,5/2,0 x açık/koyu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/last_updated.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/state_view.dart';

import 'harness.dart';

const String _errorText = 'Bu işlem için yetkiniz yok.';
const String _emptyTitle = 'Henüz duyuru yok.';
const String _emptyMessage = 'Yönetimin size gönderdiği duyurular burada görünür.';

Widget _empty({bool prominent = false, Widget? action}) => StateView.empty(
      icon: Icons.campaign_rounded,
      title: _emptyTitle,
      message: _emptyMessage,
      action: action,
      prominent: prominent,
    );

InlineNotice _notice(WidgetTester t) => t.widget<InlineNotice>(find.byType(InlineNotice));

void main() {
  group('StateView: üç durum üç ayrı görünüm (satır içi)', () {
    testWidgets('boş: EmptyCard (başlık + mesaj), bildirim yok; eylem kartın içinde', (t) async {
      var taps = 0;
      await t.pumpWidget(
        harnessApp(_empty(action: TextButton(onPressed: () => taps++, child: const Text('Excel\'den yükle')))),
      );
      await t.pumpAndSettle();
      expect(find.byType(EmptyCard), findsOneWidget);
      expect(find.byType(InlineNotice), findsNothing);
      expect(find.text(_emptyTitle), findsOneWidget);
      expect(find.text(_emptyMessage), findsOneWidget);
      await t.tap(find.text('Excel\'den yükle'));
      expect(taps, 1);
    });

    testWidgets('hata: mercan InlineNotice, hizmetin mesajı olduğu gibi, hata ikonu; Tekrar Dene çağırır', (t) async {
      var retries = 0;
      await t.pumpWidget(harnessApp(StateView.error(message: _errorText, onRetry: () => retries++)));
      await t.pumpAndSettle();
      expect(find.byType(EmptyCard), findsNothing);
      final notice = _notice(t);
      expect(notice.tone, AppTone.danger);
      expect(notice.message, _errorText);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text(_errorText), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      await t.tap(find.text('Tekrar Dene'));
      expect(retries, 1);
    });

    testWidgets('bağlı değil: kehribar InlineNotice, bulut-yok ikonu, standart metin; Tekrar Dene çağırır', (t) async {
      var retries = 0;
      await t.pumpWidget(harnessApp(StateView.offline(onRetry: () => retries++)));
      await t.pumpAndSettle();
      final notice = _notice(t);
      expect(notice.tone, AppTone.warning);
      expect(notice.message, StateView.offlineMessage);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      expect(find.text('Sunucuya ulaşılamıyor. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      await t.tap(find.text('Tekrar Dene'));
      expect(retries, 1);
    });

    testWidgets('failure: aynı mesaj, offline bayrağına göre bağlı değil ya da hata; mesaj değişmez', (t) async {
      const message = 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      await t.pumpWidget(harnessApp(StateView.failure(message: message, offline: true)));
      await t.pumpAndSettle();
      expect(_notice(t).tone, AppTone.warning);
      expect(find.text(message), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);

      await t.pumpWidget(harnessApp(StateView.failure(message: message, offline: false)));
      await t.pumpAndSettle();
      expect(_notice(t).tone, AppTone.danger);
      expect(find.text(message), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('onRetry verilmezse Tekrar Dene çıkmaz (hata ve bağlı değil)', (t) async {
      await t.pumpWidget(harnessApp(const StateView.error(message: _errorText)));
      await t.pumpAndSettle();
      expect(find.text('Tekrar Dene'), findsNothing);
      await t.pumpWidget(harnessApp(const StateView.offline()));
      await t.pumpAndSettle();
      expect(find.text('Tekrar Dene'), findsNothing);
    });

    testWidgets('eski kayıtlar ekranda duruyorsa bildirimin altında "Son güncelleme" ve uyarı yazar', (t) async {
      final at = DateTime.utc(2026, 10, 28, 11, 32); // İstanbul 14:32
      await t.pumpWidget(
        harnessApp(StateView.offline(onRetry: () {}, lastUpdated: at)),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('14:32'), findsOneWidget);
      expect(find.textContaining('Kayıtlar eski olabilir'), findsOneWidget);
      expect(find.byType(InlineNotice), findsOneWidget);

      await t.pumpWidget(harnessApp(StateView.error(message: _errorText, onRetry: () {})));
      await t.pumpAndSettle();
      expect(find.textContaining('Son güncelleme'), findsNothing);
    });
  });

  group('StateView: tam ekran (prominent)', () {
    testWidgets('boş: EmptyState, başlık + mesaj', (t) async {
      await t.pumpWidget(harnessApp(_empty(prominent: true)));
      await t.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(InlineNotice), findsNothing);
      expect(find.text(_emptyTitle), findsOneWidget);
      expect(find.text(_emptyMessage), findsOneWidget);
    });

    testWidgets('hata: mercan rozet + başlık + hizmet mesajı + Tekrar Dene', (t) async {
      var retries = 0;
      await t.pumpWidget(
        harnessApp(StateView.error(message: _errorText, onRetry: () => retries++, prominent: true)),
      );
      await t.pumpAndSettle();
      final state = t.widget<EmptyState>(find.byType(EmptyState));
      expect(state.tone, AppTone.danger);
      expect(state.icon, Icons.error_outline_rounded);
      expect(find.text(StateView.errorTitle), findsOneWidget);
      expect(find.text(_errorText), findsOneWidget);
      await t.tap(find.text('Tekrar Dene'));
      expect(retries, 1);
    });

    testWidgets('bağlı değil: kehribar rozet + "Sunucuya ulaşılamıyor" başlığı + Tekrar Dene', (t) async {
      var retries = 0;
      await t.pumpWidget(harnessApp(StateView.offline(onRetry: () => retries++, prominent: true)));
      await t.pumpAndSettle();
      final state = t.widget<EmptyState>(find.byType(EmptyState));
      expect(state.tone, AppTone.warning);
      expect(state.icon, Icons.cloud_off_rounded);
      expect(find.text(StateView.offlineTitle), findsOneWidget);
      expect(find.text(StateView.offlineMessage), findsOneWidget);
      await t.tap(find.text('Tekrar Dene'));
      expect(retries, 1);
    });

    testWidgets('eski kayıtlarla birlikte: mesajın altına "Son güncelleme" satırı eklenir', (t) async {
      await t.pumpWidget(
        harnessApp(
          StateView.offline(onRetry: () {}, lastUpdated: DateTime.utc(2026, 10, 28, 11, 32), prominent: true),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('14:32'), findsOneWidget);
    });
  });

  group('LastUpdatedCaption / formatLastUpdated', () {
    test('aynı gün: yalnız saat (İstanbul saati, UTC+3)', () {
      final at = DateTime.utc(2026, 10, 28, 11, 32);
      expect(formatLastUpdated(at, now: DateTime.utc(2026, 10, 28, 12)), 'Son güncelleme 14:32');
    });

    test('gece yarısı sınırı İstanbul saatine göre: UTC 21:30 ertesi günün 00:30\'udur', () {
      final at = DateTime.utc(2026, 10, 28, 21, 30); // İstanbul 29.10 00:30
      expect(formatLastUpdated(at, now: DateTime.utc(2026, 10, 28, 22)), 'Son güncelleme 00:30');
      expect(formatLastUpdated(at, now: DateTime.utc(2026, 10, 29, 22)), 'Son güncelleme 29.10.2026 00:30');
    });

    test('başka gün: tarih de yazılır (eski veri "az önce" gibi görünmez)', () {
      final at = DateTime.utc(2026, 10, 27, 11, 32);
      expect(formatLastUpdated(at, now: DateTime.utc(2026, 10, 28, 12)), 'Son güncelleme 27.10.2026 14:32');
    });

    testWidgets('altyazı: küçük sessiz metin (textMuted), sağa hizalı; stale ise uyarı ekler', (t) async {
      final now = DateTime.now();
      await t.pumpWidget(harnessApp(LastUpdatedCaption(at: now)));
      await t.pumpAndSettle();
      final text = t.widget<Text>(find.textContaining('Son güncelleme'));
      final p = AppPalette.light;
      expect(text.style!.color, p.textMuted);
      expect(text.data, startsWith('Son güncelleme '));
      expect(text.data, isNot(contains('eski olabilir')));
      final align = t.widget<Align>(find.descendant(of: find.byType(LastUpdatedCaption), matching: find.byType(Align)));
      expect(align.alignment, AlignmentDirectional.centerEnd);

      await t.pumpWidget(harnessApp(LastUpdatedCaption(at: now, stale: true)));
      await t.pumpAndSettle();
      expect(find.textContaining('Kayıtlar eski olabilir'), findsOneWidget);
    });
  });

  group('StateView taşmaz: boyut x yazı ölçeği x tema', () {
    final longMessage = 'Sunucuya ulaşılamadı. ${'Ağ bağlantınızı (güvenlik duvarı/proxy) kontrol edip tekrar deneyin. ' * 3}';
    final cases = <String, Widget Function()>{
      'boş': () => _empty(),
      'hata': () => StateView.error(message: longMessage, onRetry: () {}, lastUpdated: DateTime.utc(2026, 10, 28, 11, 32)),
      'bağlı değil': () => StateView.offline(onRetry: () {}, lastUpdated: DateTime.utc(2026, 10, 28, 11, 32)),
      'boş (tam ekran)': () => _empty(prominent: true),
      'hata (tam ekran)': () => StateView.error(message: longMessage, onRetry: () {}, prominent: true),
      'bağlı değil (tam ekran)': () => StateView.offline(onRetry: () {}, prominent: true),
    };
    for (final entry in cases.entries) {
      testWidgets(entry.key, (t) async {
        await forEachHarnessCell((width, scale, dark) async {
          await pumpAt(
            t,
            SizedBox(width: double.infinity, child: entry.value()),
            width: width,
            height: 640,
            scale: scale,
            dark: dark,
          );
        });
      });
    }
  });
}
