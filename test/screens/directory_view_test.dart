// Rehber (sakin) ve bekleyen davet kartı (058): telefona dokununca arama açılır, boş / hata durumları dürüsttür,
// davet kartında Kabul et / Reddet çalışır, dar ekranda büyük yazıda taşma yok.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/views/directory_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/pending_invitations_card.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

class _DirAuth extends PeopleFakeAuth {
  _DirAuth() : super();

  List<DirectorySite> dirSites = <DirectorySite>[
    const DirectorySite(
      siteName: 'Gül Sitesi',
      managers: <String>['Yönetici Kişi'],
      board: <DirectoryPerson>[DirectoryPerson(fullName: 'Selin Arda', label: 'Yönetim kurulu üyesi')],
      staff: <DirectoryPerson>[DirectoryPerson(fullName: 'Hasan Kapıcı', label: 'Kapıcı', phone: '+905321234567')],
      contacts: <DirectoryContact>[
        DirectoryContact(id: 1, label: 'Su arıza', phone: '186', category: 'utility', note: '7/24'),
      ],
    ),
  ];
  Object? directoryError;
  List<PendingInvitation> pending = <PendingInvitation>[
    const PendingInvitation(id: 5, siteName: 'Gül Sitesi', duty: 'doorman'),
  ];
  final List<({int id, bool accept})> answers = <({int id, bool accept})>[];

  @override
  Future<List<DirectorySite>> getDirectory() async {
    final error = directoryError;
    if (error != null) throw error;
    return dirSites;
  }

  @override
  Future<List<PendingInvitation>> listMyInvitations() async => List<PendingInvitation>.of(pending);

  @override
  Future<void> answerInvitation(int invitationId, {required bool accept}) async {
    answers.add((id: invitationId, accept: accept));
    pending = <PendingInvitation>[];
  }
}

Future<void> _pump(WidgetTester t, Widget view) =>
    pumpList(t, view, width: 400, height: 900, scale: 1.0, dark: false);

void main() {
  testWidgets('rehber: yönetim, kurul, görevli ve faydalı telefon; telefona dokununca tel: açılır', (t) async {
    final auth = _DirAuth();
    final launched = <Uri>[];
    await _pump(
      t,
      DirectoryView(
        authService: auth,
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
      ),
    );
    await settleFor(t);
    expect(find.text('Yönetici Kişi'), findsOneWidget);
    expect(find.text('Selin Arda'), findsOneWidget);
    expect(find.text('Hasan Kapıcı'), findsOneWidget);
    expect(find.text('Su arıza'), findsOneWidget);

    await t.tap(find.byTooltip('Ara').first);
    await settleFor(t);
    expect(launched.single.scheme, 'tel');
    expect(launched.single.path, '+905321234567');
  });

  testWidgets('rehber: hata "rehber boş" demez; Tekrar Dene yeniden yükler; hiç site yoksa açıklama', (t) async {
    final auth = _DirAuth()..directoryError = ApiException('Sunucu yanıt vermiyor.');
    await _pump(t, DirectoryView(authService: auth));
    await settleFor(t);
    expect(find.text('Sunucu yanıt vermiyor.'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);

    auth
      ..directoryError = null
      ..dirSites = <DirectorySite>[];
    await t.tap(find.text('Tekrar Dene'));
    await settleFor(t);
    expect(find.textContaining('Yönetim bu özelliği açtığında'), findsOneWidget);
  });

  testWidgets('davet kartı: Kabul et isteği gider, kart kapanır ve onAccepted çağrılır', (t) async {
    final auth = _DirAuth();
    var accepted = 0;
    await _pump(t, PendingInvitationsCard(authService: auth, onAccepted: () => accepted++));
    await settleFor(t);
    expect(find.text('Gül Sitesi sizi davet etti'), findsOneWidget);
    expect(find.textContaining('Kapıcı'), findsOneWidget);
    await t.tap(find.text('Kabul et'));
    await settleFor(t);
    expect(auth.answers.single, (id: 5, accept: true));
    expect(accepted, 1);
    expect(find.text('Gül Sitesi sizi davet etti'), findsNothing);
  });

  testWidgets('davet kartı: Reddet ve davet yoksa kart çizilmez', (t) async {
    final auth = _DirAuth();
    await _pump(t, PendingInvitationsCard(authService: auth));
    await settleFor(t);
    await t.tap(find.text('Reddet'));
    await settleFor(t);
    expect(auth.answers.single, (id: 5, accept: false));

    final none = _DirAuth()..pending = <PendingInvitation>[];
    await _pump(t, PendingInvitationsCard(authService: none));
    await settleFor(t);
    expect(find.byType(FilledButton), findsNothing);
  });

  for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (412, 915, 1.0)]) {
    testWidgets('taşma yok: rehber ve davet ${w.toInt()}x${h.toInt()} yazı $s', (t) async {
      final auth = _DirAuth();
      await pumpList(
        t,
        Column(children: [PendingInvitationsCard(authService: auth), DirectoryView(authService: auth)]),
        width: w,
        height: h,
        scale: s,
        dark: false,
      );
      await settleFor(t);
      expect(t.takeException(), isNull);
    });
  }
}
