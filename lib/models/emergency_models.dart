// Acil durum akışı (P2-24, karar K13): sunucu 107 (GET /app/emergency, PUT /manager/sites/:siteCode/emergency) modelleri ile
// ekranın içeriği (senaryolar, çağrı merkezinin soracakları, kopyalanabilir metin). SAF Dart: Flutter bağımlılığı yok, içerik testle kilitlidir.
//
// Dürüstlük kuralı: bu dosya hiçbir yerde "arandı" demez. Arama kanalı yoksa (kuru mod) numara ve adres metin olarak verilir.

/// Acil çağrı merkezi: polis, ambulans ve itfaiye için tek numara (karar K13).
const String kEmergencyNumber = '112';

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Türkçe büyük/küçük harf farkını gözetmeyen karşılaştırma anahtarı (İ/I, ı/i).
String _fold(String value) => value.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// `tel:` adresi için telefon metni ("+90 212 555 12 34" -> "+902125551234", "444 1 234" -> "4441234"); 3 haneden azsa null.
String? emergencyDialable(String? phone) {
  final value = (phone ?? '').trim();
  if (value.isEmpty) return null;
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 3) return null;
  return value.startsWith('+') ? '+$digits' : digits;
}

/// Bir sitenin acil durum bilgisi (`GET /app/emergency` -> `sites[]`).
class EmergencySite {
  const EmergencySite({
    required this.siteCode,
    required this.siteName,
    this.address,
    this.city,
    this.district,
    this.elevatorFirmName,
    this.elevatorFirmPhone,
    this.canEdit = false,
  });

  factory EmergencySite.fromJson(Map<String, dynamic> json) => EmergencySite(
    siteCode: (json['site_code'] as num?)?.toInt() ?? 0,
    siteName: _text(json['site_name']) ?? '',
    address: _text(json['address']),
    city: _text(json['city']),
    district: _text(json['district']),
    elevatorFirmName: _text(json['elevator_firm_name']),
    elevatorFirmPhone: _text(json['elevator_firm_phone']),
    canEdit: json['can_edit'] == true,
  );

  final int siteCode;
  final String siteName;
  final String? address;
  final String? city;
  final String? district;

  /// Site ayarındaki asansör bakım firması (acil arıza hattı); tanımlı değilse null.
  final String? elevatorFirmName;
  final String? elevatorFirmPhone;

  /// Sunucuya göre çağıran bu sitenin YÖNETİCİSİ (kurul, görevli ve sakin değil). Ekranda ayrıca yönetici modu aranır.
  final bool canEdit;

  /// Kullanıcıya görünen ad; ad boşsa teknik site kodu gösterilmez.
  String get label => siteName.trim().isEmpty ? 'İsimsiz site' : siteName.trim();

  /// "Atatürk Mah. 12. Sok. No: 5, Kadıköy / İstanbul"; adres, ilçe ve il yoksa null. Satır sonları virgüle çevrilir; adres ilçeyi ve ili
  /// zaten içeriyorsa ikinci kez eklenmez.
  String? get addressLine {
    final street = address?.split(RegExp(r'\s*[\r\n]+\s*')).where((p) => p.trim().isNotEmpty).join(', ');
    final place = <String>[?district, ?city];
    final streetFold = street == null ? '' : _fold(street);
    final placeCovered = street != null && place.every((p) => streetFold.contains(_fold(p)));
    final locality = place.isEmpty || placeCovered ? null : place.join(' / ');
    final parts = <String>[?street, ?locality];
    return parts.isEmpty ? null : parts.join(', ');
  }

  bool get hasAddress => addressLine != null;

  /// Aranabilir bir bakım firması telefonu var mı?
  bool get hasElevatorFirm => emergencyDialable(elevatorFirmPhone) != null;

  /// Bakım firmasının görünen adı ("Asansör bakım firması" adı yazılmamışsa genel ad).
  String get elevatorFirmLabel => elevatorFirmName ?? 'Asansör bakım firması';

  EmergencySite withElevatorFirm({String? name, String? phone}) => EmergencySite(
    siteCode: siteCode,
    siteName: siteName,
    address: address,
    city: city,
    district: district,
    elevatorFirmName: _text(name),
    elevatorFirmPhone: _text(phone),
    canEdit: canEdit,
  );

  @override
  bool operator ==(Object other) =>
      other is EmergencySite &&
      other.siteCode == siteCode &&
      other.siteName == siteName &&
      other.address == address &&
      other.city == city &&
      other.district == district &&
      other.elevatorFirmName == elevatorFirmName &&
      other.elevatorFirmPhone == elevatorFirmPhone &&
      other.canEdit == canEdit;

  @override
  int get hashCode => Object.hash(siteCode, siteName, address, city, district, elevatorFirmName, elevatorFirmPhone, canEdit);
}

/// Hızlı düğmeler: genel acil durum (112), yangın ve asansör arızası.
enum EmergencyScenario { general, fire, elevator }

/// Bir senaryonun sabit içeriği: kısa yönlendirme, aramada ilk söylenecek cümle ve çağrı merkezinin sorabilecekleri.
class EmergencyGuide {
  const EmergencyGuide({
    required this.scenario,
    required this.title,
    required this.scriptTitle,
    required this.summary,
    required this.steps,
    required this.sayLine,
    required this.questions,
  });

  final EmergencyScenario scenario;
  final String title;

  /// Kopyalanan metnin başlığı (büyük harf, Türkçe harflerle elle yazılmıştır).
  final String scriptTitle;

  /// Başlığın altındaki tek cümlelik açıklama.
  final String summary;

  /// Aramadan önce yapılacaklar (boş olabilir).
  final List<String> steps;

  /// Aramada ilk söylenecek cümle.
  final String sayLine;

  /// Çağrı merkezinin ya da bakım firmasının sorabilecekleri; sırayla.
  final List<String> questions;
}

const String _addressQuestion = 'Adres: site adı, mahalle, cadde veya sokak, bina ve kapı numarası';
const String _contactQuestion = 'Adınız ve geri aranabileceğiniz telefon numarası';

const Map<EmergencyScenario, EmergencyGuide> _guides = <EmergencyScenario, EmergencyGuide>{
  EmergencyScenario.general: EmergencyGuide(
    scenario: EmergencyScenario.general,
    title: 'Aramaya hazırlanın',
    scriptTitle: 'ACİL DURUM - 112',
    summary: 'Çağrı bitene kadar hatta kalın; sorulara sakin ve açık cevap verin.',
    steps: <String>[],
    sayLine: 'Acil bir durum var.',
    questions: <String>[
      'Ne oldu? (hasta ya da yaralı, yangın, hırsızlık, kavga, kaza)',
      _addressQuestion,
      'Blok, kat ve daire numarası',
      'Kaç kişi etkilendi? Bilinci açık mı, nefes alıyor mu?',
      _contactQuestion,
    ],
  ),
  EmergencyScenario.fire: EmergencyGuide(
    scenario: EmergencyScenario.fire,
    title: 'Yangın',
    scriptTitle: 'ACİL DURUM - YANGIN',
    summary: 'Yangında itfaiye de 112 üzerinden çağrılır.',
    steps: <String>[
      'Önce can güvenliği: bulunduğunuz yeri terk edin, asansör kullanmayın, merdivenden inin.',
      'Kapıları kapatarak çıkın; içeri geri dönmeyin.',
      'Güvenli bir yere geçince 112\'yi arayın.',
    ],
    sayLine: 'Yangın var.',
    questions: <String>[
      'Yangın nerede? (blok, kat, daire, çatı, otopark, kazan dairesi)',
      'Ne yanıyor? Yangın büyüyor mu, duman var mı?',
      'İçeride mahsur kalan ya da yaralı var mı? Kaç kişi?',
      _addressQuestion,
      _contactQuestion,
    ],
  ),
  EmergencyScenario.elevator: EmergencyGuide(
    scenario: EmergencyScenario.elevator,
    title: 'Asansör arızası',
    scriptTitle: 'ACİL DURUM - ASANSÖR ARIZASI',
    summary: 'Arızayı önce sitenin asansör bakım firmasına bildirin. İçeride mahsur kalan biri tehlikedeyse 112\'yi arayın.',
    steps: <String>[
      'İçeride mahsur kalan varsa sakin olun; kapıyı zorlamayın, kabindeki alarm ya da interkom düğmesine basın.',
      'Dışarıdakiler asansörü zorlamasın ve kullanmasın.',
      'Mahsur kalan kişide sağlık sorunu ya da panik varsa, içeride çocuk, yaşlı ya da hamile varsa vakit kaybetmeden 112\'yi arayın.',
    ],
    sayLine: 'Asansör arızası var.',
    questions: <String>[
      'Hangi blok ve hangi asansör? (kabindeki ya da kapıdaki etiket veya seri numarası varsa)',
      'Asansör kaçıncı katta? Kapı açık mı, kapalı mı?',
      'İçeride mahsur kalan var mı? Kaç kişi; çocuk, yaşlı, hamile ya da rahatsızlığı olan var mı?',
      _addressQuestion,
      _contactQuestion,
    ],
  ),
};

EmergencyGuide emergencyGuideOf(EmergencyScenario scenario) => _guides[scenario]!;

/// "Aramada söyleyin" bloğunun adres satırları: (site adı, adres). Site yoksa ya da adres kayıtlı değilse ilgili parça null.
({String? siteName, String? address}) emergencySayLines(EmergencySite? site) => (
  siteName: site?.label,
  address: site?.addressLine,
);

/// Kuru modda ve "Bilgileri kopyala" ile panoya giden düz metin: numaralar, aramada söylenecekler, adres ve sorular. Hiçbir satır
/// aramanın yapıldığını söylemez.
String buildEmergencyScript(EmergencyScenario scenario, EmergencySite? site) {
  final guide = emergencyGuideOf(scenario);
  final lines = <String>[guide.scriptTitle];
  switch (scenario) {
    case EmergencyScenario.general || EmergencyScenario.fire:
      lines.add('Aranacak numara: $kEmergencyNumber');
    case EmergencyScenario.elevator:
      if (site != null && site.hasElevatorFirm) {
        lines.add('Asansör bakım firması: ${site.elevatorFirmLabel}, ${site.elevatorFirmPhone}');
      } else {
        lines.add('Asansör bakım firması: kayıtlı değil (site yönetiminden isteyin)');
      }
      lines.add('Mahsur kalan kişide tehlike varsa: $kEmergencyNumber');
  }
  lines.add('Söyleyin: ${guide.sayLine}');
  final say = emergencySayLines(site);
  if (say.siteName != null) lines.add('Site: ${say.siteName}');
  lines.add(say.address != null ? 'Adres: ${say.address}' : 'Adres: kayıtlı değil, adresi kendiniz söyleyin');
  lines.add('Blok, kat ve daire numaranızı da söyleyin.');
  lines
    ..add('')
    ..add('Sorulabilecekler:');
  for (final (i, question) in guide.questions.indexed) {
    lines.add('${i + 1}. $question');
  }
  return lines.join('\n');
}

/// Denetim kaydı etiketi (sunucu `emergency.*`); bilinmeyen eylem null.
String? emergencyActionLabel(String action) => switch (action) {
  'emergency.info_updated' => 'Acil durum bilgisi güncellendi',
  _ => null,
};
