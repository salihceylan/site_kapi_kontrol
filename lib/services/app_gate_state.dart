import 'dart:async';

import 'package:flutter/foundation.dart';

/// Açılış kapısının (AppGate) anlık durumu.
///
/// - [active]: uygulama bir bakım / zorunlu güncelleme ekranının ALTINDA gizliyken `true`. Gizli uygulamanın
///   dışarıdan tetiklenen eylemleri (kapı açan derin bağlantı / kısayol) bu durumda yok sayılmalıdır; aksi
///   hâlde gizli gezginde açılan onay penceresi engel kalkınca beklenmedik biçimde belirir.
/// - [pendingFirstCheck]: kapı ağaçta ve İLK yapılandırma denetimi henüz bitmedi. Soğuk açılışta bekleyen
///   bir derin bağlantı, oturum yüklenir yüklenmez (kapının kararından ÖNCE) işlenebilir; bu yüzden
///   işleyici önce [waitForFirstCheck] ile denetimin bitmesini bekler. Kapı hiç yoksa (testler) `false`
///   kalır ve beklenmez.
abstract final class AppGateBlock {
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  static final ValueNotifier<bool> pendingFirstCheck = ValueNotifier<bool>(
    false,
  );

  /// İlk denetim bitene ya da [timeout] dolana kadar bekler; kapı yoksa ya da denetim bitmişse hemen döner.
  static Future<void> waitForFirstCheck({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!pendingFirstCheck.value) return;
    final done = Completer<void>();
    void listener() {
      if (!pendingFirstCheck.value && !done.isCompleted) done.complete();
    }

    pendingFirstCheck.addListener(listener);
    try {
      await done.future.timeout(timeout, onTimeout: () {});
    } finally {
      pendingFirstCheck.removeListener(listener);
    }
  }
}
