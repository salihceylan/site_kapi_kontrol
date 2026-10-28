// Sayaç saha okuması: cihazdaki bekleme kuyruğu + gönderim (internet yoksa okuma ve fotoğraf cihazda bekler, gelince gider).
//
// Kuyruk üstbilgisi SharedPreferences'ta (JSON), fotoğraflar uygulama belgeler klasöründe `meter_field/` altında dosyadır (web'de dosya yok:
// web'de yalnız elle giriş, fotoğrafsız). Gönderim sırayla yapılır; ağ/sunucu (5xx, zaman aşımı) hatasında durur ve kalanlar bekler;
// sunucunun kalıcı reddi (aynı gün farklı değer, sıra dışı, sayaç yok…) kayda `error` olarak yazılır ve görevli düzeltene dek yeniden denenmez.
// Olağan dışı tüketim uyarısı (`READING_JUMP`) da bu biçimde durur ama ENGEL DEĞİLDİR: görevli "doğru" derse kayıt `confirm_jump` ile gider.
// Sunucu aynı sayaç+tarih+değeri sessizce kabul ettiği için (replayed) bir yanıtı kaçırıp yeniden göndermek güvenlidir.
// Kuyruğu okuyup değiştirip yazan her iş sıraya girer (`_apply`): sürmekte olan gönderim turu, araya giren yeni bir okumayı ezip kaybetmez.
// Değerler, fotoğraflar ve belirteç günlüğe YAZILMAZ.
//
// "Silmeyi biz yapmayız" (karar K6): sunucu okumayı kabul etse bile fotoğrafın telefondaki kopyasını uygulama KENDİLİĞİNDEN SİLMEZ; yalnız kullanıcı isterse
// ([MeterFieldQueue.deleteKeptPhotos]) ya da bekleyen kaydı kendisi silerse ([MeterFieldQueue.remove]) gider. Sunucu fotoğrafı düşürürse ("none") kopya zaten durur.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File;
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/meter_field_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/meter_api.dart';

/// Kuyruğun depolama katmanı (testlerde bellek içi sahte).
abstract class MeterFieldStore {
  Future<List<PendingMeterReading>> load();
  Future<void> save(List<PendingMeterReading> items);

  /// Fotoğrafı cihaza yazar ve yolunu döner; dosya desteklenmiyorsa (web) null.
  Future<String?> writePhoto(String id, Uint8List bytes);
  Future<Uint8List?> readPhoto(String path);
  Future<void> deletePhoto(String path);

  /// Cihazda duran tüm fotoğraf dosyalarının yolları (bekleyenler ve gönderilmiş okumaların kopyaları); dosya desteklenmiyorsa (web) boş.
  Future<List<String>> listPhotos();
}

class LocalMeterFieldStore implements MeterFieldStore {
  static const String _key = 'meter_field_queue_v1';

  @override
  Future<List<PendingMeterReading>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null || raw.isEmpty) return <PendingMeterReading>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <PendingMeterReading>[];
      return <PendingMeterReading>[for (final e in decoded) ?PendingMeterReading.tryFromJson(e)];
    } on Object {
      return <PendingMeterReading>[];
    }
  }

  @override
  Future<void> save(List<PendingMeterReading> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(<Object?>[for (final i in items) i.toJson()]));
  }

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/meter_field');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<String?> writePhoto(String id, Uint8List bytes) async {
    if (kIsWeb) return null;
    try {
      final file = File('${(await _dir()).path}/$id.jpg');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on Object {
      return null;
    }
  }

  @override
  Future<Uint8List?> readPhoto(String path) async {
    if (kIsWeb) return null;
    try {
      final file = File(path);
      return file.existsSync() ? await file.readAsBytes() : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> deletePhoto(String path) async {
    if (kIsWeb) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on Object {
      // Silinemeyen dosya kuyruğu bozmaz.
    }
  }

  @override
  Future<List<String>> listPhotos() async {
    if (kIsWeb) return <String>[];
    try {
      final dir = await _dir();
      return <String>[for (final entry in dir.listSync()) if (entry is File) entry.path];
    } on Object {
      return <String>[];
    }
  }
}

/// Gönderim turunun özeti.
class MeterFlushReport {
  const MeterFlushReport({this.sent = 0, this.rejected = 0, this.jumpPending = 0, this.remaining = 0, this.offline = false, this.keptPhotos = 0, this.photosMissed = 0});

  final int sent;

  /// Bu turda sunucunun reddettiği okuma sayısı ([jumpPending] dahil); ekran bununla anında uyarır.
  final int rejected;

  /// [rejected] içinden: olağan dışı tüketim nedeniyle görevlinin ONAYINI bekleyenler (engel değil, onaylayınca gider).
  final int jumpPending;

  /// Hâlâ cihazda bekleyen (reddedilenler dahil).
  final int remaining;

  /// Ağ/sunucu hatasıyla durdu; sonra yeniden denenir.
  final bool offline;

  /// Bu turda gönderilen okumaların telefonda KALAN fotoğraf kopyası sayısı (uygulama silmez; kullanıcı isterse siler).
  final int keptPhotos;

  /// Okuma kabul edildi ama sunucu fotoğrafı almadı (sınır / geçersiz / hata): kopya telefonda durur.
  final int photosMissed;
}

class MeterFieldQueue {
  MeterFieldQueue({MeterFieldStore? store, DateTime Function()? now, Random? random}) : _store = store ?? LocalMeterFieldStore(), _now = now ?? DateTime.now, _random = random ?? Random();

  final MeterFieldStore _store;
  final DateTime Function() _now;
  final Random _random;
  bool _flushing = false;
  Future<void> _tail = Future<void>.value();

  /// Listeyi okuyup [change] ile değiştirip yazar; bu tür işler sırayla çalışır (biri bitmeden öteki başlamaz). Yeni listeyi döner.
  Future<List<PendingMeterReading>> _apply(List<PendingMeterReading> Function(List<PendingMeterReading> current) change) {
    final result = _tail.then((_) async {
      final next = change(await _store.load());
      await _store.save(next);
      return next;
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<List<PendingMeterReading>> items() => _store.load();

  /// Okumayı (ve varsa fotoğrafı) cihaza yazar; her zaman önce kuyruğa girer, ağ sonra denenir.
  /// [replace]: yeniden çekim (o günün okuması varsa sunucuda değeri değişir). [jumpConfirmed]: görevli olağan dışı tüketimi önceden onayladı.
  Future<PendingMeterReading> enqueue({
    required int siteCode,
    required FieldMeter meter,
    required String date,
    required String value,
    Uint8List? photo,
    bool replace = false,
    bool jumpConfirmed = false,
  }) async {
    final id = '${_now().microsecondsSinceEpoch}${_random.nextInt(1 << 20)}';
    final path = photo == null ? null : await _store.writePhoto(id, photo);
    final item = PendingMeterReading(
      id: id,
      siteCode: siteCode,
      meterId: meter.id,
      apartmentLabel: meter.apartmentLabel,
      kindLabel: meter.kind.label,
      date: date,
      value: value,
      photoPath: path,
      replace: replace,
      jumpConfirmed: jumpConfirmed,
    );
    await _apply((all) => <PendingMeterReading>[...all, item]);
    return item;
  }

  /// Bekleyen kaydı KULLANICI siler (Sil düğmesi): kaydın fotoğrafı da onunla gider.
  Future<void> remove(String id) async {
    final removed = <PendingMeterReading>[];
    await _apply((all) {
      removed.addAll(all.where((e) => e.id == id));
      return <PendingMeterReading>[for (final e in all) if (e.id != id) e];
    });
    for (final item in removed.where((e) => e.photoPath != null)) {
      await _store.deletePhoto(item.photoPath!);
    }
  }

  static String _samePath(String path) => path.replaceAll('\\', '/');

  /// Gönderilmiş okumaların telefonda kalan fotoğraf kopyaları: cihazdaki fotoğraflardan hâlâ bekleyen (ya da reddedilmiş) bir kayda ait OLMAYANLAR.
  Future<List<String>> _keptPhotoPaths() async {
    final inUse = <String>{for (final item in await _store.load()) if (item.photoPath != null) _samePath(item.photoPath!)};
    return <String>[for (final path in await _store.listPhotos()) if (!inUse.contains(_samePath(path))) path];
  }

  /// Telefonda duran, gönderilmiş okuma fotoğrafı kopyası sayısı.
  Future<int> keptPhotoCount() async => (await _keptPhotoPaths()).length;

  /// Gönderilmiş okumaların telefondaki fotoğraf kopyalarını siler. YALNIZ kullanıcı isteğiyle çağrılır ("Kopyaları sil"); uygulama bunu kendiliğinden yapmaz.
  /// Bekleyen ya da reddedilmiş kayıtların fotoğrafına dokunmaz. Silinen sayıyı döner.
  Future<int> deleteKeptPhotos() async {
    var deleted = 0;
    for (final path in await _keptPhotoPaths()) {
      await _store.deletePhoto(path);
      deleted++;
    }
    return deleted;
  }

  /// Reddedilen kaydın değerini düzeltir ve yeniden denemeye açar (yeni değer için önceki sıçrama onayı geçersizdir).
  Future<void> correct(String id, String value) async {
    await _apply((all) => <PendingMeterReading>[for (final e in all) e.id == id ? e.copyWith(value: value, clearError: true, jumpConfirmed: false) : e]);
  }

  /// Olağan dışı tüketim uyarısını görevli onayladı: kayıt `confirm_jump: true` ile yeniden denenmeye açılır.
  Future<void> confirmJump(String id) async {
    await _apply((all) => <PendingMeterReading>[for (final e in all) e.id == id ? e.copyWith(jumpConfirmed: true, clearError: true) : e]);
  }

  /// Bekleyenleri sırayla gönderir. Eşzamanlı ikinci çağrı boş rapor döner.
  Future<MeterFlushReport> flush(MeterService service) async {
    if (_flushing) return MeterFlushReport(remaining: (await _store.load()).length);
    _flushing = true;
    var sent = 0;
    var rejected = 0;
    var jumpPending = 0;
    var offline = false;
    var keptPhotos = 0;
    var photosMissed = 0;
    try {
      for (final queued in await _store.load()) {
        // Tur sürerken görevli kaydı silmiş / değiştirmiş olabilir: güncel hâline bak.
        final item = (await _store.load()).where((e) => e.id == queued.id).firstOrNull;
        if (item == null || item.error != null) continue;
        String? b64;
        if (item.photoPath != null) {
          final bytes = await _store.readPhoto(item.photoPath!);
          if (bytes != null) b64 = base64Encode(bytes);
        }
        try {
          final result = await service.postFieldReading(
            item.siteCode,
            meterId: item.meterId,
            date: item.date,
            value: item.value,
            photoBase64: b64,
            confirmJump: item.jumpConfirmed,
            replace: item.replace,
          );
          // K6: fotoğrafın telefondaki kopyası SİLİNMEZ (sunucu kabul etse bile). Kullanıcı isterse siler (deleteKeptPhotos).
          if (item.photoPath != null) {
            keptPhotos++;
            if (b64 != null && !result.replayed && result.photoStorage == 'none') photosMissed++;
          }
          await _apply((current) => <PendingMeterReading>[for (final e in current) if (e.id != item.id) e]);
          sent++;
        } on ApiException catch (e) {
          if (_isPermanent(e)) {
            await _apply((current) => <PendingMeterReading>[for (final x in current) x.id == item.id ? x.copyWith(error: e.message, errorCode: e.code) : x]);
            rejected++;
            if (e.code == kReadingJumpCode) jumpPending++;
          } else {
            offline = true;
            break;
          }
        }
      }
      return MeterFlushReport(
        sent: sent,
        rejected: rejected,
        jumpPending: jumpPending,
        remaining: (await _store.load()).length,
        offline: offline,
        keptPhotos: keptPhotos,
        photosMissed: photosMissed,
      );
    } finally {
      _flushing = false;
    }
  }

  /// 4xx (oturum, hız sınırı ve ara katman hariç) kalıcı reddir; ağ yok / zaman aşımı / 5xx / 429 / 401 geçicidir.
  static bool _isPermanent(ApiException e) {
    final status = e.statusCode;
    if (status == null || e.fromIntermediary || e.invalidatesSession || e.isRateLimited || e.isServerError) return false;
    return status >= 400 && status < 500;
  }
}
