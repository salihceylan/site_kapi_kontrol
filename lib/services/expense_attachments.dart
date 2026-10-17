import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/widgets.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/finance_4b_api.dart';

/// Gider eki için ince arayüz (Platform Faz 4b, Ö3): dosya / fotoğraf SEÇİCİ dış bağımlılıktır (`file_picker`,
/// Faz 2b / 3b ile gelir). Bu arayüz verilmedikçe gider ekranlarında ek alanı GİZLİDİR ("modül yoksa gizli");
/// belge modülü ya da seçici hazır olduğunda çağıran bir uygulama verir, ekranlar değişmez.
abstract class ExpenseAttachmentSource {
  /// Kullanıcıdan en çok [maxCount] dosya seçtirir; vazgeçerse boş liste. Yalnız PDF / JPG / PNG kabul edilir
  /// (kimlik no / IBAN karartılmalı; telefon fotoğrafı konum bilgisi içerebilir — uyarı ekranda gösterilir).
  Future<List<PickedExpenseFile>> pick(BuildContext context, {required int maxCount});
}

/// Seçilen dosya: ad + bayt + (biliniyorsa) tür. Bellekte tutulur (en çok 5 dosya).
class PickedExpenseFile {
  PickedExpenseFile({required this.name, required this.bytes, this.mimeType});

  final String name;
  final Uint8List bytes;
  final String? mimeType;

  int get size => bytes.length;

  String? _digest;

  /// İçerik özeti (SHA-256'nın ilk 20 onaltılık hanesi): yükleme işlem anahtarı AD + BOYUT + İÇERİKE bağlıdır; aynı adlı ve
  /// aynı boyutlu ama farklı iki dosya aynı anahtarı paylaşmaz (ikincisi "zaten yüklendi" sayılmasın).
  String get contentDigest => _digest ??= sha256.convert(bytes).toString().substring(0, 20);

  /// Gider eki olarak kabul edilen uzantılar (içerik imzasını sunucu ayrıca doğrular).
  static const Set<String> allowedExtensions = <String>{'pdf', 'jpg', 'jpeg', 'png'};

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool get isAllowedType => allowedExtensions.contains(extension);

  /// Sunucuya bildirilen içerik türü (bilinmiyorsa uzantıdan).
  String get contentType {
    final given = mimeType;
    if (given != null && given.isNotEmpty) return given;
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      default:
        return 'image/jpeg';
    }
  }

  ExpenseAttachmentKind get kind =>
      extension == 'pdf' ? ExpenseAttachmentKind.invoice : ExpenseAttachmentKind.photo;
}

/// Bir dosyanın yükleme sonucu.
class ExpenseUploadResult {
  const ExpenseUploadResult({required this.file, this.error});

  final PickedExpenseFile file;

  /// Başarısızsa kullanıcıya gösterilecek Türkçe metin; başarıda null.
  final String? error;

  bool get ok => error == null;
}

/// Bir yükleme grubunun işlem anahtarı imzaları (dosya örneği -> imza): `doc|gider|ad|boyut|özet`. AYNI içerikli ikinci dosya
/// (aynı ad, boyut ve içerik) sıra numarasıyla ayrılır. İmza, dosya seçim sırasına DEĞİL içeriğe bağlıdır: yanıtı kaybolan
/// yüklemenin yeniden denenmesi (dosya yeniden seçilse bile) aynı anahtarı kullanır, çift belge oluşmaz.
Map<PickedExpenseFile, String> expenseUploadSignatures(int expenseId, List<PickedExpenseFile> files) {
  final seen = <String, int>{};
  final result = Map<PickedExpenseFile, String>.identity();
  for (final file in files) {
    final base = 'doc|$expenseId|${file.name}|${file.size}|${file.contentDigest}';
    final n = seen[base] = (seen[base] ?? 0) + 1;
    result[file] = n == 1 ? base : '$base|$n';
  }
  return result;
}

/// Giderin ek dosyalarını sırayla yükler (iki adım: üstveri + ham gövde). Bir dosyanın hatası ötekileri durdurmaz;
/// sonuçlar dosya başına döner. [onProgress] her dosyadan önce `(sıra, toplam)` ile çağrılır.
Future<List<ExpenseUploadResult>> uploadExpenseFiles({
  required Finance4bService service,
  required int siteCode,
  required int expenseId,
  required List<PickedExpenseFile> files,
  required String Function(PickedExpenseFile file) keyFor,
  void Function(int index, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final results = <ExpenseUploadResult>[];
  for (var i = 0; i < files.length; i++) {
    if (isCancelled?.call() ?? false) break;
    final file = files[i];
    onProgress?.call(i + 1, files.length);
    try {
      final ticket = await service.run(
        (api, token) => api.createExpenseDocument(
          token: token,
          siteCode: siteCode,
          expenseId: expenseId,
          fileName: file.name,
          size: file.size,
          contentType: file.contentType,
          kind: file.kind,
          idempotencyKey: keyFor(file),
        ),
      );
      if (ticket.alreadyStored) {
        // Önceki denemede yükleme tamamlanmıştı (yanıt kaybolmuş): tekrar yüklenmez.
        results.add(ExpenseUploadResult(file: file));
        continue;
      }
      final max = ticket.maxBytes;
      if (max != null && file.size > max) {
        results.add(ExpenseUploadResult(file: file, error: 'Dosya çok büyük. Daha küçük bir dosya seçin.'));
        continue;
      }
      await service.run((api, token) => api.uploadExpenseDocument(token: token, ticket: ticket, bytes: file.bytes));
      results.add(ExpenseUploadResult(file: file));
    } catch (e) {
      results.add(ExpenseUploadResult(file: file, error: e is ApiException && e.message.trim().isNotEmpty ? e.message : 'Dosya yüklenemedi.'));
    }
  }
  return results;
}
