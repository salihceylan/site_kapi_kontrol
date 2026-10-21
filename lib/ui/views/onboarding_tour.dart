import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/views/help_content.dart';

/// Turun tek adımı.
class OnboardingStep {
  const OnboardingStep({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;
}

/// Role göre 4 adımlık kısa tanıtım içeriği. Arayüz adları “çift tırnak” içinde verilir ve gerçek menü /
/// ekran etiketlerine dayanır ([HelpContent.knownMenuTitles], [HelpContent.knownScreenLabels]). Girişte açılan
/// "Panel" modül vitrinidir; kapı paneli "Kapılar" ekranındadır (tur da kapıyı orada anlatır).
abstract final class OnboardingSteps {
  static const OnboardingStep _help = OnboardingStep(
    icon: Icons.help_outline_rounded,
    title: 'Yardım her zaman yanınızda',
    body:
        'Takıldığınızda menüdeki “Yardım ve Destek” ekranına bakın: nasıl yapılır adımları, sık sorulan '
        'sorular, destek bilgileri ve yasal belgeler orada. Bu tanıtımı da oradan yeniden açabilirsiniz.',
  );

  static List<OnboardingStep> forAudience(HelpAudience audience) {
    switch (audience) {
      case HelpAudience.resident:
        return const <OnboardingStep>[
          OnboardingStep(
            icon: Icons.lock_open_rounded,
            title: 'Kapınız cebinizde',
            body:
                'Girişte açılan “Panel” ekranı (alttaki “Özet” sekmesi) modüllerinizin vitrinidir. Kapınız “Kapılar” '
                'kartının ve alttaki “Kapı” sekmesinin arkasında: dokunun, “KAPIYI AÇ” düğmesiyle kapıyı açın.',
          ),
          OnboardingStep(
            icon: Icons.qr_code_2_rounded,
            title: 'QR, sesli komut ve misafir geçişi',
            body:
                'Yetkinize göre menüde “Kapıya QR Göster”, “Sesli Kapı Açma” ve “Kurye / Misafir Geçiş Linki Oluştur” '
                'eylemleri görünür.',
          ),
          OnboardingStep(
            icon: Icons.campaign_rounded,
            title: 'Alt çubuk, duyurular ve borcunuz',
            body:
                'Alttaki “Duyuru”, “Arıza” ve “Belgeler” sekmeleri duyuruları, arıza taleplerinizi ve site belgelerini '
                'açar. Sitenizde Finans modülü açıksa “Borcum” ekranından borç ve ödemelerinizi görürsünüz; hesap '
                'ayarlarınız sağ üstteki “Ayarlar” düğmesindedir.',
          ),
          _help,
        ];
      case HelpAudience.individual:
        return const <OnboardingStep>[
          OnboardingStep(
            icon: Icons.waving_hand_rounded,
            title: 'Hoş geldiniz',
            body:
                'Hesabınız hazır. Girişte açılan “Panel” ekranındaki kartlardan bir siteye daire sakini olarak '
                'katılabilir, cihazınızı hesabınıza ekleyebilir ya da site kurmak için başvurabilirsiniz. Hesap '
                'ayarlarınız sağ üstteki “Ayarlar” düğmesindedir.',
          ),
          OnboardingStep(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Daireye katılın',
            body:
                'Menüden “Daireye Katıl & Cihaz Ekle” ekranını açın ve “QR / Kod ile Daireye Katıl” düğmesiyle '
                'yöneticinizin paylaştığı kodu girin. Yönetici onaylayınca kapılarınız “Kapılar” ekranında görünür.',
          ),
          OnboardingStep(
            icon: Icons.add_to_photos_rounded,
            title: 'Cihaz ekleyin ya da site kurun',
            body:
                'Aynı ekranda “Cihaz Ekle” ile kutudaki QR kodu okutabilir, “Site Kurmak İçin Başvur” ile site '
                'yöneticisi olmak için başvurabilirsiniz.',
          ),
          _help,
        ];
      case HelpAudience.siteManager:
        return const <OnboardingStep>[
          OnboardingStep(
            icon: Icons.apartment_rounded,
            title: 'Sitenizi yönetin',
            body:
                '“Site Yönetimi” ekranında bloklarınızı, dairelerinizi, kapılarınızı ve sakin hesaplarını yönetir, '
                'katılım başvurularını onaylarsınız.',
          ),
          OnboardingStep(
            icon: Icons.contacts_rounded,
            title: 'Kayıtlar ve duyurular',
            body:
                '“Kişiler” ekranında kişi, daire ve araç kayıtlarını tutar, “Duyurular” ekranından sakinlerinize '
                'duyuru yayınlarsınız.',
          ),
          OnboardingStep(
            icon: Icons.extension_rounded,
            title: 'Panel ve modüller',
            body:
                'Açık modüller girişte açılan “Panel” ekranında kart olarak dizilir; kapı paneli “Kapılar” '
                'kartındadır. Menü başlıklar altında toplanır, birden çok siteniz varsa en üstten site seçersiniz. '
                'Sağ üstteki “Ayarlar” düğmesindeki “Modüller” ekranında kapalı bir modül için talep gönderirsiniz.',
          ),
          _help,
        ];
      case HelpAudience.superUser:
        return const <OnboardingStep>[
          OnboardingStep(
            icon: Icons.admin_panel_settings_rounded,
            title: 'Platform yönetimi',
            body:
                'Girişte açılan “Panel” ekranında yönetim ekranlarınız kart olarak dizilir; kapı paneli “Kapılar” '
                'kartındadır. “Kullanıcı Yönetimi”, “Site Yöneticileri Yönetimi” ve “Daire Sakinleri” ekranlarından '
                'hesapları yönetirsiniz.',
          ),
          OnboardingStep(
            icon: Icons.inbox_rounded,
            title: 'Başvurular ve talepler',
            body:
                '“Site Başvuruları” ve “Modül Talepleri” ekranlarında bekleyen işleri değerlendirirsiniz; '
                'bekleyen sayılar Panel\'deki dikkat barında ve “Ayarlar” düğmesinde rozetle görünür.',
          ),
          OnboardingStep(
            icon: Icons.fact_check_rounded,
            title: 'Cihazlar ve denetim',
            body:
                'Sağ üstteki “Ayarlar” düğmesi “Şirket Cihaz Envanteri”, “Denetim Kaydı” ve “Platform Ayarları” '
                'gibi yönetim ekranlarını açar; bekleyen talepler düğmede rozetle görünür.',
          ),
          _help,
        ];
    }
  }
}

/// İlk kullanım turunu gösterir ve "görüldü" bilgisini (kullanıcı başına) saklar.
abstract final class OnboardingTour {
  static bool _showing = false;

  /// Yalnız testler: açık tur bayrağını sıfırlar (ağaç, tur açıkken atılırsa bayrak takılı kalır).
  @visibleForTesting
  static void resetForTesting() => _showing = false;

  /// Bu kullanıcı için "görüldü" anahtarı.
  static String seenKey(int userId) => 'onboarding_tour_seen_v1_$userId';

  /// Tur bu kullanıcıya gösterildi mi? Okuma hatasında true döner (kullanıcıyı sürekli rahatsız etme).
  static Future<bool> hasSeen(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(seenKey(userId)) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markSeen(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(seenKey(userId), true);
    } catch (_) {
      // Saklanamadı: bir sonraki açılışta yeniden gösterilebilir; işlem etkilenmez.
    }
  }

  /// Daha önce görülmediyse gösterir (giriş sonrası ilk açılış). Zaten bir tur açıkken ya da oturum
  /// yokken hiçbir şey yapmaz.
  static Future<void> maybeShow(BuildContext context, {required AuthService authService}) async {
    final session = authService.session;
    if (session == null || _showing) return;
    if (await hasSeen(session.id)) return;
    if (!context.mounted || authService.session?.id != session.id) return;
    await show(context, role: session.role, userId: session.id);
  }

  /// Turu her durumda açar (Yardım'dan yeniden açma dahil). Kapanınca (bitir / atla / geri) "görüldü"
  /// işaretlenir.
  static Future<void> show(
    BuildContext context, {
    required UserRole role,
    bool residentMode = false,
    int? userId,
  }) async {
    if (_showing) return;
    _showing = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => OnboardingTourPage(
            steps: OnboardingSteps.forAudience(
              HelpContent.audienceFor(role, residentMode: residentMode),
            ),
          ),
        ),
      );
    } finally {
      _showing = false;
    }
    if (userId != null) await markSeen(userId);
  }
}

/// Tam ekran tur sayfası: 4 adım, "Atla", "Geri", "İleri"/"Başla". Geri tuşu da turu kapatır (atlar).
///
/// Erişilebilirlik: başlıklar başlık düğümüdür; adım değişince "Adım 2 / 4: başlık" duyurulur; ilerleme
/// noktaları dekoratiftir (ilerleme metinle de verilir). Dokunma hedefleri >= 48 dp; büyük yazıda içerik
/// kaydırılır, düğmeler satıra sığmazsa alta iner.
class OnboardingTourPage extends StatefulWidget {
  const OnboardingTourPage({super.key, required this.steps});

  final List<OnboardingStep> steps;

  @override
  State<OnboardingTourPage> createState() => _OnboardingTourPageState();
}

class _OnboardingTourPageState extends State<OnboardingTourPage> {
  final PageController _controller = PageController();
  int _index = 0;

  bool get _isLast => _index >= widget.steps.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    if (mounted) Navigator.of(context).maybePop();
  }

  void _go(int target) {
    if (target < 0 || target >= widget.steps.length) return;
    final duration = AppMotion.of(context, AppMotion.base);
    if (duration == Duration.zero) {
      _controller.jumpToPage(target);
    } else {
      unawaited(_controller.animateToPage(target, duration: duration, curve: AppMotion.standard));
    }
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    announcePolite(
      context,
      'Adım ${index + 1} / ${widget.steps.length}: ${widget.steps[index].title}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final steps = widget.steps;
    final hPad = MediaQuery.sizeOf(context).width < 400 ? AppSpace.lg : AppSpace.xl;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, 0),
                child: TextButton(
                  onPressed: _close,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('Atla'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: steps.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, i) {
                  final step = steps[i];
                  return Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: AppSpace.lg),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: AppCard(
                          level: 2,
                          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: AppSpace.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Center(child: IconOrb(icon: step.icon, size: 72, glow: true)),
                              const SizedBox(height: AppSpace.lg),
                              Semantics(
                                header: true,
                                child: Text(
                                  step.title,
                                  textAlign: TextAlign.center,
                                  style: th.titleLarge,
                                ),
                              ),
                              const SizedBox(height: AppSpace.sm),
                              Text(
                                step.body,
                                textAlign: TextAlign.center,
                                style: th.bodyLarge?.copyWith(color: p.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, AppSpace.sm, hPad, AppSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // İlerleme noktaları süs: adım bilgisi adım değişiminde TEK duyuruyla verilir (_onPageChanged). Aynı
                  // bilgiyi canlı bir anlamsal etiketle de vermek çift duyuruya yol açardı.
                  ExcludeSemantics(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        for (var i = 0; i < steps.length; i++)
                          AnimatedContainer(
                            duration: AppMotion.of(context, AppMotion.base),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _index ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _index ? AppTone.primary.ink(p) : p.border,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: <Widget>[
                      if (_index > 0)
                        PrimaryActionButton(
                          label: 'Geri',
                          icon: Icons.arrow_back_rounded,
                          variant: AppButtonVariant.outline,
                          expand: false,
                          onPressed: () => _go(_index - 1),
                        ),
                      PrimaryActionButton(
                        label: _isLast ? 'Başla' : 'İleri',
                        icon: _isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                        expand: false,
                        onPressed: _isLast ? _close : () => _go(_index + 1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
