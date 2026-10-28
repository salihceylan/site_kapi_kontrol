import 'package:url_launcher/url_launcher.dart';

// "Dokun-ara" (P2-23, karar K13): yöneticiyi ve 112'yi tek dokunuşla arama. Saf mantık burada; düğmeler
// `lib/ui/widgets/call_actions.dart`, `emergency_call_button.dart` içindedir.
//
// İlke: `tel:` adresi yalnız telefon uygulamasını numara yazılı AÇAR (Android arama ekranı, iOS onay penceresi); uygulama kendisi
// arama BAŞLATMAZ ve kazara dokunuşla çağrı yapılmaz. Arama açılamayan ortamda (tablet, emülatör, masaüstü, web ya da arama
// uygulaması olmayan cihaz) "kuru mod": numara ekranda gösterilir ve kopyalanabilir; hata gibi değil, çözümle birlikte anlatılır.

/// Acil çağrı merkezi (karar K13: acil numara 112).
const String kEmergencyNumber = '112';

/// Telefon uygulamasında bir adres açar (`tel:`); açılamazsa false. Testlerde sahte verilir.
typedef DialLauncher = Future<bool> Function(Uri uri);

/// Varsayılan açıcı: önce cihazın `tel:` adresini işleyebildiği sorulur (Android 11+ için manifestte `tel` sorgusu var),
/// sonra dış uygulamada açılır. Her hata "açılamadı" sayılır (asla fırlatmaz).
Future<bool> defaultDialLauncher(Uri uri) async {
  try {
    if (!await canLaunchUrl(uri)) return false;
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Aranabilir biçim: "0532 123 45 67" -> "05321234567", "+90 (532) 123-45-67" -> "+905321234567", "112" -> "112".
///
/// Yalnız rakam, boşluk, ( ) - . / ve BAŞTAKİ + kabul edilir; harf, `*`, `#`, `;`, `,` ya da ortadaki + varsa null
/// (USSD / özel kod / çoklu arama çevrilmez). Hane sayısı 3-15 dışındaysa null. Sunucudaki `dialablePhone` (yönetici profil
/// telefonu: 7-15 hane, `/` yok) ile aynı yönde ama biraz geniştir: alt sınır 3 (112, 185 gibi kısa hizmet numaraları) ve `/`
/// kabul edilir (firma / rehber telefonları).
String? dialableNumber(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  if (!RegExp(r'^\+?[0-9()\-\s./]+$').hasMatch(value)) return null;
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 3 || digits.length > 15) return null;
  return value.startsWith('+') ? '+$digits' : digits;
}

/// `tel:` adresi ([dialable] [dialableNumber] çıktısıdır).
Uri telUri(String dialable) => Uri(scheme: 'tel', path: dialable);

/// Ekranda gösterilecek biçim: Türkiye numaraları gruplanır ("05321234567" -> "0532 123 45 67",
/// "+905321234567" -> "+90 532 123 45 67"); öteki (112, 444 1 234, yabancı numara) olduğu gibi kalır.
String formatPhoneForDisplay(String dialable) {
  final local = RegExp(r'^0(\d{3})(\d{3})(\d{2})(\d{2})$').firstMatch(dialable);
  if (local != null) return '0${local[1]} ${local[2]} ${local[3]} ${local[4]}';
  final intl = RegExp(r'^\+90(\d{3})(\d{3})(\d{2})(\d{2})$').firstMatch(dialable);
  if (intl != null) return '+90 ${intl[1]} ${intl[2]} ${intl[3]} ${intl[4]}';
  return dialable;
}

/// Arama denemesinin sonucu.
enum DialOutcome {
  /// Telefon uygulaması numarayla açıldı.
  started,

  /// Numara geçerli ama cihaz aramayı açamadı (kuru mod: numara gösterilir ve kopyalanır).
  unavailable,

  /// Numara aranabilir biçimde değil (boş, harfli, çok kısa / uzun); hiçbir adres açılmaz.
  invalid,
}

/// [raw] numarayı arama ekranında açar. Geçersiz numarada launcher ÇAĞRILMAZ.
Future<DialOutcome> dialPhone(String? raw, {DialLauncher? launcher}) async {
  final dialable = dialableNumber(raw);
  if (dialable == null) return DialOutcome.invalid;
  final opened = await (launcher ?? defaultDialLauncher)(telUri(dialable));
  return opened ? DialOutcome.started : DialOutcome.unavailable;
}
