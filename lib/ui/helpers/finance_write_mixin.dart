import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';

/// Faz 4b yazma pencerelerinin ortak gönderim mantığı (4a tahsilat / borçlandırma pencerelerinin dersleri):
/// - ÇİFT GÖNDERİM koruması: gönderim sürerken ikinci çağrı yok sayılır.
/// - `idempotency_key` VERİ İMZASINA bağlıdır: aynı veriyle yeniden deneme (sonuç belirsizse) AYNI anahtarı kullanır,
///   çift kayıt oluşmaz; veri değişirse yeni anahtar alınır. Başarıda ve `IDEMPOTENCY_CONFLICT`ta anahtar atılır.
/// - Hız sınırı (429) düğmeyi geçici kilitler ([retry]).
/// - Sonuç BELİRSİZ kalan hatada (ağ / 5xx) [needsRefreshOnClose] işaretlenir; çağıran pencere kapanırken listeyi tazeler
///   ve kullanıcıya "kayıt oluşmuş olabilir" ipucu gösterilir.
mixin FinanceWriteMixin<W extends StatefulWidget> on State<W> {
  /// `idempotency_key` önek (yalnız küçük harf, rakam, tire).
  String get keyPrefix;

  /// Oturumu temsil eden nesne (örn. `scope.authService`). Verilirse anahtarlar OTURUM boyunca yaşar: sonucu belirsiz kalan
  /// bir isteğin penceresi kapatılıp aynı veriyle yeniden açılsa bile AYNI anahtar kullanılır (çift kayıt yok). Verilmezse
  /// anahtarlar pencere ömrüncedir.
  Object? get keyOwner => null;

  late final IdempotencyKeys keys = keyOwner == null ? IdempotencyKeys(keyPrefix) : sessionIdempotencyKeys(keyOwner!, keyPrefix);
  final RetryLock retry = RetryLock();

  bool submitting = false;
  String? submitError;
  bool needsRefreshOnClose = false;

  void disposeWrite() => retry.dispose();

  /// Gönderim sürüyor ya da hız sınırı kilidi açık mı (düğme pasif)?
  bool get writeBlocked => submitting || retry.locked;

  /// [action] anahtarla çağrılır. Başarıda [onSuccess] (pencereyi kapatmak çağıranın işidir). Hata metni
  /// [failure] ya da sunucunun Türkçe metnidir; [onError] true dönerse çağıran hatayı kendisi gösterir.
  Future<bool> runWrite<T>({
    required String signature,
    required Future<T> Function(String key) action,
    required FutureOr<void> Function(T result) onSuccess,
    required String failure,
    bool Function(Object error)? onError,
  }) async {
    if (submitting || retry.locked) return false;
    final key = keys.keyFor(signature);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      submitting = true;
      submitError = null;
    });
    try {
      final result = await action(key);
      keys.clear(signature);
      if (!mounted) return true;
      needsRefreshOnClose = false;
      await onSuccess(result);
      if (mounted && submitting) setState(() => submitting = false);
      return true;
    } catch (e) {
      if (financeOutcomeUncertain(e)) needsRefreshOnClose = true;
      if (hasErrorCode(e, 'IDEMPOTENCY_CONFLICT')) {
        keys.clear(signature);
        needsRefreshOnClose = true;
      }
      if (!mounted) return false;
      final limited = retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      final custom = !limited && (onError?.call(e) ?? false);
      setState(() {
        submitting = false;
        if (!custom) {
          submitError = limited ? RetryLock.messageFor(e) : financeWriteMessage(e, failure);
        }
      });
      return false;
    }
  }
}

/// Form pencerelerinde KAYDEDİLMEMİŞ VERİ KAYBINI önler: kullanıcı bir alanı değiştirdikten sonra geri tuşu / Esc / "Vazgeç" ile
/// kapatırsa "Değişiklikler silinsin mi?" onayı sorulur ("Düzenlemeye Dön" varsayılandır). Gönderim sürerken kapanış zaten
/// engellidir ([closeLocked]); değişiklik yoksa onay sorulmaz.
///
/// Kullanım: `PopScope(canPop: canPopNow, onPopInvokedWithResult: (didPop, _) { handleBlockedPop(didPop); ... })`, "Vazgeç"
/// düğmesi `requestClose`, alan değişiminde `markDirty()` (Form.onChanged, seçim çipleri...).
mixin FinanceDiscardGuard<W extends StatefulWidget> on State<W> {
  bool _dirty = false;

  /// Gönderim sürüyor mu (kapanış engelli)?
  bool get closeLocked;

  /// Kaydedilmemiş değişiklik var mı? Varsayılan: [markDirty] çağrıldı. Pencere kendi ölçütünü verebilir (örn. "not dolu").
  bool get hasUnsavedChanges => _dirty;

  bool get canPopNow => !closeLocked && !hasUnsavedChanges;

  /// Kullanıcı veriyi değiştirdi. `setState` içinden de çağrılabilir (yalnız bayrak kurar; geri tuşu denetimi güncellensin diye
  /// sonraki karede bir kez yeniden çizim ister).
  void markDirty() {
    if (_dirty) return;
    _dirty = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// Başarıyla kaydedildi / bilerek sıfırlandı: artık onay gerekmez.
  void clearDirty() => _dirty = false;

  Future<bool> _confirmDiscard() => confirmCrmAction(
    context,
    title: 'Değişiklikler silinsin mi?',
    message: 'Girdiğiniz bilgiler henüz kaydedilmedi. Pencereyi şimdi kapatırsanız silinir.',
    confirmLabel: 'Vazgeç ve Kapat',
    cancelLabel: 'Düzenlemeye Dön',
    icon: Icons.warning_amber_rounded,
  );

  /// `PopScope.onPopInvokedWithResult` içinden: kapanış değişiklik yüzünden engellendiyse onay sorar.
  void handleBlockedPop(bool didPop) {
    if (didPop || closeLocked || !hasUnsavedChanges) return;
    unawaited(_discardAndClose());
  }

  Future<void> _discardAndClose() async {
    if (await _confirmDiscard() && mounted) popIfCurrent(context);
  }

  /// "Vazgeç" düğmesi.
  Future<void> requestClose() async {
    if (closeLocked) return;
    if (!hasUnsavedChanges || await _confirmDiscard()) {
      if (mounted) popIfCurrent(context);
    }
  }
}

/// Yazma penceresi kapanırken döner: kullanıcıya gösterilecek kısa sonuç iletisi (tutarlar ekran okuyucuda okunuşla
/// duyurulur; bkz. `showFinanceSnack`).
class FinanceWriteOutcome {
  const FinanceWriteOutcome(this.message);

  final String message;
}
