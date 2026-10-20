// Kurallar tablosu (G11) istemci testlerinin örnek sunucu yanıtı: 15 kural, sözleşme sırasıyla (docs/PLATFORM_KURALLAR.md).
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.

Map<String, dynamic> _value(Object? value, {String source = 'default', String? validFrom, String? by, String? note}) => <String, dynamic>{
  'value': value,
  'source': source,
  'valid_from': validFrom,
  'note': note,
  'updated_at': validFrom == null ? null : '${validFrom}T08:00:00.000Z',
  'updated_by_name': by,
};

Map<String, dynamic> _rule(
  String key, {
  required String label,
  String type = 'int',
  String? unit,
  bool nullable = false,
  int? min,
  int? max,
  required Object? defaultValue,
  bool siteOverridable = false,
  bool schedulable = true,
  bool editable = true,
  String? lockedReason,
  Map<String, dynamic>? pair,
  Map<String, dynamic>? platform,
  Map<String, dynamic>? site,
  Map<String, dynamic>? effective,
  List<Map<String, dynamic>> scheduled = const <Map<String, dynamic>>[],
}) {
  final platformValue = platform ?? _value(defaultValue);
  return <String, dynamic>{
    'key': key,
    'group': key.substring(0, key.indexOf('.')),
    'label': label,
    'description': '$label açıklaması.',
    'type': type,
    'unit': unit,
    'nullable': nullable,
    'min': min,
    'max': max,
    'default': defaultValue,
    'site_overridable': siteOverridable,
    'schedulable': schedulable,
    'editable': editable,
    'locked_reason': lockedReason,
    'pair': pair,
    'legal_note': key.startsWith('finance.') ? 'KMK 634 m.20/2: aylık yüzde beş. [AVUKAT DOĞRULASIN]' : 'Karar notu. [AVUKAT DOĞRULASIN]',
    'platform': platformValue,
    'site': site,
    'effective': effective ??
        <String, dynamic>{'value': platformValue['value'], 'source': platformValue['source'], 'valid_from': platformValue['valid_from']},
    'scheduled': scheduled,
  };
}

/// Örnek `GET /admin/rules` (ya da yönetici ucu) gövdesi. [siteCode] verilirse site görünümü (tahmin artışı siteye özel 2.500 bp).
Map<String, dynamic> prRulesJson({int? siteCode, String? siteName, bool canEdit = true, int lateFeeMax = 400}) {
  final siteScope = siteCode != null;
  return <String, dynamic>{
    'on_date': '2026-10-21',
    'site': siteScope ? <String, dynamic>{'site_code': siteCode, 'site_name': siteName} : null,
    'can_edit': canEdit,
    'groups': <Map<String, dynamic>>[
      <String, dynamic>{'code': 'finance', 'label': 'Finans'},
      <String, dynamic>{'code': 'budget', 'label': 'İşletme projesi (bütçe)'},
      <String, dynamic>{'code': 'heat', 'label': 'Isınma gideri payı'},
      <String, dynamic>{'code': 'forecast', 'label': 'Gelecek yıl tahmini'},
      <String, dynamic>{'code': 'retention', 'label': 'Saklama süreleri'},
    ],
    'items': <Map<String, dynamic>>[
      _rule(
        'finance.late_fee.monthly_bp_max',
        label: 'Gecikme tazminatı aylık üst sınırı',
        unit: 'bp',
        min: 0,
        max: 500,
        defaultValue: 500,
        schedulable: false,
        platform: _value(lateFeeMax, source: 'platform', validFrom: '2026-10-21', by: canEdit ? 'Süper Kişi' : null, note: 'Kurul kararı'),
      ),
      _rule('budget.provisional_max_days', label: 'Geçici işletme projesi en uzun süresi', unit: 'days', min: 1, max: 90, defaultValue: 90),
      _rule(
        'budget.objection_days',
        label: 'İşletme projesine itiraz süresi',
        unit: 'days',
        min: 1,
        max: 30,
        defaultValue: 7,
        scheduled: <Map<String, dynamic>>[
          <String, dynamic>{'scope': 'platform', 'value': 10, 'inherit': false, 'valid_from': '2026-11-20', 'note': null},
        ],
      ),
      _rule('heat.measured_share_pct', label: 'Isınma gideri: ölçüme göre pay', unit: 'pct', min: 0, max: 100, defaultValue: 70,
          pair: <String, dynamic>{'key': 'heat.area_share_pct', 'sum': 100}),
      _rule('heat.area_share_pct', label: 'Isınma gideri: alana göre pay', unit: 'pct', min: 0, max: 100, defaultValue: 30,
          pair: <String, dynamic>{'key': 'heat.measured_share_pct', 'sum': 100}),
      _rule(
        'forecast.default_increase_bp',
        label: 'Gelecek yıl tahmini: varsayılan artış oranı',
        unit: 'bp',
        min: 0,
        max: 10000,
        defaultValue: 0,
        siteOverridable: true,
        site: siteScope ? _value(2500, source: 'site', validFrom: '2026-10-21', by: canEdit ? 'Süper Kişi' : null) : null,
        effective: siteScope ? <String, dynamic>{'value': 2500, 'source': 'site', 'valid_from': '2026-10-21'} : null,
      ),
      _rule('retention.finance_days', label: 'Mali kayıtlar', unit: 'days', min: 1825, max: 7300, defaultValue: 3650),
      _rule('retention.contact_after_moveout_days', label: 'Taşınan kişinin iletişim bilgileri', unit: 'days', min: 30, max: 3650, defaultValue: 365),
      _rule('retention.door_logs_days', label: 'Kapı geçiş kayıtları', unit: 'days', min: 30, max: 3650, defaultValue: 365),
      _rule('retention.visitor_logs_days', label: 'Ziyaretçi ve kargo kayıtları', unit: 'days', min: 30, max: 3650, defaultValue: 365),
      _rule('retention.work_photos_after_close_days', label: 'İş takibi fotoğrafları (talep kapandıktan sonra)', unit: 'days', min: 30, max: 3650,
          defaultValue: 730),
      _rule('retention.announcements_days', label: 'Duyurular', unit: 'days', min: 365, max: 3650, defaultValue: 1825),
      _rule('retention.audit_days', label: 'Denetim kaydı', unit: 'days', min: 365, max: 3650, defaultValue: 1825),
      _rule('retention.decision_book_days', label: 'Karar defteri', unit: 'days', nullable: true, min: 3650, max: 36500, defaultValue: null),
      _rule(
        'retention.enforce',
        label: 'Otomatik silme',
        type: 'bool',
        defaultValue: false,
        editable: false,
        lockedReason: 'Otomatik silme avukat onayına kadar kapalıdır; bu kural şimdilik değiştirilemez.',
      ),
    ],
  };
}
