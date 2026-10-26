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
    required this.onOpenJoinSite,
    this.onRefreshAll,
    this.applications,
    this.onRefreshAccount,
  });

  final AuthService authService;
  final UserSession session;
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
  /// "Site Kurulumu" kartının eylemi: birincil "Site Kurmak İçin Başvur" ([SiteApplyCta]: bekleyen / durum bilinmezken pasif)
  /// ve "Yakında…" pasif satırı. Bu ekranda CİHAZ EKLEME yoktur: cihazı yalnız Geçiş Kontrol modülü açık sitenin yöneticisi
  /// ekler ("Kayıtlı Cihazlar" ekranından); bu ekran yalnız daireye katılma ve site başvurusu içindir.
  Widget _buildAdminAction(SiteApplicationTracker tracker) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SiteApplyCta(tracker: tracker, onApply: _openApplicationForm),
        const SizedBox(height: AppSpace.sm),
        const SiteSubscriptionComingSoonRow(),
      ],
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
    // Takipçi ya da rol değişti (örn. bireysel <-> daire kullanıcısı): açık ekran durumu yeniden yükler.
    if (oldWidget.applications != widget.applications ||
        oldWidget.session.role != widget.session.role) {
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
                                title: 'Daireye Katıl',
                              ),
                              const SizedBox(height: AppSpace.xs),
                              Text(
                                'Yöneticinizin paylaştığı site katılım QR kodu ya da katılım koduyla bir siteye/daireye katılabilirsiniz.',
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
                    showApproved: showsApprovedApplicationCard(widget.session.role),
                    showLoadFailure: canApplyForSite(widget.session.role),
                    showReapplyOnRejected: true,
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
                    badge: 'Hızlı Katılım',
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
                // 2. KART: SİTE KURULUMU (yalnız başvuru akışı açık rollerde)
                // ==========================================
                if (widget.applications != null)
                  StaggeredEntry(
                    index: 2,
                    child: SetupOptionCard(
                      tone: AppTone.primary,
                      icon: Icons.domain_add_rounded,
                      title: 'Site Kurulumu',
                      badge: 'Başvuru',
                      description:
                          'Sitenizi tanımlayıp başvurun; süper kullanıcı onayladığında siteniz kurulur ve site yöneticisi olursunuz. Cihazı site kurulduktan sonra siz (site yöneticisi) eklersiniz.',
                      action: _buildAdminAction(widget.applications!),
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
