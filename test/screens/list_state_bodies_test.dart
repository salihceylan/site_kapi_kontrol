// P2-21 + P2-26: ortak liste gövdeleri (CrmListBody, CursorListBody) boş / hata / bağlı değil üçlüsünü StateView ile çizer ve
// isteyen listede yenilemeden sonra "Son güncelleme 14:32" gösterir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import '../design/harness.dart';

const String _offlineText = 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
const String _serverText = 'Bu işlem için yetkiniz yok.';

/// Sıradaki yanıtları sırayla veren sahte kaynak.
class _Source {
  final List<Object> script = <Object>[];

  Future<List<int>> next() async {
    final step = script.removeAt(0);
    if (step is Exception) throw step;
    return step as List<int>;
  }
}

class _PagedHost extends StatefulWidget {
  const _PagedHost({required this.source, this.showLastUpdated = false, required this.clock});

  final _Source source;
  final bool showLastUpdated;
  final DateTime Function() clock;

  @override
  State<_PagedHost> createState() => _PagedHostState();
}

class _PagedHostState extends State<_PagedHost> {
  late final PagedLoader<int> loader = PagedLoader<int>(
    fetch: (offset, limit) async {
      final items = await widget.source.next();
      return (items: items, total: items.length);
    },
    keyOf: (i) => i,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    clock: widget.clock,
  );

  @override
  void initState() {
    super.initState();
    unawaited(loader.reload());
  }

  @override
  void dispose() {
    loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton(onPressed: () => unawaited(loader.reload()), child: const Text('yenile-test')),
          CrmListBody<int>(
            loader: loader,
            showLastUpdated: widget.showLastUpdated,
            emptyIcon: Icons.campaign_rounded,
            emptyTitle: 'Henüz kayıt yok.',
            itemBuilder: (context, item) => Text('kayıt $item'),
          ),
        ],
      );
}

class _CursorHost extends StatefulWidget {
  const _CursorHost({required this.source, this.showLastUpdated = false, required this.clock});

  final _Source source;
  final bool showLastUpdated;
  final DateTime Function() clock;

  @override
  State<_CursorHost> createState() => _CursorHostState();
}

class _CursorHostState extends State<_CursorHost> {
  late final CursorLoader<int> loader = CursorLoader<int>(
    fetch: (before) async => (items: await widget.source.next(), next: null),
    keyOf: (i) => i,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    clock: widget.clock,
  );

  @override
  void initState() {
    super.initState();
    unawaited(loader.reload());
  }

  @override
  void dispose() {
    loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton(onPressed: () => unawaited(loader.reload()), child: const Text('yenile-test')),
          CursorListBody<int>(
            loader: loader,
            showLastUpdated: widget.showLastUpdated,
            emptyIcon: Icons.campaign_rounded,
            emptyTitle: 'Henüz kayıt yok.',
            itemBuilder: (context, item) => Text('kayıt $item'),
          ),
        ],
      );
}

InlineNotice _notice(WidgetTester t) => t.widget<InlineNotice>(find.byType(InlineNotice));

Future<void> _refresh(WidgetTester t) async {
  await t.tap(find.text('yenile-test'));
  await t.pumpAndSettle();
}

void main() {
  // 11:32 UTC = 14:32 İstanbul.
  DateTime clock() => DateTime.now();

  group('CrmListBody', () {
    testWidgets('ilk yükleme ağ hatası: "bağlı değil" bildirimi (kehribar), liste yok; Tekrar Dene yükler', (t) async {
      final source = _Source()
        ..script.addAll(<Object>[ApiException(_offlineText), <int>[1, 2]]);
      await t.pumpWidget(harnessApp(_PagedHost(source: source, clock: clock)));
      await t.pumpAndSettle();
      expect(_notice(t).tone, AppTone.warning);
      expect(find.text(_offlineText), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.text('Henüz kayıt yok.'), findsNothing, reason: 'hata varken "kayıt yok" denmez');

      await t.tap(find.text('Tekrar Dene'));
      await t.pumpAndSettle();
      expect(find.byType(InlineNotice), findsNothing);
      expect(find.text('kayıt 1'), findsOneWidget);
      expect(find.text('kayıt 2'), findsOneWidget);
    });

    testWidgets('sunucu hatası (durum kodu var): mercan hata, "bağlı değil" değil', (t) async {
      final source = _Source()..script.add(ApiException(_serverText, statusCode: 403));
      await t.pumpWidget(harnessApp(_PagedHost(source: source, clock: clock)));
      await t.pumpAndSettle();
      expect(_notice(t).tone, AppTone.danger);
      expect(find.text(_serverText), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    });

    testWidgets('boş liste: EmptyCard (eski görünüm), son güncelleme kapalıyken altyazı yok', (t) async {
      final source = _Source()..script.add(<int>[]);
      await t.pumpWidget(harnessApp(_PagedHost(source: source, clock: clock)));
      await t.pumpAndSettle();
      expect(find.byType(EmptyCard), findsOneWidget);
      expect(find.text('Henüz kayıt yok.'), findsOneWidget);
      expect(find.textContaining('Son güncelleme'), findsNothing);
    });

    testWidgets('showLastUpdated: yükleme ve her yenileme sonrası "Son güncelleme HH:mm"; kapalıyken yok', (t) async {
      var now = DateTime.utc(2026, 10, 28, 11, 32);
      final source = _Source()..script.addAll(<Object>[<int>[1], <int>[1, 2]]);
      await t.pumpWidget(harnessApp(_PagedHost(source: source, showLastUpdated: true, clock: () => now)));
      await t.pumpAndSettle();
      expect(find.text('kayıt 1'), findsOneWidget);
      expect(find.textContaining('14:32'), findsOneWidget);

      now = DateTime.utc(2026, 10, 28, 11, 40);
      await _refresh(t);
      expect(find.text('kayıt 2'), findsOneWidget);
      expect(find.textContaining('14:32'), findsNothing);
      expect(find.textContaining('14:40'), findsOneWidget);
    });

    testWidgets('boş ama yüklenmiş liste de yenilemeden sonra saat gösterir', (t) async {
      final source = _Source()..script.add(<int>[]);
      await t.pumpWidget(
        harnessApp(_PagedHost(source: source, showLastUpdated: true, clock: () => DateTime.utc(2026, 10, 28, 11, 32))),
      );
      await t.pumpAndSettle();
      expect(find.byType(EmptyCard), findsOneWidget);
      expect(find.textContaining('14:32'), findsOneWidget);
    });

    testWidgets('yenileme ağ hatası verirse eski kayıtlar durur: bağlı değil bildirimi + eski saat + uyarı', (t) async {
      var now = DateTime.utc(2026, 10, 28, 11, 32);
      final source = _Source()..script.addAll(<Object>[<int>[1, 2], ApiException(_offlineText)]);
      await t.pumpWidget(harnessApp(_PagedHost(source: source, showLastUpdated: true, clock: () => now)));
      await t.pumpAndSettle();
      now = DateTime.utc(2026, 10, 28, 12, 10);
      await _refresh(t);
      expect(_notice(t).tone, AppTone.warning);
      expect(find.text('kayıt 1'), findsOneWidget, reason: 'eski kayıtlar silinmez');
      expect(find.textContaining('14:32'), findsOneWidget, reason: 'en son BAŞARILI güncelleme');
      expect(find.textContaining('15:10'), findsNothing);
      expect(find.textContaining('Kayıtlar eski olabilir'), findsOneWidget);
    });
  });

  group('CursorListBody', () {
    testWidgets('ağ hatası: bağlı değil bildirimi; boş liste: EmptyCard; son güncelleme isteğe bağlı', (t) async {
      final source = _Source()..script.addAll(<Object>[ApiException(_offlineText), <int>[]]);
      await t.pumpWidget(harnessApp(_CursorHost(source: source, showLastUpdated: true, clock: clock)));
      await t.pumpAndSettle();
      expect(_notice(t).tone, AppTone.warning);
      expect(find.textContaining('Son güncelleme'), findsNothing, reason: 'hiç başarılı yükleme olmadı');

      await t.tap(find.text('Tekrar Dene'));
      await t.pumpAndSettle();
      expect(find.byType(EmptyCard), findsOneWidget);
      expect(find.textContaining('Son güncelleme'), findsOneWidget);
    });

    testWidgets('showLastUpdated kapalıyken (varsayılan) altyazı çıkmaz', (t) async {
      final source = _Source()..script.add(<int>[1]);
      await t.pumpWidget(harnessApp(_CursorHost(source: source, clock: clock)));
      await t.pumpAndSettle();
      expect(find.text('kayıt 1'), findsOneWidget);
      expect(find.textContaining('Son güncelleme'), findsNothing);
    });

    testWidgets('sunucu hatası yenilemede eski kayıtları korur: mercan bildirim, saat uyarısıyla', (t) async {
      final source = _Source()..script.addAll(<Object>[<int>[7], ApiException(_serverText, statusCode: 500)]);
      await t.pumpWidget(
        harnessApp(_CursorHost(source: source, showLastUpdated: true, clock: () => DateTime.utc(2026, 10, 28, 11, 32))),
      );
      await t.pumpAndSettle();
      await _refresh(t);
      expect(_notice(t).tone, AppTone.danger);
      expect(find.text('kayıt 7'), findsOneWidget);
      expect(find.textContaining('14:32'), findsOneWidget);
    });
  });

  group('taşmaz', () {
    for (final width in <double>[320, 360]) {
      testWidgets('bağlı değil + eski kayıtlar + saat ${width.toInt()} dp x2,0', (t) async {
        final source = _Source()
          ..script.addAll(<Object>[
            <int>[1, 2, 3],
            ApiException('$_offlineText ${_offlineText * 2}'),
          ]);
        await pumpAt(
          t,
          SizedBox(
            width: double.infinity,
            child: _PagedHost(source: source, showLastUpdated: true, clock: () => DateTime.utc(2026, 10, 28, 11, 32)),
          ),
          width: width,
          height: 640,
          scale: 2.0,
        );
        await t.pumpAndSettle();
        await t.tap(find.text('yenile-test'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byType(InlineNotice), findsOneWidget);
      });
    }
  });
}
