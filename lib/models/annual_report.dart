// Faaliyet raporu (`annual_report`) modeli ve bölüm metinleri. Sunucu: server/src/modules/annual_report_routes.js.
// Sistem verisi sunucuda hesaplanır; burada yalnız ham JSON okunur ve her bölüm için sade Türkçe satırlara çevrilir.
import 'package:site_kapi_kontrol/ui/helpers/money.dart' show formatMinor;

/// Bölüm anahtarları, sunucudaki SECTION_KEYS ile aynı sırada.
const List<String> kAnnualReportSections = <String>[
  'general',
  'finance',
  'collections',
  'works',
  'maintenance',
  'contracts',
  'decisions',
  'announcements',
  'forecast',
];

const Map<String, String> kAnnualReportTitles = <String, String>{
  'general': '1. Genel bilgiler',
  'finance': '2. Mali durum (gelir, gider ve bütçe)',
  'collections': '3. Tahsilat ve borçlar',
  'works': '4. Yapılan işler',
  'maintenance': '5. Bakım ve ekipman',
  'contracts': '6. Sözleşmeler',
  'decisions': '7. Kararlar',
  'announcements': '8. Duyurular',
  'forecast': '9. Gelecek yıl tahmini',
};

const int kAnnualReportEditMax = 4000;

class AnnualReport {
  const AnnualReport({
    required this.year,
    required this.sections,
    required this.edits,
    required this.growthBp,
    required this.saved,
    this.updatedAt,
  });

  final int year;
  final Map<String, Map<String, dynamic>> sections;
  final Map<String, String> edits;
  final int growthBp;
  final bool saved;
  final String? updatedAt;

  factory AnnualReport.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'];
    final draft = json['draft'];
    final rawEdits = draft is Map ? draft['edits'] : null;
    return AnnualReport(
      year: (json['year'] as num?)?.toInt() ?? 0,
      sections: <String, Map<String, dynamic>>{
        if (rawSections is Map)
          for (final e in rawSections.entries)
            if (e.value is Map) e.key as String: Map<String, dynamic>.from(e.value as Map),
      },
      edits: <String, String>{
        if (rawEdits is Map)
          for (final e in rawEdits.entries)
            if (e.value is String && (e.value as String).trim().isNotEmpty) e.key as String: e.value as String,
      },
      growthBp: draft is Map ? (draft['growth_bp'] as num?)?.toInt() ?? 0 : 0,
      saved: draft is Map && draft['saved'] == true,
      updatedAt: draft is Map ? draft['updated_at'] as String? : null,
    );
  }
}

int _i(Object? v) => v is num ? v.toInt() : 0;
List<Map<String, dynamic>> _list(Object? v) => <Map<String, dynamic>>[
  if (v is List)
    for (final e in v)
      if (e is Map) Map<String, dynamic>.from(e),
];

String _pct(Object? bp) => bp is num ? '%${(bp / 100).toStringAsFixed(1).replaceAll('.', ',')}' : '-';

const Map<String, String> _workCategory = <String, String>{'ariza': 'Arıza', 'bakim': 'Bakım', 'sikayet_oneri': 'Şikayet/Öneri', 'diger': 'Diğer'};
const Map<String, String> _contractCategory = <String, String>{
  'asansor': 'Asansör',
  'guvenlik': 'Güvenlik',
  'temizlik': 'Temizlik',
  'bahce': 'Bahçe',
  'havuz': 'Havuz',
  'teknik_bakim': 'Teknik bakım',
  'yazilim': 'Yazılım',
  'sigorta': 'Sigorta',
  'diger': 'Diğer',
};
const Map<String, String> _vote = <String, String>{'kabul': 'Kabul', 'ret': 'Ret', 'ertelendi': 'Ertelendi', 'bilgi': 'Bilgi'};

/// Bölümün sistem taslağı: sade Türkçe satırlar. Modül kapalıysa tek satırlık açıklama.
List<String> annualReportLines(String key, Map<String, dynamic>? s) {
  if (s == null || s['available'] != true) {
    return const <String>['Bu bölüm için gerekli modül bu sitede kapalı; kayıt yok.'];
  }
  switch (key) {
    case 'general':
      return <String>[
        'Site: ${s['site_name'] ?? ''}',
        'Blok sayısı: ${_i(s['block_count'])}, aktif daire sayısı: ${_i(s['apartment_count'])}',
      ];
    case 'finance':
      final budget = s['budget'];
      return <String>[
        'Toplam tahsilat (gelir): ${formatMinor(_i(s['income_minor']))}',
        'Toplam gider: ${formatMinor(_i(s['expense_minor']))}',
        'Net kasa farkı: ${formatMinor(_i(s['net_minor']))}',
        for (final c in _list(s['expense_by_category'])) 'Gider - ${c['category_name']}: ${formatMinor(_i(c['total_minor']))}',
        if (budget is Map) ...<String>[
          'İşletme projesi (${budget['status']}): planlanan ${formatMinor(_i((budget['totals'] as Map?)?['planned_minor']))}, '
              'gerçekleşen ${formatMinor(_i((budget['totals'] as Map?)?['actual_minor']))}',
          for (final r in _list(budget['rows']))
            '${r['category_name']}: planlanan ${formatMinor(_i(r['planned_minor']))}, gerçekleşen ${formatMinor(_i(r['actual_minor']))}',
        ] else
          'Bu yıl için işletme projesi (bütçe) kaydı yok.',
      ];
    case 'collections':
      return <String>[
        'Tahakkuk: ${formatMinor(_i(s['charged_minor']))}, tahsilat: ${formatMinor(_i(s['collected_minor']))} (${_pct(s['collection_rate_bp'])})',
        'Yıl sonu açık borç: ${formatMinor(_i(s['open_debt_minor']))} (${_i(s['debtor_apartment_count'])} daire)',
        'Yıl sonu avans/alacak: ${formatMinor(_i(s['open_credit_minor']))}',
      ];
    case 'works':
      final cats = _list(s['by_category']);
      final closed = _list(s['closed_items']);
      return <String>[
        'Açılan kayıt: ${_i(s['total'])}, çözülen/kapanan: ${_i(s['done'])}, fotoğraf: ${_i(s['photo_count'])}',
        for (final c in cats) '${_workCategory[c['category']] ?? c['category']}: ${_i(c['total'])} kayıt, ${_i(c['done'])} tamamlandı',
        for (final w in closed) '- ${w['title']} (${w['closed_on'] ?? ''}${_i(w['photo_count']) > 0 ? ', ${_i(w['photo_count'])} fotoğraf' : ''})',
      ];
    case 'maintenance':
      final wi = s['work_items'];
      final cs = _list(s['contracts']);
      return <String>[
        if (wi is Map) 'Bakım kaydı: ${_i(wi['total'])}, tamamlanan: ${_i(wi['done'])}',
        for (final c in cs) 'Bakım sözleşmesi: ${c['title']} (${_contractCategory[c['category']] ?? c['category']}) - ${c['vendor_name']}',
        'Ekipman envanteri: Yakında…',
      ];
    case 'contracts':
      final items = _list(s['items']);
      return <String>[
        'Yıl içinde geçerli sözleşme: ${items.length}',
        for (final c in items)
          '${c['title']} (${_contractCategory[c['category']] ?? c['category']}) - ${c['vendor_name']}, ${c['start_date']} / ${c['end_date'] ?? 'süresiz'}'
              '${c['amount_minor'] == null ? '' : ', ${formatMinor(_i(c['amount_minor']))}'}${c['status'] == 'feshedildi' ? ' (feshedildi)' : ''}',
      ];
    case 'decisions':
      return <String>[
        'Kesinleşen karar sayısı: ${_i(s['total'])}',
        for (final d in _list(s['items']))
          '${d['decision_no'] == null ? '' : 'No ${d['decision_no']} - '}${d['title']} (${d['meeting_date']}, ${_vote[d['vote_result']] ?? d['vote_result']})',
      ];
    case 'announcements':
      return <String>[
        'Yayımlanan duyuru: ${_i(s['total'])}',
        for (final a in _list(s['items'])) '${a['published_on']} - ${a['title']}',
      ];
    case 'forecast':
      return <String>[
        '${_i(s['next_year'])} yılı için beklenen gider: ${formatMinor(_i(s['expected_expense_minor']))} '
            '(bu yılın gideri ${formatMinor(_i(s['base_expense_minor']))}, artış ${_pct(s['growth_bp'])})',
        if (s['next_year_budget_minor'] != null) '${_i(s['next_year'])} işletme projesi toplamı: ${formatMinor(_i(s['next_year_budget_minor']))}',
      ];
  }
  return const <String>[];
}

/// PDF ve ekran için bölümün son metni: yönetici düzenlediyse o, yoksa sistem taslağı satırları.
List<String> annualReportFinalLines(AnnualReport report, String key) {
  final edited = report.edits[key];
  if (edited != null && edited.trim().isNotEmpty) return edited.split('\n');
  return annualReportLines(key, report.sections[key]);
}
