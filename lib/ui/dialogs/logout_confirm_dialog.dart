// P2-26: "Çıkış Yap" onayı. Çıkış artık AppBar'daki çıplak bir simge değil, menünün dibindeki bir satırdır ve her zaman
// onaydan geçer: yanlışlıkla bir dokunuşla oturum kapanmaz (kapı açma, bildirim ve yerel veri oturuma bağlıdır).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';

/// Çıkış onayı penceresi. Onaylanırsa true, "Vazgeç" ya da dışarı dokunuşla false döner (çıkış yapılmaz).
Future<bool> confirmLogout(BuildContext context) => confirmCrmAction(
      context,
      title: 'Çıkış yapılsın mı?',
      message: 'Bu cihazdaki oturumunuz kapatılacak. Tekrar kullanmak için yeniden giriş yapmanız gerekir.',
      confirmLabel: 'Çıkış Yap',
      icon: Icons.logout_rounded,
      tone: AppTone.danger,
    );
