// Site başına SMS + WhatsApp bağlantısı kartı: yönetici yazar, kurul yalnız görür; WhatsApp dürüstçe "doğrulama modunda";
// sınama GERÇEK SMS göndermez (yalnız /sms/test). Gizli değerler ekranda görünmez. Dar ekranda taşma yok.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/ui/widgets/messaging_connections_card.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

http.Response _json(Map<String, Object?> body) =>
    http.Response(jsonEncode(body), 200, headers: const <String, String>{'content-type': 'application/json; charset=utf-8'});

const String _waNote = 'WhatsApp sürücüsü bu sürümde doğrulama modunda; Meta hesabı bağlanınca etkinleşir.';

Map<String, Object?> _status({bool sms = true, bool globalFallback = false}) => <String, Object?>{
  'key_configured': true,
  'can_write': true,
  'sms': <String, Object?>{
    'drivers': <Object?>[
      <String, Object?>{'id': 'netgsm', 'label': 'NetGSM'},
    ],
    'connection': sms
        ? <String, Object?>{
            'provider': 'netgsm',
            'config': <String, Object?>{'header': 'SITEAPT', 'secret_hint': 'si***'},
            'last_test': <String, Object?>{'ok': true, 'code': '00'},
          }
        : null,
    'global_fallback': globalFallback,
  },
  'whatsapp': <String, Object?>{
    'driver': <String, Object?>{'id': 'meta_cloud', 'label': 'Meta WhatsApp Cloud API', 'active': false, 'note': _waNote},
    'connection': null,
  },
};

Future<List<String>> _pump(WidgetTester t, {required bool canWrite, Map<String, Object?>? status, double width = 320}) async {
  final log = <String>[];
  final api = MessagingApi(
    baseUrl: 'http://localhost',
    client: MockClient((request) async {
      log.add('${request.method} ${request.url.path}');
      if (request.url.path.endsWith('/sms/test')) {
        return _json(<String, Object?>{'ok': true, 'code': '00', 'message': 'Kimlik doğrulandı.', 'balance': 12.5});
      }
      return _json(status ?? _status());
    }),
  );
  await pumpList(
    t,
    MessagingConnectionsCard(authService: PeopleFakeAuth(), siteCode: 11, canWrite: canWrite, api: api),
    width: width,
    height: 1100,
    scale: 1.0,
    dark: true,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return log;
}

void main() {
  testWidgets('yönetici: SMS bağlantısı maskeli görünür, sınama yalnız /sms/test çağırır; WhatsApp dürüst not; taşma yok', (t) async {
    final log = await _pump(t, canWrite: true);
    expect(find.textContaining('NetGSM · başlık: SITEAPT · kullanıcı: si***'), findsOneWidget);
    expect(find.textContaining('GIZLI'), findsNothing);
    expect(find.text(_waNote), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('messaging_sms_test')), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey<String>('messaging_sms_test')));
    await t.tap(find.byKey(const ValueKey<String>('messaging_sms_test')));
    await settleFor(t, 100);
    expect(log.where((e) => e.startsWith('POST')), <String>['POST /manager/sites/11/messaging/sms/test']);
    expect(find.textContaining('Bakiye: 12.5'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('kurul üyesi: salt okunur, hiçbir yazma düğmesi yok; bağlantı yokken ortak hesap bilgisi', (t) async {
    await _pump(t, canWrite: false, status: _status(sms: false, globalFallback: true));
    expect(find.textContaining('yalnızca görüntüleyebilirsiniz'), findsOneWidget);
    expect(find.text('Şu an platformun ortak SMS hesabı kullanılıyor.'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('messaging_sms_edit')), findsNothing);
    expect(find.byKey(const ValueKey<String>('messaging_wa_edit')), findsNothing);
    expect(find.text(_waNote), findsOneWidget);
  });
}
