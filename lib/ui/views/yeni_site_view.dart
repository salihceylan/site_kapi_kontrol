import 'package:flutter/material.dart';
import 'package:phosphor_glyphs/phosphor_glyphs.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/site_application_flow.dart';
import 'package:site_kapi_kontrol/ui/widgets/setup_option_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_status_card.dart';

/// Yeni Site Oluşturma Görünümü (Site Hizmetleri menüsü altındadır).
///
/// Bireysel kullanıcı, site yöneticisi ve süper kullanıcı için merkezi site kurulum noktasıdır.
/// Bireysel kullanıcılar başvuru akışı üzerinden, yöneticiler ve süper kullanıcılar anlık sihirbaz
/// üzerinden site oluşturma sürecini başlatır.
class YeniSiteView extends StatelessWidget {
  const YeniSiteView({
    super.key,
    required this.session,
    required this.authService,
    required this.onStartSetup,
    this.tracker,
    this.onRefreshAccount,
  });

  final UserSession session;
  final AuthService authService;
  final VoidCallback onStartSetup;
  final SiteApplicationTracker? tracker;
  final Future<void> Function()? onRefreshAccount;

  /// Başlatma düğmesi. [tracker] verilmişse (başvuru akışındaki roller) düğme, durum biliniyor ve bekleyen başvuru
  /// yokken etkindir; bekleyen başvuru varken, durum kontrol edilirken ya da ALINAMADIYKEN pasiftir ve nedeni ipucunda
  /// yazılıdır (sunucuya gidip 409 almaz; [SiteApplyCta] ile aynı kural). [tracker] yoksa (süper kullanıcı) hep etkin.
  Widget _startAction(String readyLabel) {
    Widget button(String label, IconData icon, VoidCallback? onPressed) => ElevatedButton.icon(
      key: const ValueKey<String>('yeni_site_start'),
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTone.primary.a,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    final tracker = this.tracker;
    if (tracker == null) {
      return button(readyLabel, Icons.add_circle_outline_rounded, onStartSetup);
    }
    return ListenableBuilder(
      listenable: tracker,
      builder: (context, _) {
        final availability = tracker.applyAvailability;
        final reason = siteApplyDisabledReason(availability);
        final (IconData icon, String label) = switch (availability) {
          SiteApplyAvailability.ready => (Icons.add_circle_outline_rounded, readyLabel),
          SiteApplyAvailability.pending => (Icons.hourglass_top_rounded, 'Başvurunuz İnceleniyor'),
          SiteApplyAvailability.checking => (Icons.sync_rounded, 'Durum Kontrol Ediliyor...'),
          SiteApplyAvailability.unknown => (Icons.sync_problem_rounded, 'Başvuru Durumu Alınamadı'),
        };
        final built = button(label, icon, reason == null ? onStartSetup : null);
        if (reason == null) return built;
        return Tooltip(
          message: reason,
          child: Semantics(hint: reason, child: built),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final isManagerOrSuper =
        session.role == UserRole.siteManager || session.role == UserRole.superUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başvuru durumu kartı (kullanıcının incelenen veya sonuçlanmış başvurusu varsa)
              if (tracker != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.md),
                  child: SiteApplicationStatusCard(
                    tracker: tracker!,
                    onReapply: (_) async => onStartSetup(),
                    onRefreshAccount: onRefreshAccount,
                    showApproved: showsApprovedApplicationCard(session.role),
                    showLoadFailure: true,
                    showReapplyOnRejected: true,
                  ),
                ),

              SetupOptionCard(
                tone: AppTone.primary,
                icon: PhosphorIconsRegular.buildings,
                title: 'Yeni Site Oluştur',
                badge: isManagerOrSuper ? 'ANLIK KURULUM' : 'BAŞVURU',
                description: isManagerOrSuper
                    ? 'Yeni bir site, blok ve kapı yapısını anında tanımlayarak dijital site yönetimini hemen başlatın.'
                    : 'Sitenizi, bloğunuzu ve tahmini daire sayılarınızı tanımlayarak site oluşturma başvurusunu başlatın. Başvurunuz onaylandığında sitenizin yöneticisi olursunuz.',
                action: _startAction(
                  isManagerOrSuper
                      ? 'Site Kurulum Sihirbazını Başlat'
                      : 'Site Oluşturma Başvurusu Yap',
                ),
              ),

              const SizedBox(height: AppSpace.lg),

              // Bilgilendirme Kartı
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 20, color: p.textMuted),
                          const SizedBox(width: AppSpace.sm),
                          Flexible(
                            child: Text(
                              'Site Oluşturma Süreci',
                              style: th.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: p.text,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        '• Site kurulumu sırasında sitenizin adını, adresini ve blok/daire sayılarını dinamik olarak belirleyebilirsiniz.\n'
                        '• Kurulum sonrasında kapılarınızı ve akıllı geçiş cihazlarınızı (ESP32-C3 / WROOM) tek tıkla atayabilirsiniz.\n'
                        '• Site sakinleri için "Site Katılım QR Kodu" üreterek sakinlerin dairelerine hızla bağlanmasını sağlayabilirsiniz.',
                        style: th.bodySmall?.copyWith(color: p.textMuted, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

