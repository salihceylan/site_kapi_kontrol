// Android "Paylaş" ile gelen dekont (Dalga 2 / 2B). Paketsiz: ayrı ShareReceiverActivity (yalnız content://, PDF / JPEG / PNG, en çok 10 MB) dosyayı
// uygulamanın önbelleğine (cache/share_inbox) kopyalar ve MainActivity'yi öne getirir; bekleyen tek kayıt 30 dakika tutulur.
// Bu sınıf kanaldan o kaydı OKUR ve siler (bir kez). iOS paylaşım uzantısı Apple hesabı (App Group, Team ID) açılınca yapılır: orada bu sınıf null döner.
// Dosya adı ve içerik günlüğe yazılmaz.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Paylaşılan dekont: ad, tür (application/pdf | image/jpeg | image/png) ve baytlar.
@immutable
class SharedReceipt {
  const SharedReceipt({required this.name, required this.mime, required this.bytes});

  final String name;
  final String mime;
  final Uint8List bytes;
}

abstract class ShareInbox {
  /// Bekleyen paylaşımı döndürür ve siler; yoksa (ya da platform desteklemiyorsa) null.
  Future<SharedReceipt?> take();

  /// Bekleyen paylaşımı kullanmadan siler (ör. oturum yok / sakin değil).
  Future<void> clear();
}

/// Android kanalı. Testlerde sahte [ShareInbox] verilir.
class ChannelShareInbox implements ShareInbox {
  const ChannelShareInbox({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('tr.com.gudeteknoloji.siteyonetim/share_inbox');

  final MethodChannel _channel;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<SharedReceipt?> take() async {
    if (!supported) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('take');
      if (raw == null) return null;
      final bytes = raw['bytes'];
      final name = raw['name'];
      final mime = raw['mime'];
      if (bytes is! Uint8List || name is! String || mime is! String || bytes.isEmpty) return null;
      return SharedReceipt(name: name, mime: mime, bytes: bytes);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } on PlatformException {
      // sessiz: süre dolunca zaten silinir
    } on MissingPluginException {
      // sessiz
    }
  }
}
