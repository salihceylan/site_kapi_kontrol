// Platform: site başvurusu - ekranların başvuru durumunu eşitlemesi (B10).
//
// - Rol değişimi (bireysel <-> daire kullanıcısı): açık ekran durumu `ensureLoaded` ile yeniden yükler; durum
//   1 dakikadan ESKİYSE sunucudan okur, TAZEYSE gereksiz istek atmaz (saat enjekte edilir).
// - Ekranın genel yenilemesi (loadAll) başvuru durumunun tazelik kuralını AŞMAZ (her yenilemede `mine` atılmaz).
// - Form kapanınca durum yalnız başvuru gönderildiyse / zaten bekleyen varsa / sonuç belirsizse okunur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/dialogs/setup_site_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/site_application_flow.dart';
import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart';
import 'package:site_kapi_kontrol/ui/views/join_and_setup_view.dart';

import 'site_application_fixtures.dart';

/// Ana ekran uçları boş dönen sahte servis; başvuru uçları [SiteApplicationFakeAuth]tan.
class _Auth extends SiteApplicationFakeAuth {
  _Auth({super.role});

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async => (<MyApartmentRecord>[], null);
}

class _Clock {
  DateTime now = DateTime.utc(2026, 10, 16, 12);
  DateTime read() => now;
}

SiteApplicationTracker _tracker(_Auth auth, _Clock clock) => SiteApplicationTracker(
  fetch: () => auth.getMySiteApplications(),
  cancel: (id) => auth.cancelSiteApplication(id),
  now: clock.read,
);

Future<void> _host(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(400, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _end(WidgetTester t, SiteApplicationTracker tracker) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
  tracker.dispose();
}

void main() {
  group('B10: rol değişiminde açık ekran başvuru durumunu eşitler', () {
    final key = GlobalKey<IndividualHomeViewState>();

    Widget individual(_Auth auth, SiteApplicationTracker tracker, UserRole role) => IndividualHomeView(
      key: key,
      session: saSession(role),
      authService: auth,
      onRefreshAll: () {},
      applications: tracker,
    );

    testWidgets('IndividualHomeView: durum ESKİYSE (> 1 dk) rol değişimi sunucudan yeniden okutur', (t) async {
      final auth = _Auth(role: UserRole.individual)..seed([saRow(7, status: 'rejected', decisionNote: 'Eksik')]);
      final clock = _Clock();
      final tracker = _tracker(auth, clock);
      await _host(t, individual(auth, tracker, UserRole.individual));
      expect(auth.mineCalls, 1);

      clock.now = clock.now.add(const Duration(minutes: 2));
      await _host(t, individual(auth, tracker, UserRole.apartmentOwner));
      expect(auth.mineCalls, 2, reason: 'eski durum yeniden okundu');
      await _end(t, tracker);
    });

    testWidgets('IndividualHomeView: durum TAZEYSE rol değişimi gereksiz istek atmaz', (t) async {
      final auth = _Auth(role: UserRole.individual);
      final clock = _Clock();
      final tracker = _tracker(auth, clock);
      await _host(t, individual(auth, tracker, UserRole.individual));
      expect(auth.mineCalls, 1);

      clock.now = clock.now.add(const Duration(seconds: 20));
      await _host(t, individual(auth, tracker, UserRole.apartmentOwner));
      expect(auth.mineCalls, 1);
      await _end(t, tracker);
    });

    testWidgets('IndividualHomeView.loadAll (genel yenileme) başvuru durumunun tazelik kuralını AŞMAZ', (t) async {
      final auth = _Auth(role: UserRole.individual);
      final clock = _Clock();
      final tracker = _tracker(auth, clock);
      await _host(t, individual(auth, tracker, UserRole.individual));
      expect(auth.mineCalls, 1);

      final doorCallsBefore = auth.deviceCalls;
      await key.currentState!.loadAll();
      await t.pump();
      expect(auth.deviceCalls, greaterThan(doorCallsBefore), reason: 'ekran verisi yenilendi');
      expect(auth.mineCalls, 1, reason: 'taze başvuru durumu yeniden okunmadı');
      await _end(t, tracker);
    });

    testWidgets('JoinAndSetupView: durum ESKİYSE rol değişimi yeniden okutur; TAZEYSE okutmaz', (t) async {
      final auth = _Auth(role: UserRole.apartmentOwner);
      final clock = _Clock();
      final tracker = _tracker(auth, clock);
      Widget join(UserRole role) => JoinAndSetupView(
        authService: auth,
        session: saSession(role),
        onOpenClaimDevice: () {},
        onOpenJoinSite: () {},
        applications: tracker,
      );
      await _host(t, join(UserRole.apartmentOwner));
      expect(auth.mineCalls, 1);

      clock.now = clock.now.add(const Duration(seconds: 20));
      await _host(t, join(UserRole.individual));
      expect(auth.mineCalls, 1, reason: 'taze');

      clock.now = clock.now.add(const Duration(minutes: 2));
      await _host(t, join(UserRole.apartmentOwner));
      expect(auth.mineCalls, 2, reason: 'eski');
      await _end(t, tracker);
    });
  });

  group('B10: başvuru formu kapanınca durum yalnız gerektiğinde okunur', () {
    for (final (outcome, calls, why) in <(SetupSiteOutcome?, int, String)>[
      (SetupSiteOutcome.applied, 1, 'başvuru gönderildi'),
      (SetupSiteOutcome.uncertain, 1, 'sonuç belirsiz'),
      (SetupSiteOutcome.alreadyPending, 1, 'zaten bekleyen başvuru var'),
      (SetupSiteOutcome.applicationRequired, 1, 'sunucu başvuru istedi'),
      (SetupSiteOutcome.created, 0, 'anlık kurulum: başvuru durumu etkilenmez'),
      (null, 0, 'hiçbir şey gönderilmedi'),
    ]) {
      testWidgets('${outcome ?? 'null'}: mine $calls kez ($why)', (t) async {
        final auth = _Auth(role: UserRole.individual);
        final tracker = _tracker(auth, _Clock());
        syncApplicationsAfterForm(tracker, outcome);
        await t.pump();
        await t.pump(const Duration(milliseconds: 50));
        expect(auth.mineCalls, calls);
        await _end(t, tracker);
      });
    }

    testWidgets('izlenen takipçi yokken (null) hiçbir şey yapılmaz', (t) async {
      expect(() => syncApplicationsAfterForm(null, SetupSiteOutcome.applied), returnsNormally);
    });
  });
}
