// FAZ 5 / A2-G5: ManageJoinRequestsDialog taşma testi (AGENTS.md kural 6).
//
// `Dialog`: başlık şeridi + bekleyen rozeti sabit, başvuru kartları RefreshIndicator'lı listede akar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/dialogs/manage_join_requests_dialog.dart';

import 'dialog_layout_harness.dart';

SiteRecord _site() => SiteRecord.fromJson({
  'id': 101,
  'name': 'Güneş Sitesi Uzun İsimli Konutları Yönetimi',
  'block_count': 2,
  'apartment_count': 20,
  'door_count': 2,
  'approval_status': 'approved',
});

JoinRequestRecord _req(
  int id,
  String status, {
  String? notes,
  String? rejection,
}) => JoinRequestRecord(
  id: id,
  siteCode: 101,
  fullName: 'Ayşe Yılmaz Uzun Soyadlı Başvuran',
  email: 'ayse.yilmaz.uzun.eposta@ornek-alan-adi.example.com',
  phoneNumber: '+90 555 000 00 00',
  blockName: 'A Blok',
  apartmentId: 5,
  unitLabel: 'Daire 12',
  status: status,
  notes: notes,
  rejectionReason: rejection,
  createdAt: DateTime(2026, 1, 1, 10, 30),
);

class _FakeAuth extends AuthService {
  _FakeAuth({this.error, this.requests = const []})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? error;
  final List<JoinRequestRecord> requests;
  final List<int> approved = [];
  final List<(int, String?)> rejected = [];

  @override
  Future<(List<JoinRequestRecord>?, String?)> getSiteJoinRequests({
    required int siteCode,
    String? status,
  }) async {
    if (error != null) return (null, error);
    return (requests, null);
  }

  @override
  Future<(bool, String?)> approveJoinRequest(int requestId) async {
    approved.add(requestId);
    return (true, 'Başvuru onaylandı.');
  }

  @override
  Future<(bool, String?)> rejectJoinRequest(
    int requestId, {
    String? reason,
  }) async {
    rejected.add((requestId, reason));
    return (true, 'Başvuru reddedildi.');
  }
}

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
    (context) => ManageJoinRequestsDialog.show(
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

List<JoinRequestRecord> _mixed() => [
  _req(
    1,
    'PENDING',
    notes: 'Annem adına başvuruyorum, daire kiracı ailesine aittir.',
  ),
  _req(2, 'APPROVED'),
  _req(3, 'REJECTED', rejection: 'Daire sahibi başvuruyu teyit etmedi.'),
];

void main() {
  layoutMatrix(
    'ManageJoinRequestsDialog (bekleyen / onaylı / reddedilen kartlar)',
    (t, width, height, scale, dark) async {
      await _open(
        t,
        _FakeAuth(requests: _mixed()),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(AppDialogHeader), findsOneWidget);
      expect(find.text('Katılım Talepleri'), findsOneWidget);
      expect(find.text('1 Bekleyen'), findsOneWidget);
      expect(find.byTooltip('Yenile'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byType(AppCard), findsAtLeastNWidgets(1));
      expect(find.text('Onay Bekliyor'), findsOneWidget);
      await scrollTo(t, find.text('Onayla'));
      expect(find.text('Reddet'), findsOneWidget);
      // Alttaki (reddedilmiş) karta kadar kaydır.
      await scrollIntoBuilt(
        t,
        find.textContaining('Ret Sebebi:'),
        find.byType(ListView),
      );
      expect(find.byType(StatusChip), findsAtLeastNWidgets(2));
    },
  );

  layoutMatrix('ManageJoinRequestsDialog (reddetme onay penceresi)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final auth = _FakeAuth(requests: [_req(1, 'PENDING')]);
    await _open(
      t,
      auth,
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    await scrollTo(t, find.text('Reddet'));
    await t.tap(find.text('Reddet'));
    await settleFor(t);
    expect(find.text('Katılım Başvurusunu Reddet'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Daire sahibi teyit etmedi.');
    await settleFor(t);
    // Onay penceresindeki "Reddet" (eylem satırı) ve alttaki liste düğmesi: ikisi birden bulunur.
    await t.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Reddet'),
      ),
    );
    await settleFor(t, 800);
    expect(auth.rejected, [(1, 'Daire sahibi teyit etmedi.')]);
  });

  layoutMatrix(
    'ManageJoinRequestsDialog (yüklenemedi: InlineNotice + Tekrar Dene)',
    (t, width, height, scale, dark) async {
      await _open(
        t,
        _FakeAuth(
          error:
              'Katılım talepleri şu an alınamadı; lütfen bağlantınızı kontrol edip yeniden deneyin.',
        ),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      await scrollTo(t, find.text('Tekrar Dene'));
    },
  );

  layoutMatrix('ManageJoinRequestsDialog (talep yok: EmptyState)', (
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

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Henüz katılım talebi bulunmuyor.'), findsOneWidget);
    expect(find.text('Bekleyen'), findsNothing);
  });

  testWidgets(
    'ManageJoinRequestsDialog: onaylayınca servis çağrılır ve başarı bildirimi gösterilir',
    (t) async {
      final auth = _FakeAuth(requests: [_req(1, 'PENDING')]);
      await _open(t, auth, width: 400, height: 900, scale: 1.0, dark: false);

      await t.tap(find.text('Onayla'));
      await settleFor(t, 800);
      expect(auth.approved, [1]);
      expect(find.text('Başvuru onaylandı.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
