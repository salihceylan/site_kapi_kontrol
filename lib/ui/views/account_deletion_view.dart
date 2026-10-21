import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/account_deletion.dart';
import 'package:site_kapi_kontrol/services/account_api.dart';
import 'package:site_kapi_kontrol/services/account_local_wipe.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/widgets/account_password_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Hesabımı Sil" sayfası (Profil -> Gizlilik ve Veri).
///
/// Akış: önizleme (`POST /me/account-deletion/preview`) -> NE SİLİNECEK / NE KALACAK açık dille -> silmeyi
/// engelleyen nedenler varsa nedenleriyle birlikte gösterilir ve ilerleme KAPALIDIR -> parola + "SİL"
/// yazdırma ile son onay (`POST /me/account-deletion`).
///
/// Güvenli taraf: önizleme yüklenemezse / bozuksa silme açılmaz ("Tekrar Dene" gösterilir; yanlış "silinebilir"
/// ya da "boş" durum çizilmez). Önizleme `can_delete: true` dese bile engel listesi doluysa ilerlenmez.
///
/// Başarıda: sunucu silmeyi onaylayınca [AccountService.deleteAccount] yerel durumu temizler ve çıkış yapar;
/// bu sayfa ve üstündeki tüm yollar kapatılır (kök sayfa artık giriş ekranıdır) ve bilgi mesajı gösterilir.
class AccountDeletionView extends StatefulWidget {
  const AccountDeletionView({super.key, required this.service, this.onOpenDebt});

  final AccountService service;

  /// Verilirse borç engelinde "Borcum'a git" düğmesi çıkar: bu sayfa kapanır, ardından çağrılır (Borcum açılır).
  final VoidCallback? onOpenDebt;

  static const String deletedMessage =
      'Hesabınız silindi ve bu cihazdaki verileriniz temizlendi. '
      'İsterseniz aynı e-posta adresiyle yeniden kayıt olabilirsiniz.';

  /// Hesap sunucuda silindi ama bu cihazdaki bazı yerel adımlar başarısız oldu ([LocalWipeReport.complete] false):
  /// "temizlendi" denmez, kalanı kullanıcıya dürüstçe söylenir.
  static const String deletedPartialMessage =
      'Hesabınız silindi. Ancak bu cihazdaki bazı yerel veriler silinemedi; uygulama verilerini cihaz '
      'ayarlarından temizleyin.';

  @override
  State<AccountDeletionView> createState() => AccountDeletionViewState();
}

class AccountDeletionViewState extends State<AccountDeletionView> {
  AccountDeletionPreview? _preview;
  bool _loading = true;
  bool _confirming = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await widget.service.previewDeletion();
      if (!mounted || token != _token) return;
      // Silinebilir diyor ama neyin silineceğini söylemiyor: bilgilendirilmiş onay verilemez, ilerleme yok.
      final incomplete = preview.canDelete && preview.willRemove.isEmpty;
      setState(() {
        _loading = false;
        if (incomplete) {
          _preview = null;
          _error = 'Silinecek verilerin ayrıntısı alınamadı. Lütfen tekrar deneyin.';
        } else {
          _preview = preview;
        }
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _preview = null;
        _error = e is ApiException && e.message.trim().isNotEmpty
            ? e.message
            : 'Silme bilgileri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      });
    }
  }

  /// Silme sırasında sunucu engel bildirdi (önizlemeden sonra durum değişmiş): sayfa güncellenir.
  void _applyBlockers(List<AccountDeletionBlocker> blockers) {
    if (!mounted) return;
    final old = _preview;
    setState(() {
      _preview = AccountDeletionPreview(
        canDelete: false,
        blockers: blockers,
        willRemove: old?.willRemove ?? const <String>[],
        willKeep: old?.willKeep ?? const <String>[],
      );
    });
    announcePolite(context, 'Hesabınız şu anda silinemez.');
  }

  Future<void> _confirm() async {
    if (_confirming) return;
    setState(() => _confirming = true);
    final navigator = Navigator.of(context, rootNavigator: true);
    LocalWipeReport? report;
    try {
      report = await AccountPasswordDialog.show<LocalWipeReport>(
        context,
        title: 'Hesabı kalıcı olarak sil',
        icon: Icons.delete_forever_rounded,
        tone: AppTone.danger,
        message:
            'Bu işlem geri alınamaz. Hesabınız silinecek ve oturumunuz kapanacak. '
            'Onaylamak için şifrenizi girin ve SİL yazın.',
        confirmLabel: 'Hesabımı Sil',
        busyLabel: 'Siliniyor...',
        confirmWord: 'SİL',
        closeOnError: (error) {
          if (error is AccountDeleteBlockedException) {
            _applyBlockers(error.blockers);
            return true;
          }
          return false;
        },
        onSubmit: widget.service.deleteAccount,
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
    if (report == null) return;
    // Sunucu sildi, yerel oturum kapandı: kök sayfa artık giriş ekranı. Üstteki tüm yolları (bu sayfa dahil)
    // kapat ve bilgiyi giriş ekranının üstünde göster.
    navigator.popUntil((route) => route.isFirst);
    if (navigator.mounted) {
      AppSnack.show(
        navigator.context,
        report.complete ? AccountDeletionView.deletedMessage : AccountDeletionView.deletedPartialMessage,
        kind: report.complete ? AppSnackKind.success : AppSnackKind.warning,
        duration: const Duration(seconds: 8),
        maxLines: 8,
        replace: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final hPad = MediaQuery.sizeOf(context).width < 360 ? AppSpace.md : AppSpace.lg;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hesabımı Sil'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: (_loading || _confirming) ? null : reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: AppSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const InlineNotice(
                    tone: AppTone.warning,
                    message:
                        'Hesabınızı silmek geri alınamaz. Devam etmeden önce aşağıda nelerin silineceğini '
                        've nelerin saklanacağını okuyun.',
                  ),
                  const SizedBox(height: AppSpace.lg),
                  _body(context, th),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, TextTheme th) {
    final preview = _preview;
    if (_loading && preview == null) {
      return const ListSkeleton(rows: 3);
    }
    if (preview == null) {
      return InlineNotice(message: _error ?? 'Silme bilgileri yüklenemedi.', onRetry: reload);
    }
    final blocked = !preview.canDelete;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          InlineNotice(message: _error!, onRetry: reload),
          const SizedBox(height: AppSpace.lg),
        ],
        if (blocked) ...[
          _BlockersCard(
            blockers: preview.blockers,
            onOpenDebt: widget.onOpenDebt == null
                ? null
                : () {
                    Navigator.of(context).maybePop();
                    widget.onOpenDebt!();
                  },
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        if (preview.willRemove.isNotEmpty) ...[
          _ListCard(
            key: const ValueKey<String>('account_will_remove'),
            title: 'Silinecekler',
            icon: Icons.delete_outline_rounded,
            tone: AppTone.danger,
            items: preview.willRemove,
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        if (preview.willKeep.isNotEmpty) ...[
          _ListCard(
            key: const ValueKey<String>('account_will_keep'),
            title: 'Saklanacaklar',
            icon: Icons.inventory_2_outlined,
            tone: AppTone.info,
            items: preview.willKeep,
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        if (blocked)
          Text(
            'Yukarıdaki engeller kalkmadan hesabınız silinemez.',
            style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        if (blocked) const SizedBox(height: AppSpace.md),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const ValueKey<String>('account_delete_continue'),
            style: filledToneStyle(context, tone: AppTone.danger),
            onPressed: (blocked || _confirming || _loading) ? null : _confirm,
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Silmeye Devam Et', textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            key: const ValueKey<String>('account_delete_cancel'),
            onPressed: _confirming ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Vazgeç', textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}

/// "Hesabınız şu anda silinemez" kartı: her engel nedeniyle (+ varsa site kodu ve çözüm yönergesi).
class _BlockersCard extends StatelessWidget {
  const _BlockersCard({required this.blockers, this.onOpenDebt});

  final List<AccountDeletionBlocker> blockers;
  final VoidCallback? onOpenDebt;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return AppCard(
      key: const ValueKey<String>('account_blockers'),
      tone: AppTone.danger,
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Hesabınız şu anda silinemez', icon: Icons.block_rounded),
          const SizedBox(height: AppSpace.md),
          if (blockers.isEmpty)
            Text(
              'Hesabınızın silinmesine şu anda izin verilmiyor. Ayrıntı için destek ekibiyle iletişime geçin.',
              style: th.bodyMedium,
            ),
          for (var i = 0; i < blockers.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.md),
            Semantics(
              container: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    blockers[i].message,
                    style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (blockers[i].siteId != null)
                    Text('Site kodu: ${blockers[i].siteId}', style: th.bodySmall),
                  if (blockers[i].hint != null) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      blockers[i].hint!,
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ],
                  if (blockers[i].code == 'OPEN_DEBT' && onOpenDebt != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    OutlinedButton(
                      key: const ValueKey<String>('account_blocker_open_debt'),
                      onPressed: onOpenDebt,
                      child: const Text("Borcum'a git", textAlign: TextAlign.center),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Madde işaretli kart (silinecekler / saklanacaklar). Maddeler kırpılmadan sarar.
class _ListCard extends StatelessWidget {
  const _ListCard({
    super.key,
    required this.title,
    required this.icon,
    required this.tone,
    required this.items,
  });

  final String title;
  final IconData icon;
  final AppTone tone;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title, icon: icon),
          const SizedBox(height: AppSpace.md),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: AppSpace.sm),
                  child: ExcludeSemantics(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: tone.ink(p), shape: BoxShape.circle),
                    ),
                  ),
                ),
                Expanded(child: Text(items[i], style: th.bodyMedium)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
