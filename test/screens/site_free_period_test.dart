// Kampanya "şimdi abone olana 2 ay ücretsiz" (sunucu 114), istemci tarafı: SiteRecord alanları + site kartı.
// Süper kullanıcı: başlıkta rozet (sürüyorsa yeşil "Ücretsiz dönem: GG.AA.YYYY tarihine kadar", bittiyse gri "Ücretsiz dönem bitti").
// Site yöneticisi: rozet yok, küçük bilgi satırı. Eski sunucu (alan yok) hiçbir şey göstermez. Fiyat rakamı yoktur.
// Kural 6: tüm ölçü / tema hücrelerinde taşma yok.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_card.dart';

import 'list_fixtures.dart';

SiteRecord _site(Map<String, dynamic> extra) => SiteRecord.fromJson(<String, dynamic>{
      'id': 7,
      'name': 'Gül Sitesi',
      'manager_name': 'Ayşe Yılmaz',
      'created_at': '2026-10-01T12:30:00Z',
      ...extra,
    });

const Map<String, dynamic> _active = <String, dynamic>{
  'subscription_started_at': '2026-10-29',
  'free_until': '2026-12-29',
  'free_period_state': 'active',
  'free_period_days_left': 61,
};
const Map<String, dynamic> _ended = <String, dynamic>{
  'subscription_started_at': '2026-06-01',
  'free_until': '2026-08-01',
  'free_period_state': 'ended',
};

SiteCard _card(SiteRecord site, {required bool isSuperUser}) => SiteCard(
      site: site,
      selected: false,
      formattedCreatedAt: '01.10.2026 12:30',
      deleteBusy: false,
      approvalBusy: false,
      onTap: () {},
      isSuperUser: isSuperUser,
    );

void main() {
  group('SiteRecord: ücretsiz dönem alanları', () {
    test('eski sunucu (alan yok): none, rozet ve not yok', () {
      final site = _site(const <String, dynamic>{});
      expect(site.freePeriodState, 'none');
      expect(site.freeUntil, isNull);
      expect(site.subscriptionStartedAt, isNull);
      expect(site.freePeriodBadgeLabel, isNull);
      expect(site.freePeriodManagerNote, isNull);
    });

    test('sürüyor: tarih GG.AA.YYYY, kalan gün; son gün "(son gün)"', () {
      final site = _site(_active);
      expect(site.hasActiveFreePeriod, isTrue);
      expect(site.freeUntil, DateTime(2026, 12, 29));
      expect(site.subscriptionStartedAt, DateTime(2026, 10, 29));
      expect(site.freePeriodBadgeLabel, 'Ücretsiz dönem: 29.12.2026 tarihine kadar');
      expect(site.freePeriodManagerNote, 'Ücretsiz dönem: 29.12.2026 tarihine kadar (61 gün kaldı)');
      final lastDay = _site(<String, dynamic>{..._active, 'free_period_days_left': 0});
      expect(lastDay.freePeriodManagerNote, 'Ücretsiz dönem: 29.12.2026 tarihine kadar (son gün)');
    });

    test('bitti: gri rozet metni ve yönetici notu; bozuk tarih / null güvenle yok sayılır', () {
      final site = _site(_ended);
      expect(site.hasEndedFreePeriod, isTrue);
      expect(site.freePeriodBadgeLabel, 'Ücretsiz dönem bitti');
      expect(site.freePeriodManagerNote, 'Ücretsiz dönem sona erdi.');
      final broken = _site(const <String, dynamic>{'free_until': 'bozuk', 'free_period_state': 'active'});
      expect(broken.freeUntil, isNull);
      expect(broken.freePeriodBadgeLabel, isNull);
      expect(_site(const <String, dynamic>{'free_until': null}).freePeriodBadgeLabel, isNull);
    });

    test('copyWith kampanya alanlarını taşır', () {
      final copy = _site(_active).copyWith(name: 'Yeni Ad');
      expect(copy.freeUntil, DateTime(2026, 12, 29));
      expect(copy.freePeriodState, 'active');
      expect(copy.freePeriodDaysLeft, 61);
    });
  });

  group('Site kartı: ücretsiz dönem', () {
    listMatrix('süper: yeşil / gri rozet; yönetici: yalnız bilgi satırı; eski sitede hiçbiri', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      await pumpList(
        t,
        Column(
          children: [
            _card(_site(_active), isSuperUser: true),
            const SizedBox(height: 12),
            _card(_site(<String, dynamic>{..._ended, 'id': 8, 'name': 'Lale Sitesi'}), isSuperUser: true),
            const SizedBox(height: 12),
            _card(_site(<String, dynamic>{..._active, 'id': 9, 'name': 'Papatya Sitesi'}), isSuperUser: false),
            const SizedBox(height: 12),
            _card(_site(<String, dynamic>{'id': 10, 'name': 'Eski Site'}), isSuperUser: true),
          ],
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.widgetWithText(StatusChip, 'Ücretsiz dönem: 29.12.2026 tarihine kadar'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Ücretsiz dönem bitti'), findsOneWidget);
      expect(find.byKey(const ValueKey('site-free-period-note')), findsOneWidget);
      expect(find.text('Ücretsiz dönem: 29.12.2026 tarihine kadar (61 gün kaldı)'), findsOneWidget);
    });
  });
}
