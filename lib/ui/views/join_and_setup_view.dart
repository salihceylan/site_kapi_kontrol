import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/site_application_flow.dart';
import 'package:site_kapi_kontrol/ui/widgets/join_request_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/setup_option_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_status_card.dart';

class JoinAndSetupView extends StatefulWidget {
  const JoinAndSetupView({
    super.key,
    required this.authService,
    required this.session,
    required this.onOpenClaimDevice,
    required this.onOpenJoinSite,
    this.onRefreshAll,
    this.applications,
    this.onRefreshAccount,
  });

  final AuthService authService;
  final UserSession session;
  final VoidCallback onOpenClaimDevice;
  final VoidCallback onOpenJoinSite;
  final VoidCallback? onRefreshAll;

  /// Site başvurusu durumu (Platform: site başvurusu). YALNIZ bireysel / daire kullanıcısına verilir: null
  /// iken başvuru kartı ve "Site Kurmak İçin Başvur" eylemi görünmez (eski ekran birebir aynıdır).
  final SiteApplicationTracker? applications;

  /// Onaylanmış başvuruda rolü elle yenileme ("Hesabı yenile").
  final Future<void> Function()? onRefreshAccount;

  @override
  State<JoinAndSetupView> createState() => _JoinAndSetupViewState();
}

class _JoinAndSetupViewState extends State<JoinAndSetupView> {
  /// Cihaz ekleyerek yönetici olma düğmesi (eski eylem; etiketi ve davranışı aynıdır).
  Widget _claimButton({bool tonal = false}) {
    return ElevatedButton.icon(
      style: tonal ? tonalActionStyle(context) : null,
      onPressed: () async {
        widget.onOpenClaimDevice();
        await _loadRequests();
      },
      icon: const Icon(
        Icons.add_circle_outline_rounded,
        size: 20,
      ),
      label: Text(
        // Başvuru akışında cihaz sahiplenmek yönetici yapmaz: etiket yanıltmasın.
        tonal ? 'Cihaz Ekle' : 'Cihaz Ekleyerek Site Yöneticisi Ol',
        textAlign: TextAlign.center,
      ),
    );
  }

  /// "Yönetici & Cihaz Kurulumu" kartının eylemi: başvuru akışı kapalıysa (rol uygun değil) eski tek düğme;
  /// açıksa birincil "Site Kurmak İçin Başvur", ikincil cihaz düğmesi ve "Yakında…" pasif satırı.
  Widget _buildAdminAction() {
    final tracker = widget.applications;
    if (tracker == null) return _claimButton();
    return ListenableBuilder(
      listenable: tracker,
      builder: (context, _) {
        final pending = tracker.pending != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              key: const ValueKey<String>('site_application_apply'),
              onPressed: pending ? null : () => unawaited(_openApplicationForm()),
              icon: Icon(
                pending ? Icons.hourglass_top_rounded : Icons.domain_add_rounded,
                size: 20,
              ),
              label: Text(
                pending ? 'Başvurunuz İnceleniyor' : 'Site Kurmak İçin Başvur',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            _claimButton(tonal: true),
            const SizedBox(height: AppSpace.sm),
            const SiteSubscriptionComingSoonRow(),
          ],
        );
      },
    );
  }

  List<JoinRequestRecord> _myRequests = [];
  bool _isLoadingRequests = false;

  // Başvuru formu çift dokunuşta iki kez açılmasın.
  bool _openingApplication = false;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    unawaited(widget.applications?.ensureLoaded());
  }

  @override
  void didUpdateWidget(JoinAndSetupView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.applications != widget.applications) {
      unawaited(widget.applications?.ensureLoaded());
    }
  }

  /// "Site Kurmak İçin Başvur" / "Yeniden başvur": başvuru formunu açar ([previous] ile önceki değerlerle).
  Future<void> _openApplicationForm([SiteApplication? previous]) async {
    if (_openingApplication) return;
    _openingApplication = true;
    try {
      await openSiteApplicationForm(
        context,
        authService: widget.authService,
        tracker: widget.applications,
        previous: previous,
      );
    } finally {
      _openingApplication = false;
    }
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoadingRequests = true);
    try {
      final (list, _) = await widget.authService.getMyJoinRequests();
      if (!mounted) return;
      setState(() {
        _myRequests = list ?? [];
        _isLoadingRequests = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingRequests = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadRequests();
        await widget.applications?.refresh();
        widget.onRefreshAll?.call();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Başlık Bilgi Kartı: cilalı rozet (büyük yazıda gizlenir) + SectionHeader başlığı.
                StaggeredEntry(
                  index: 0,
                  child: AppCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const IconTile(
                          icon: Icons.add_home_work_rounded,
                          size: 48,
                          gap: AppSpace.md,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionHeader(
                                title: 'Daireye Katıl & Cihaz Ekle',
                              ),
                              const SizedBox(height: AppSpace.xs),
                              Text(
                                'Yeni bir siteye/daireye katılabilir veya kutudan çıkan yeni bir cihazı sahiplenerek site yöneticisi olabilirsiniz.',
                                style: th.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),

                // Site başvurusu durumu (bekleyen / reddedildi / iptal / onaylandı); durum alınamazsa hata.
                if (widget.applications != null)
                  SiteApplicationStatusCard(
                    tracker: widget.applications!,
                    onReapply: _openApplicationForm,
                    onRefreshAccount: widget.onRefreshAccount,
                  ),

                // ==========================================
                // 1. KART: SİTE SAKİNİ GİRİŞİ (DAİREYE KATIL)
                // ==========================================
                StaggeredEntry(
                  index: 1,
                  child: SetupOptionCard(
                    tone: AppTone.success,
                    icon: Icons.key_rounded,
                    title: 'Site Sakini Girişi',
                    badge: 'Daireye Katıl',
                    description:
                        'Yöneticinizin paylaştığı site katılım QR kodunu okutarak veya katılım kodunu girerek dairenize katılım başvurusu gönderin.',
                    action: ElevatedButton.icon(
                      onPressed: () async {
                        widget.onOpenJoinSite();
                        await _loadRequests();
                      },
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                      label: const Text(
                        'QR / Kod ile Daireye Katıl',
                        textAlign: TextAlign.center,
                      ),
                      // Beyaz etiket >= 4,5:1 için koyu zümrüt (success.a); eski #059669 3,8:1 idi.
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTone.success.a,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),

                // ==========================================
                // 2. KART: YÖNETİCİ & CİHAZ KURULUMU
                // ==========================================
                StaggeredEntry(
                  index: 2,
                  child: SetupOptionCard(
                    tone: AppTone.primary,
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Yönetici & Cihaz Kurulumu',
                    badge: 'Yönetici Ol',
                    description: widget.applications == null
                        ? 'Satın aldığınız kutudaki QR kodu veya Seri Numarasını okutup cihazınızı bağlayarak yeni site kurun ve site yöneticisi olun.'
                        : 'Sitenizi tanımlayıp başvurun; süper kullanıcı onayladığında siteniz kurulur ve site yöneticisi olursunuz. Cihaz şart değildir, kutudaki QR kodu veya Seri Numarasıyla sonra da eklenebilir.',
                    action: _buildAdminAction(),
                  ),
                ),

                // ==========================================
                // 3. BÖLÜM: KATILIM BAŞVURULARIM (VARSA)
                // ==========================================
                if (_myRequests.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xl),
                  SectionHeader(
                    title: 'Katılım Başvurularım',
                    trailing: IconButton(
                      onPressed: _isLoadingRequests ? null : _loadRequests,
                      icon: _isLoadingRequests
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'Yenile',
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  for (final (index, req) in _myRequests.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.md),
                      child: StaggeredEntry(
                        key: ValueKey<String>('request-${req.id}'),
                        index: index,
                        child: JoinRequestCard(
                          title: req.siteName ?? 'Site #${req.siteCode}',
                          status: JoinRequestCard.statusOf(req),
                          details: [
                            Text(
                              '${req.blockName?.isNotEmpty == true ? '${req.blockName} • ' : ''}Daire ${req.unitLabel ?? '-'}',
                              style: th.bodyMedium?.copyWith(
                                color: p.text,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (req.notes?.isNotEmpty == true)
                              Text(
                                'Not: "${req.notes}"',
                                style: th.bodySmall?.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
