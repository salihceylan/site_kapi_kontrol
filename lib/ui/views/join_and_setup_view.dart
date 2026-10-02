import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/join_request_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/setup_option_card.dart';

class JoinAndSetupView extends StatefulWidget {
  const JoinAndSetupView({
    super.key,
    required this.authService,
    required this.session,
    required this.onOpenClaimDevice,
    required this.onOpenJoinSite,
    this.onRefreshAll,
  });

  final AuthService authService;
  final UserSession session;
  final VoidCallback onOpenClaimDevice;
  final VoidCallback onOpenJoinSite;
  final VoidCallback? onRefreshAll;

  @override
  State<JoinAndSetupView> createState() => _JoinAndSetupViewState();
}

class _JoinAndSetupViewState extends State<JoinAndSetupView> {
  List<JoinRequestRecord> _myRequests = [];
  bool _isLoadingRequests = false;

  @override
  void initState() {
    super.initState();
    _loadRequests();
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
    const headerTone = AppTone.primary;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadRequests();
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
                // Başlık Bilgi Kartı
                StaggeredEntry(
                  index: 0,
                  child: AppCard(
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: headerTone.tint(p),
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Icon(
                                Icons.add_home_work_rounded,
                                color: headerTone.ink(p),
                                size: 26,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  'Daireye Katıl & Cihaz Ekle',
                                  style: th.titleLarge,
                                ),
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
                    description:
                        'Satın aldığınız kutudaki QR kodu veya Seri Numarasını okutup cihazınızı bağlayarak yeni site kurun ve site yöneticisi olun.',
                    action: ElevatedButton.icon(
                      onPressed: () async {
                        widget.onOpenClaimDevice();
                        await _loadRequests();
                      },
                      icon: const Icon(
                        Icons.add_circle_outline_rounded,
                        size: 20,
                      ),
                      label: const Text(
                        'Cihaz Ekleyerek Site Yöneticisi Ol',
                        textAlign: TextAlign.center,
                      ),
                    ),
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
