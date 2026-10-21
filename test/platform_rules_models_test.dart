// Kurallar tablosu modeli (G11; docs/PLATFORM_KURALLAR.md): sunucu yanıtının ayrıştırılması, değer / sınır / tarih biçimleme, giriş ayrıştırma ve
// doğrulama, değişiklik gövdesi, denetim kaydı etiketleri.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/platform_rule.dart';

import 'fixtures/platform_rules_fixtures.dart';

void main() {
  group('ayrıştırma', () {
    test('liste gövdesi: tarih, kapsam, düzenleme izni, gruplar, kurallar (meta + platform / site / etkin / planlı)', () {
      final view = PlatformRulesView.fromJson(prRulesJson(siteCode: 1000000001, siteName: 'Gül Sitesi', canEdit: false));
      expect(view.onDate, '2026-10-21');
      expect(view.siteCode, 1000000001);
      expect(view.siteName, 'Gül Sitesi');
      expect(view.canEdit, isFalse);
      expect(view.isSiteScope, isTrue);
      expect(view.groups.map((g) => g.code), <String>['finance', 'budget', 'heat', 'forecast', 'retention']);
      expect(view.items, hasLength(15));
      final late = view.byKey('finance.late_fee.monthly_bp_max')!;
      expect(late.label, 'Gecikme tazminatı aylık üst sınırı');
      expect(late.type, PlatformRuleType.integer);
      expect(late.unit, PlatformRuleUnit.basisPoints);
      expect(late.min, 0);
      expect(late.max, 500);
      expect(late.defaultValue, 500);
      expect(late.siteOverridable, isFalse);
      expect(late.schedulable, isFalse);
      expect(late.editable, isTrue);
      expect(late.legalNote, contains('KMK'));
      expect(late.effective.value, 400);
      expect(late.effective.source, PlatformRuleSource.platform);
      expect(late.effective.validFrom, '2026-10-21');
      expect(late.platform.updatedByName, isNull, reason: 'yönetici görünümünde değiştirenin adı gelmez');
      expect(late.platform.note, 'Kurul kararı');
      expect(PlatformRulesView.fromJson(prRulesJson()).byKey('finance.late_fee.monthly_bp_max')!.platform.updatedByName, 'Süper Kişi');
      expect(late.scheduled, isEmpty);
      final forecast = view.byKey('forecast.default_increase_bp')!;
      expect(forecast.site!.value, 2500);
      expect(forecast.effective.source, PlatformRuleSource.site);
      final objection = view.byKey('budget.objection_days')!;
      expect(objection.scheduled.single.validFrom, '2026-11-20');
      expect(objection.scheduled.single.value, 10);
      expect(objection.scheduled.single.isSite, isFalse);
      final heat = view.byKey('heat.measured_share_pct')!;
      expect(heat.pair!.key, 'heat.area_share_pct');
      expect(heat.pair!.sum, 100);
      final enforce = view.byKey('retention.enforce')!;
      expect(enforce.type, PlatformRuleType.boolean);
      expect(enforce.editable, isFalse);
      expect(enforce.lockedReason, contains('avukat'));
      final book = view.byKey('retention.decision_book_days')!;
      expect(book.nullable, isTrue);
      expect(book.effective.value, isNull);
      expect(view.itemsIn('heat').map((r) => r.key), <String>['heat.measured_share_pct', 'heat.area_share_pct']);
    });

    test('eksik / bozuk alanlar güvenli varsayılanlara düşer (çökme yok); bilinmeyen kaynak varsayılan sayılır', () {
      final view = PlatformRulesView.fromJson(<String, dynamic>{
        'items': <Object?>[
          <String, dynamic>{'key': 'x.y', 'type': 'garip', 'effective': <String, dynamic>{'value': '5', 'source': 'baska'}},
          'bozuk',
        ],
      });
      expect(view.items, hasLength(1));
      final rule = view.items.single;
      expect(rule.type, PlatformRuleType.integer);
      expect(rule.unit, PlatformRuleUnit.none);
      expect(rule.effective.source, PlatformRuleSource.fallback);
      expect(rule.effective.value, isNull, reason: 'metin sayı sayılmaz');
      expect(rule.scheduled, isEmpty);
      expect(view.canEdit, isFalse);
      expect(view.siteCode, isNull);
      expect(view.groups, isEmpty);
    });

    test('yazma yanıtı changed listesini taşır', () {
      final view = PlatformRulesView.fromJson(<String, dynamic>{...prRulesJson(), 'changed': <Object?>['budget.objection_days']});
      expect(view.changed, <String>['budget.objection_days']);
    });
  });

  group('biçimleme', () {
    final view = PlatformRulesView.fromJson(prRulesJson());
    PlatformRule rule(String key) => view.byKey(key)!;

    test('baz puan yüzde iki ondalıkla, yüzde tam sayıyla, gün binlik ayraçla ve tam yılsa yıl ile; süresiz; açık / kapalı', () {
      expect(formatRuleValue(rule('finance.late_fee.monthly_bp_max'), 500), '%5,00');
      expect(formatRuleValue(rule('finance.late_fee.monthly_bp_max'), 450), '%4,50');
      expect(formatRuleValue(rule('finance.late_fee.monthly_bp_max'), 5), '%0,05');
      expect(formatRuleValue(rule('forecast.default_increase_bp'), 10000), '%100,00');
      expect(formatRuleValue(rule('heat.measured_share_pct'), 70), '%70');
      expect(formatRuleValue(rule('retention.finance_days'), 3650), '3.650 gün (10 yıl)');
      expect(formatRuleValue(rule('retention.work_photos_after_close_days'), 730), '730 gün (2 yıl)');
      expect(formatRuleValue(rule('budget.provisional_max_days'), 90), '90 gün');
      expect(formatRuleValue(rule('retention.decision_book_days'), null), 'Süresiz');
      expect(formatRuleValue(rule('retention.decision_book_days'), 36500), '36.500 gün (100 yıl)');
      expect(formatRuleValue(rule('retention.enforce'), false), 'Kapalı');
      expect(formatRuleValue(rule('retention.enforce'), true), 'Açık');
      expect(formatRuleValue(rule('budget.objection_days'), 'x'), '-');
    });

    test('sınır metni; tarih GG.AA.YYYY; kaynak etiketleri', () {
      expect(formatRuleRange(rule('finance.late_fee.monthly_bp_max')), '%0,00 ile %5,00 arasında');
      expect(formatRuleRange(rule('retention.contact_after_moveout_days')), '30 ile 3.650 gün arasında');
      expect(formatRuleRange(rule('heat.area_share_pct')), '%0 ile %100 arasında');
      expect(formatRuleRange(rule('retention.enforce')), '');
      expect(formatRuleDate('2026-10-21'), '21.10.2026');
      expect(formatRuleDate(null), '-');
      expect(formatRuleDate('bozuk'), '-');
      expect(ruleSourceLabel(PlatformRuleSource.site), 'Bu siteye özel');
      expect(ruleSourceLabel(PlatformRuleSource.platform), 'Platform değeri');
      expect(ruleSourceLabel(PlatformRuleSource.fallback), 'Varsayılan');
    });
  });

  group('giriş ayrıştırma ve doğrulama', () {
    final view = PlatformRulesView.fromJson(prRulesJson());
    PlatformRule rule(String key) => view.byKey(key)!;

    test('baz puan: yüzde metni (virgül ya da nokta, en çok 2 ondalık, isteğe bağlı %) -> tam baz puan (kayan nokta yok)', () {
      final late = rule('finance.late_fee.monthly_bp_max');
      expect(parseRuleInput(late, '5'), 500);
      expect(parseRuleInput(late, '5,00'), 500);
      expect(parseRuleInput(late, '4,5'), 450);
      expect(parseRuleInput(late, '4.25'), 425);
      expect(parseRuleInput(late, ' %0,05 '), 5);
      for (final bad in <String>['', '5,001', '-1', 'abc', '5,0,0', '1e2', '٥']) {
        expect(parseRuleInput(late, bad), isNull, reason: bad);
      }
    });

    test('gün ve yüzde: tam sayı (gün binlik ayraçlı olabilir)', () {
      expect(parseRuleInput(rule('retention.finance_days'), '3.650'), 3650);
      expect(parseRuleInput(rule('retention.finance_days'), '3650'), 3650);
      expect(parseRuleInput(rule('heat.measured_share_pct'), '65'), 65);
      expect(parseRuleInput(rule('heat.measured_share_pct'), '65,5'), isNull);
      expect(parseRuleInput(rule('budget.objection_days'), '7 gün'), isNull);
    });

    test('doğrulama: boş, biçim ve sınır hataları Türkçe; geçerli değer null', () {
      final late = rule('finance.late_fee.monthly_bp_max');
      expect(validateRuleInput(late, ''), 'Bir değer girin.');
      expect(validateRuleInput(late, 'abc'), 'Oranı yüzde olarak girin (örn. 4,50).');
      expect(validateRuleInput(late, '5,01'), 'Değer %0,00 ile %5,00 arasında olmalıdır.');
      expect(validateRuleInput(late, '4,50'), isNull);
      expect(validateRuleInput(rule('budget.objection_days'), '0'), 'Değer 1 ile 30 gün arasında olmalıdır.');
      expect(validateRuleInput(rule('budget.objection_days'), 'yedi'), 'Gün sayısını tam sayı olarak girin.');
      expect(validateRuleInput(rule('heat.measured_share_pct'), '101'), 'Değer %0 ile %100 arasında olmalıdır.');
      expect(validateRuleInput(rule('heat.measured_share_pct'), 'x'), 'Yüzdeyi tam sayı olarak girin.');
    });

    test('düzenleme kapsamı: kilitli kural hiçbir yerde; sitede değişemeyen kural site kapsamında değil', () {
      expect(rule('retention.enforce').editableIn(siteScope: false), isFalse);
      expect(rule('finance.late_fee.monthly_bp_max').editableIn(siteScope: false), isTrue);
      expect(rule('finance.late_fee.monthly_bp_max').editableIn(siteScope: true), isFalse);
      expect(rule('forecast.default_increase_bp').editableIn(siteScope: true), isTrue);
    });
  });

  group('değişiklik gövdesi ve denetim kaydı', () {
    test('değer ya da "üst düzeye dön" (inherit); süresiz null değer olarak gider', () {
      expect(const PlatformRuleChange(key: 'budget.objection_days', value: 9).toJson(), <String, Object?>{'key': 'budget.objection_days', 'value': 9});
      expect(const PlatformRuleChange(key: 'retention.decision_book_days', value: null).toJson(), <String, Object?>{'key': 'retention.decision_book_days', 'value': null});
      expect(const PlatformRuleChange.inherit('forecast.default_increase_bp').toJson(), <String, Object?>{'key': 'forecast.default_increase_bp', 'inherit': true});
    });

    test('platform_rule.updated etiketi ve hedef (kural adı + kapsam); ham anahtar bilinmiyorsa "Kural"', () {
      final entry = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 1,
        'action': 'platform_rule.updated',
        'target_type': 'platform_rule',
        'target_id': 'finance.late_fee.monthly_bp_max',
        'details': <String, dynamic>{'scope': 'platform', 'from': 500, 'to': 400},
      });
      expect(entry.actionLabel, 'Kural değeri güncellendi');
      expect(entry.targetLabel, 'Gecikme tazminatı aylık üst sınırı • Platform geneli');
      final site = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 2,
        'action': 'platform_rule.updated',
        'target_type': 'platform_rule',
        'target_id': 'yeni.kural',
        'details': <String, dynamic>{'scope': 'site'},
      });
      expect(site.targetLabel, 'Kural • Site');
    });
  });
}
