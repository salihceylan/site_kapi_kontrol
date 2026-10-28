// P2-21: "bağlı değil" ile "hata" ayrımı. Liste yükleyicileri ([PagedLoader], [CursorLoader]) yakalanan hatayı buradan
// geçirir; ortak durum bileşeni ([StateView]) ağ kaynaklı hatayı (sunucuya ulaşılamıyor) sunucu hatasından ayırır.
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/services/api_exception.dart';

/// [error] sunucuya ULAŞILAMAMASINDAN mı (internet yok, DNS/TLS, zaman aşımı, ara katman/proxy, 502/503/504) geliyor?
///
/// Hizmet katmanı taşıma hatalarını `ApiException(mesaj)` olarak (durum kodu OLMADAN) sarar; bu yüzden durum kodu yoksa
/// mesajdaki bilinen ifadelere bakılır (Türkçe karakterler katlanır: "ulaşılamadı" = "ulasilamadi"). Sunucu bir durum
/// koduyla YANIT verdiyse (400, 403, 404, 409, 422, 500 ...) bağlantı vardır: bu "bağlı değil" değil, hatadır.
/// Programlama hataları ([Error]) ağ sorunu gibi gösterilmez.
bool isConnectivityError(Object? error) {
  if (error == null) return false;
  if (error is TimeoutException || error is http.ClientException) return true;
  if (error is ApiException) {
    // Araya giren katman (proxy / WAF / captive portal) sunucumuzdan yanıt değildir: ulaşılamıyor demektir.
    if (error.fromIntermediary) return true;
    final status = error.statusCode;
    if (status != null) return status == 502 || status == 503 || status == 504;
    return _transportMessage.hasMatch(_fold(error.message));
  }
  if (error is Exception) {
    // dart:io web derlemesinde yok: SocketException / HandshakeException / TlsException tür adıyla tanınır.
    const names = <String>{'SocketException', '_ClientSocketException', 'HandshakeException', 'TlsException', 'WebSocketException'};
    return names.contains(error.runtimeType.toString());
  }
  return false;
}

/// Katlanmış (küçük harf, ASCII) ağ hatası ifadeleri; hizmet katmanındaki gerçek mesajlardan derlendi.
final RegExp _transportMessage = RegExp(
  r'sunucuya (ulasilamadi|baglanilamadi|ulasilamiyor)'
  r'|sunucu (zamaninda )?yanit vermedi'
  r'|internet baglantisi yok'
  r'|(internet|ag) baglantinizi kontrol'
  r'|ssl baglantisi'
  r'|baglanti cok yavas',
);

/// Türkçe karakterleri ASCII'ye katlar ve küçük harfe çevirir (eşleştirme için; kullanıcıya gösterilmez).
String _fold(String text) {
  const map = <String, String>{
    'ı': 'i', 'İ': 'i', 'I': 'i', 'ş': 's', 'Ş': 's', 'ğ': 'g', 'Ğ': 'g',
    'ü': 'u', 'Ü': 'u', 'ö': 'o', 'Ö': 'o', 'ç': 'c', 'Ç': 'c',
  };
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(map[ch] ?? ch.toLowerCase());
  }
  return buffer.toString();
}
