import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/ui/design/module_art.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_status_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

// Vitrin renkleri tek kaynaktan ([AppShowcaseColors], tokens.dart): açık temada işverenin renk tablosu (zemin #F8FAFC,
// kart #FFFFFF + #E2E8F0 çerçeve, metin #475569, odak #0F172A, durum noktaları), koyu temada palet. Düz hex yazılmaz.
Color _cardColor(AppPalette p) => p.isDark ? p.surface : AppShowcaseColors.card;
Color _cardBorder(AppPalette p) => p.isDark ? p.border : AppShowcaseColors.cardBorder;
Color _bodyInk(AppPalette p) => p.isDark ? p.textSecondary : AppShowcaseColors.text;

/// Panel: MODÜL VİTRİNİ. Girişten sonra herkesi karşılayan ekran; kapı paneli artık "Kapılar" kartının arkasındadır.
///
/// - Kartlar yan menünün hesapladığı öğe listesinden ([menuItems], `YanMenu.visibleItems`) türetilir; görünürlük
///   mantığı burada YOKTUR: listede olmayan (kapalı / yetkisiz) modülün kartı hiçbir koşulda çizilmez.
/// - Kart: modül görseli ([ModuleArt]) + menüdeki başlık + tek satır açıklama + (varsa) bekleyen / okunmamış rozeti.
///   Dokunmak çekmecede o öğeyi seçmekle AYNI gezinmedir ([onOpen]).
/// - [ShowcaseAudience.admin]: üstte koyu "Dikkat edilmesi gereken iş" barı (YALNIZ [badgeCounts] içinde bekleyen sayı
///   varsa; yeni veri kaynağı yok), altında ızgara.
/// - [ShowcaseAudience.resident]: üstte tek kart (Borcum açıksa ve borç bilgisi alınabildiyse "Güncel borcunuz" +
///   "Borcum'a git"; değilse selamlama), altında hızlı işlemler (yalnız modülü açık olanlar), sonra ızgara.
///   Kart YALNIZ ödenecek borç varken koyudur (eylem isteyen yer); selamlama, borç yok ve alacak düz beyaz karttır.
/// - Hesap / ayar türü öğeler ([showcaseSecondaryItems]) ızgarada değil, altta küçük "Hesap ve ayarlar" satırındadır.
/// - Izgara duyarlıdır (telefonda 2, geniş ekranda 3-4 sütun; büyük yazıda azalır); kartlar yüksekliğe göre sabit
///   değildir (taşma yok). Hareket azaltmada giriş animasyonu yoktur.
/// - Vitrin zemin BOYAMAZ ve kendi sınırının dışına hiçbir şey boyamaz. Açık temadaki düz #F8FAFC sayfa zeminini
///   sayfanın kaydırılan gövdesinin kabı verir ([pageBackgroundOf]). Koyu odak kutusu koyu temada zeminden ayrışan
///   lacivert yüzey + mavi kenarla çizilir. Hap düğmeler en az 48 dp ve klavye odağında halkalıdır ([_PillButton]).
class ModuleShowcaseView extends StatefulWidget {
  const ModuleShowcaseView({
    super.key,
    required this.session,
    required this.audience,
    required this.menuItems,
    required this.onOpen,
    this.badgeCounts = const <SirketMenuItem, int>{},
    this.badgeNouns = const <SirketMenuItem, String>{},
    this.fetchMyFinance,
    this.residentSiteName,
    this.applications,
    this.onReapply,
    this.onRefreshAccount,
    this.applicantRole = false,
    this.belowHero,
    this.aboveHero,
    this.onOpenHelp,
    this.debtSiteCodes,
    this.quickActionItems,
    this.onCreateGuestPass,
    this.onPay,
    this.monthPanel,
  }) : assert(applications == null || onReapply != null, 'başvuru kartı için onReapply gerekir');

  final UserSession session;
  final ShowcaseAudience audience;

  /// Yan menünün hesapladığı öğe listesi (`YanMenu.visibleItems`).
  final List<SirketMenuItem> menuItems;

  /// Karta dokunuldu: çekmecede [SirketMenuItem] seçmekle aynı gezinme.
  final ValueChanged<SirketMenuItem> onOpen;

  /// Çekmecedeki rozet sayıları ve ekran okuyucu sözcükleri (aynı harita).
  final Map<SirketMenuItem, int> badgeCounts;
  final Map<SirketMenuItem, String> badgeNouns;

  /// Sakin borç özeti kaynağı (`GET /app/my-finance`). Yalnız sakin vitrininde ve "Borcum" menüde GÖRÜNÜYORKEN
  /// çağrılır; null ise ya da hata verirse hero kart selamlamadır (asla "borç yok" denmez).
  final Future<MyFinance> Function()? fetchMyFinance;

  /// "Öde" (2A): tek borçlu daire varken o dairenin Öde sayfasını açar; verilmezse "Öde" düğmesi çıkmaz.
  final void Function(MyFinanceApartment item)? onPay;

  /// Sakin selamlamasının site satırı (modül verisinden); bilinmiyorsa null.
  final String? residentSiteName;

  /// Site başvurusu durumu (bireysel / daire kullanıcısı ve başvurusu gereken yönetici); null ise kart yok.
  final SiteApplicationTracker? applications;
  final Future<void> Function(SiteApplication previous)? onReapply;
  final Future<void> Function()? onRefreshAccount;

  /// Rol her zaman başvuran mı (bireysel / daire kullanıcısı)? Onaylandı kartı ve yükleme hatası yalnız o zaman çıkar.
  final bool applicantRole;

  /// Sakin hero kartının hemen altı (örn. "Yeni duyuru" kartı).
  final Widget? belowHero;

  /// Sakin hero kartının hemen ÜSTÜ (örn. okunmamış "Yeni duyuru" kartı; yoksa null / boş ve borç kartı en üsttedir).
  final Widget? aboveHero;

  /// Verilirse "Hesap ve ayarlar" satırında "Yardım ve Destek" çıkar.
  final VoidCallback? onOpenHelp;

  /// Borç özetinin kapsadığı siteler (alıcısı olunan ve Finans modülü AÇIK sitelerin kodları). Borcum menüde kalsa da
  /// bu küme değişince (bir sitede Finans kapandı, siteden ayrılındı) eski tutar GÖSTERİLMEZ ve özet yeniden okunur;
  /// özet yalnız bu sitelerin dairelerini içerir. null: süzgeç yok.
  final Set<int>? debtSiteCodes;

  /// Hızlı işlem olabilecek menü öğeleri (null: menüdeki her hızlı işlem öğesi). Daire bağı gerektiren eylemler
  /// ("Arıza bildir", "Ziyaretçi ve kargo") çağıran tarafından yalnız daire bağı olabilen sitede verilir.
  final Set<SirketMenuItem>? quickActionItems;

  /// Verilirse hızlı işlemlerde "Ziyaretçi kodu" çıkar: misafir / kurye için süreli geçiş linki oluşturur (kapı AÇMAZ).
  final VoidCallback? onCreateGuestPass;

  /// Yönetici "Bu ay" paneli (G5); yalnız yönetici kitlesinde ve finans açıkken verilir, yoksa görünmez.
  final Widget? monthPanel;

  /// Vitrin gösterilirken sayfa kabının (ana sayfada kaydırılan gövdenin kabı) zemini: açık temada DÜZ #F8FAFC
  /// ([AppShowcaseColors.background], işverenin "ana zemin"i), koyu temada null (koyu zemin olduğu gibi kalır).
  ///
  /// Zemini vitrinin kendisi çizmez: kaydırma görünümü içerik sığınca kırpmaz, vitrin sınırını aşan bir boya üstteki
  /// acil duyuru şeridini örterdi. Kap şeridin ALTINDAN ekranın altına kadar uzanır ve kaydırılmaz; vitrinin altında
  /// gösterilen bölümler (Geçiş Kontrol kapalı bireyselde ana ekran) de aynı düz zemindedir. Uygulamanın genel zemini
  /// (gradyan + ışıma) DEĞİŞMEZ; gradyanın alt tonu kart çerçevesiyle (#E2E8F0) aynı olduğundan vitrinde kullanılmaz.
  static Color? pageBackgroundOf(BuildContext context) =>
      context.palette.isDark ? null : AppShowcaseColors.background;

  @override
  State<ModuleShowcaseView> createState() => ModuleShowcaseViewState();
}

class ModuleShowcaseViewState extends State<ModuleShowcaseView> {
  MyFinance? _finance;
  bool _loadFailed = false;
  int _token = 0;

  bool _wantsDebt(ModuleShowcaseView w) =>
      w.audience == ShowcaseAudience.resident &&
      w.fetchMyFinance != null &&
      w.menuItems.contains(SirketMenuItem.borcum);

  @override
  void initState() {
    super.initState();
    if (_wantsDebt(widget)) unawaited(reload());
    unawaited(widget.applications?.ensureLoaded());
  }

  @override
  void didUpdateWidget(ModuleShowcaseView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wants = _wantsDebt(widget);
    if (wants && !_wantsDebt(oldWidget)) {
      // Borcum menüye yeni girdi (modül açıldı / veri geldi): özet okunur.
      unawaited(reload());
    } else if (!wants && _wantsDebt(oldWidget)) {
      // Borcum menüden çıktı (modül kapandı): eski tutar GÖSTERİLMEZ, uçuştaki yanıt yok sayılır.
      ++_token;
      _finance = null;
      _loadFailed = false;
    } else if (wants && !_sameSites(widget.debtSiteCodes, oldWidget.debtSiteCodes)) {
      // Borcum menüde kaldı ama kapsadığı site kümesi değişti (bir sitede Finans kapandı / açıldı, siteden ayrılındı):
      // eski tutar GÖSTERİLMEZ, uçuştaki yanıt yok sayılır ve özet yeniden okunur.
      ++_token;
      _finance = null;
      _loadFailed = false;
      unawaited(reload());
    }
    if (oldWidget.applications != widget.applications) {
      unawaited(widget.applications?.ensureLoaded());
    }
  }

  static bool _sameSites(Set<int>? a, Set<int>? b) =>
      a == null ? b == null : (b != null && a.length == b.length && a.containsAll(b));

  /// Özetten kapsam dışı (Finans'ı kapalı / bağı kalmamış) sitelerin daireleri atılır: sunucu da yalnız açık siteleri
  /// verir; bu, istemcideki son site kümesiyle ek güvencedir.
  MyFinance _scoped(MyFinance data) {
    final codes = widget.debtSiteCodes;
    if (codes == null || data.items.every((item) => codes.contains(item.siteCode))) return data;
    return MyFinance(items: [for (final item in data.items) if (codes.contains(item.siteCode)) item]);
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  /// Borç özetini yeniden okur (sayfa kabuğunun "aşağı çek yenile"sinden de çağrılır). Eski / geç yanıt yenisini ezmez.
  Future<void> reload() async {
    final fetch = widget.fetchMyFinance;
    if (fetch == null || !_wantsDebt(widget)) return;
    final token = ++_token;
    try {
      final data = await fetch();
      if (!mounted || token != _token) return;
      setState(() {
        _finance = _scoped(data);
        _loadFailed = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        // Eski tutar gösterilmez; modül kapalıysa sessiz selamlama, başka hatada kısa bilgi.
        _finance = null;
        _loadFailed = !isFinanceModuleDisabled(e);
      });
    }
  }

  void _open(SirketMenuItem item) => widget.onOpen(item);

  @override
  Widget build(BuildContext context) {
    final role = widget.session.role;
    final model = buildShowcaseModel(
      menuItems: widget.menuItems,
      role: role,
      badgeCounts: widget.badgeCounts,
      badgeNouns: widget.badgeNouns,
    );
    final audience = widget.audience;
    final focus = audience == ShowcaseAudience.admin
        ? buildFocusEntries(menuItems: widget.menuItems, badgeCounts: widget.badgeCounts)
        : const <ShowcaseFocusEntry>[];

    final children = <Widget>[
      if (widget.applications != null)
        SiteApplicationStatusCard(
          tracker: widget.applications!,
          onReapply: widget.onReapply!,
          onRefreshAccount: widget.applicantRole ? widget.onRefreshAccount : null,
          showApproved: widget.applicantRole,
          showLoadFailure: widget.applicantRole,
        ),
      if (focus.isNotEmpty) ...[
        _FocusBar(entries: focus, onOpen: _open),
        const SizedBox(height: AppSpace.lg),
      ],
      if (audience == ShowcaseAudience.admin && widget.monthPanel != null) widget.monthPanel!,
      if (audience == ShowcaseAudience.resident) ...[
        if (widget.aboveHero != null) widget.aboveHero!,
        _buildHero(context),
        const SizedBox(height: AppSpace.lg),
        if (widget.belowHero != null) widget.belowHero!,
        _buildQuickActions(context),
      ],
      if (model.grid.isNotEmpty) ...[
        _SectionTitle(
          key: const ValueKey<String>('panel_vitrin_baslik'),
          text: 'Modüller',
        ),
        const SizedBox(height: AppSpace.md),
        _ShowcaseGrid(
          key: const ValueKey<String>('panel_vitrin_izgara'),
          children: [
            for (final (index, entry) in model.grid.indexed)
              StaggeredEntry(
                index: index,
                child: _ModuleTile(entry: entry, onTap: () => _open(entry.item)),
              ),
          ],
        ),
      ],
      if (model.secondary.isNotEmpty || widget.onOpenHelp != null) ...[
        const SizedBox(height: AppSpace.xl),
        const _SectionTitle(text: 'Hesap ve ayarlar'),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          key: const ValueKey<String>('panel_vitrin_ikincil'),
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final entry in model.secondary)
              _SecondaryChip(
                label: entry.title,
                semanticLabel: entry.semanticLabel,
                icon: YanMenu.iconFor(entry.item),
                chipKey: ValueKey<String>('panel_ikincil_${entry.item.name}'),
                onTap: () => _open(entry.item),
              ),
            if (widget.onOpenHelp != null)
              _SecondaryChip(
                label: 'Yardım ve Destek',
                semanticLabel: 'Yardım ve Destek',
                icon: Icons.help_outline_rounded,
                chipKey: const ValueKey<String>('panel_ikincil_yardim'),
                onTap: widget.onOpenHelp!,
              ),
          ],
        ),
      ],
    ];

    return Column(
      key: const ValueKey<String>('panel_vitrin'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// Hero "Öde": tek borçlu daire varsa Öde sayfası, birden çoksa daire seçimi için Borcum.
  void _payFromHero() {
    final finance = _finance;
    final debtors = finance == null
        ? const <MyFinanceApartment>[]
        : [for (final i in finance.items) if (i.ownAccount.balanceMinor > 0) i];
    if (debtors.length == 1 && widget.onPay != null) {
      widget.onPay!(debtors.first);
    } else {
      _open(SirketMenuItem.borcum);
    }
  }

  /// Sakin hero kartı: borç özeti (Borcum açık + veri alındı) ya da selamlama.
  Widget _buildHero(BuildContext context) {
    final finance = _finance;
    final debtShown = finance != null && finance.items.isNotEmpty;
    final summary = debtShown ? summarizeMyFinance(finance) : null;
    final canOpenDebt = widget.menuItems.contains(SirketMenuItem.borcum);
    final siteLine = <String>[
      if (summary != null && summary.siteName.isNotEmpty)
        summary.siteName
      else if ((widget.residentSiteName ?? '').trim().isNotEmpty)
        widget.residentSiteName!.trim(),
      if (summary != null && summary.apartmentTitle.isNotEmpty && summary.apartmentTitle != '-')
        summary.apartmentTitle,
      // İP-1A: tutar kişinin KENDİ hesabıdır; tek dairede hesabın adı yazılır ("Kiracı hesabı").
      if (summary != null && summary.accountLabel.isNotEmpty) summary.accountLabel,
    ].join(' · ');
    if (summary != null) {
      return _DebtHero(
        key: const ValueKey<String>('panel_hero_borc'),
        summary: summary,
        siteLine: siteLine,
        onOpenDebt: () => _open(SirketMenuItem.borcum),
        onPay: summary.hasDebt && widget.onPay != null ? _payFromHero : null,
      );
    }
    final first = widget.session.fullName.trim().split(RegExp(r'\s+')).first;
    return _GreetingHero(
      key: const ValueKey<String>('panel_hero_selam'),
      greeting: first.isEmpty ? 'Hoş geldiniz' : 'Merhaba, $first',
      siteLine: siteLine,
      note: _loadFailed ? 'Borç bilginiz şu an alınamadı.' : null,
      onOpenDebt: canOpenDebt && _loadFailed ? () => _open(SirketMenuItem.borcum) : null,
    );
  }

  /// Hızlı işlemler (yalnız modülü AÇIK olanlar): menü listesinde olmayan eylem hiç çizilmez. Vitrinde hiçbir hızlı
  /// işlem kapı AÇMAZ: "Kapıyı aç" Kapılar sayfasını açar (kapı oradaki düğmeyle açılır), "Ziyaretçi kodu" yalnız süreli
  /// misafir geçiş linki üretir. Erişilebilir ipucu, dokununca olanı söyler.
  Widget _buildQuickActions(BuildContext context) {
    const defs = <(SirketMenuItem, String, String, ModuleArtKind)>[
      (SirketMenuItem.kapilar, 'Kapıyı aç', 'Kapılar sayfasını açar; kapı orada açılır', ModuleArtKind.door),
      (
        SirketMenuItem.taleplerim,
        'Arıza bildir',
        'Taleplerim sayfasını açar; yeni talep oradan bildirilir',
        ModuleArtKind.workTracking,
      ),
      (SirketMenuItem.ziyaretcilerim, 'Ziyaretçi ve kargo', 'Ziyaretçilerim sayfasını açar', ModuleArtKind.visitor),
      (SirketMenuItem.belgeler, 'Belgeler', 'Belgeler sayfasını açar', ModuleArtKind.documents),
    ];
    final allowed = widget.quickActionItems;
    final guestPass = widget.onCreateGuestPass;
    final tiles = <Widget>[
      for (final (item, title, hint, art) in defs) ...[
        if (widget.menuItems.contains(item) && (allowed == null || allowed.contains(item)))
          _QuickTile(
            tileKey: ValueKey<String>('panel_hizli_${item.name}'),
            title: title,
            hint: hint,
            art: art,
            onTap: () => _open(item),
          ),
        // İşverenin "Ziyaretçi Kodu (Kapı)" kutusu: "Arıza bildir"in hemen ardından.
        if (item == SirketMenuItem.taleplerim && guestPass != null)
          _QuickTile(
            tileKey: const ValueKey<String>('panel_hizli_ziyaretciKodu'),
            title: 'Ziyaretçi kodu',
            hint: 'Misafir ve kurye için süreli geçiş linki oluşturur; kapıyı açmaz',
            art: ModuleArtKind.accessCards,
            onTap: guestPass,
          ),
      ],
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(text: 'Hızlı işlemler'),
          const SizedBox(height: AppSpace.sm),
          _ShowcaseGrid(key: const ValueKey<String>('panel_hizli_izgara'), children: tiles),
        ],
      ),
    );
  }
}

/// Bölüm başlığı (küçük, kalın; başlık düğümü).
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

/// Duyarlı kart ızgarası: sütun sayısı genişliğe ve yazı ölçeğine göre ([showcaseColumns]); her satırın kartları AYNI
/// yüksekliktedir (içerik uzayınca satır birlikte uzar, taşma olmaz).
class _ShowcaseGrid extends StatelessWidget {
  const _ShowcaseGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = showcaseColumns(constraints.maxWidth, scale);
        const gap = AppSpace.md;
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) const SizedBox(width: gap),
                    Expanded(
                      child: start + c < children.length ? children[start + c] : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: gap),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// Düz beyaz kart yüzeyi: ince çerçeve, gölge yok (koyu temada palet yüzeyi).
ShapeBorder _cardShape(AppPalette p) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(color: _cardBorder(p)),
    );

/// Modül kartı: görsel + başlık + açıklama + rozet. Tek erişilebilir düğme (etiket = başlık + rozet).
class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.entry, required this.onTap});

  final ShowcaseEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      button: true,
      label: entry.semanticLabel,
      hint: entry.description,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        key: ValueKey<String>('panel_kart_${entry.item.name}'),
        color: _cardColor(p),
        shape: _cardShape(p),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Görsel solda, rozet sağda. Dar kartta (320 dp telefonda iki sütun: kart içi ~114 dp) ya da büyük
                  // yazıda rozet sığmazsa görselin ALTINA iner (taşma yok). Wrap, satırların eşit yüksekliği için
                  // gereken iç boyut ölçümünü destekler (LayoutBuilder desteklemez).
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        ModuleArt(kind: entry.art, size: 56),
                        if (entry.badge > 0) _CountDot(count: entry.badge),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(entry.title, style: th.titleMedium),
                  if (entry.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(entry.description, style: th.bodySmall?.copyWith(color: _bodyInk(p))),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rozet: metnin soluna nokta + sayı (arka planı boyamaz; 99'dan büyük "99+"). Dekoratiftir: sayı kartın erişilebilirlik
/// etiketindedir. Noktanın rengi çekmecedeki sayı rozetinin ([YanMenu]) dolgusuyla AYNI belirteçtir ([AppTone.danger]
/// `a`): aynı bekleyen / okunmamış sayısı çekmecede ve Panel'de aynı renkte görünür. Vitrinin öteki durum noktaları
/// (borç kartı, dikkat barı) işverenin tablosundaki renklerde kalır ([AppShowcaseColors]).
class _CountDot extends StatelessWidget {
  const _CountDot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey<String>('panel_kart_rozet'),
        decoration: BoxDecoration(
          color: p.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: p.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(color: AppTone.danger.a),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Text(
                  count > 99 ? '99+' : '$count',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: p.text,
                        fontWeight: FontWeight.w800,
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

/// Durum noktası (8 dp). [edge]: açık yüzeyde dolgusu zemine 3:1'i tutmayan nokta (kehribar beyazda ~2,1:1) için 1 dp
/// koyu kenar; nokta işverenin rengini korur, sınırı seçilir.
class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.edge});

  final Color color;
  final Color? edge;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey<String>('panel_durum_noktasi'),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: edge == null ? null : Border.all(color: edge!),
      ),
      child: const SizedBox.square(dimension: 8),
    );
  }
}

/// Hızlı işlem kutusu: küçük görsel + tek başlık (yan yana); kart gibi düz beyaz, tek düğme. Ekran okuyucu ipucu
/// ([hint]) dokununca olanı söyler (örn. "Kapılar sayfasını açar").
class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.tileKey,
    required this.title,
    required this.hint,
    required this.art,
    required this.onTap,
  });

  final Key tileKey;
  final String title;
  final String hint;
  final ModuleArtKind art;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      button: true,
      label: title,
      hint: hint,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        key: tileKey,
        color: _cardColor(p),
        shape: _cardShape(p),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(
                children: [
                  ModuleArt(kind: art, size: 40),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(title, style: th.titleMedium)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Hesap ve ayarlar" satırındaki küçük düğme (profil, eller serbest, yardım vb.): en az 48 dp yüksek (dokunma hedefi).
class _SecondaryChip extends StatelessWidget {
  const _SecondaryChip({
    required this.label,
    required this.semanticLabel,
    required this.icon,
    required this.chipKey,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final IconData icon;
  final Key chipKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        key: chipKey,
        color: _cardColor(p),
        shape: _cardShape(p),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: _bodyInk(p)),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(
                    child: Text(label, style: th.bodyMedium?.copyWith(color: _bodyInk(p), fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Koyu odak kutusu: YALNIZ eylem isteyen yerde (ödenecek borç kartı, yönetici dikkat barı; işveren talimatı 3: "koyu
/// renk yalnız aksiyon isteyen yerde"). Açık temada gece kömürü (#0F172A) + ince kenar. Koyu temada sayfa zemini de koyu
/// (#0F172A -> #020617) olduğundan kutu zeminden ayrışan lacivert yüzeyle (#172554) ve zemine de kutuya da en az 3:1
/// kontrastlı 1,5 dp mavi kenarla çizilir (koyu temada da göz önce bu kutuyu görür).
class _FocusSurface extends StatelessWidget {
  const _FocusSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.palette.isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? AppShowcaseColors.focusDark : AppShowcaseColors.focus,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: dark
            ? Border.all(color: AppTone.primary.hue, width: 1.5)
            : Border.all(color: AppShowcaseColors.focusBorder),
      ),
      child: Padding(padding: const EdgeInsets.all(AppSpace.lg), child: child),
    );
  }
}

/// Düz üst kart (eylem istemeyen durum: selamlama, borç yok, alacak): modül kartlarıyla aynı yüzey; açıkta beyaz + ince
/// #E2E8F0 çerçeve, koyuda palet yüzeyi; gölge yok.
class _PlainSurface extends StatelessWidget {
  const _PlainSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _cardColor(p),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: _cardBorder(p)),
      ),
      child: Padding(padding: const EdgeInsets.all(AppSpace.lg), child: child),
    );
  }
}

/// Ana eylem düğmesi (hap): en az 48 x 48 dp. [onDark] true ise koyu yüzeyde açık hap (#F8FAFC zemin, #0F172A metin);
/// değilse açık yüzeyde koyu hap (#0F172A zemin, #F8FAFC metin: işverenin "ana buton" rengi).
///
/// Klavye odağı iki temada da görünür: hapın 2 dp dışında 2 dp halka (yanındaki yüzeye >= 3:1: koyu yüzeyde #93C5FD,
/// açıkta #1D4ED8) ve hapın metin tonunda odak / üzerine gelme / basma rengi. Temanın varsayılanı (koyu temada beyaz
/// %12) açık hapın üstünde görünmüyordu. Ekran okuyucu adı [semanticLabel] (verilmezse [label]); görünen metni İÇERİR
/// (WCAG 2.5.3), tek düğümdür.
class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.label,
    required this.onTap,
    required this.onDark,
    this.semanticLabel,
    this.buttonKey,
  });

  final String label;
  final String? semanticLabel;
  final VoidCallback onTap;
  final bool onDark;
  final Key? buttonKey;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onDark = widget.onDark;
    final fill = onDark ? AppShowcaseColors.onFocus : AppShowcaseColors.focus;
    final ink = onDark ? AppShowcaseColors.focus : AppShowcaseColors.onFocus;
    final ring = onDark ? AppTone.primary.inkDark : AppTone.primary.inkLight;
    final pill = Material(
      key: widget.buttonKey,
      color: fill,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (focused) {
          if (focused != _focused) setState(() => _focused = focused);
        },
        focusColor: ink.withValues(alpha: 0.16),
        hoverColor: ink.withValues(alpha: 0.08),
        highlightColor: ink.withValues(alpha: 0.10),
        splashColor: ink.withValues(alpha: 0.16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                Icon(Icons.arrow_forward_rounded, size: 18, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      button: true,
      label: widget.semanticLabel ?? widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          pill,
          if (_focused)
            Positioned(
              left: -4,
              top: -4,
              right: -4,
              bottom: -4,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey<String>('panel_hap_odak'),
                  decoration: ShapeDecoration(
                    shape: StadiumBorder(side: BorderSide(color: ring, width: 2)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Yönetici odak barı: "Dikkat edilmesi gereken N iş var" + her satırda tek düğme (ilgili sayfaya gider).
class _FocusBar extends StatelessWidget {
  const _FocusBar({required this.entries, required this.onOpen});

  final List<ShowcaseFocusEntry> entries;
  final ValueChanged<SirketMenuItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final n = entries.length;
    return _FocusSurface(
      key: const ValueKey<String>('panel_odak_bar'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.bolt_rounded, size: 20, color: AppShowcaseColors.statusWarn),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    'Dikkat edilmesi gereken $n iş var',
                    style: th.titleMedium?.copyWith(color: AppShowcaseColors.onFocus, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          for (final entry in entries) ...[
            const SizedBox(height: AppSpace.md),
            _FocusRow(entry: entry, onTap: () => onOpen(entry.item)),
          ],
        ],
      ),
    );
  }
}

/// Odak barı satırı: nokta + metin + tek düğme. Düğmenin ekran okuyucu adı satırın bağlamlı etiketidir
/// ([ShowcaseFocusEntry.semanticLabel], örn. "2 bekleyen site başvurusu. İncele"): birden çok "İncele" düğmesi
/// birbirinden ayrılır (WCAG 2.4.6). Satır metni bu adın içinde olduğundan ayrıca okunmaz (iki kez duyulmasın).
class _FocusRow extends StatelessWidget {
  const _FocusRow({required this.entry, required this.onTap});

  final ShowcaseFocusEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final text = ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: _Dot(color: AppShowcaseColors.statusWarn),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(entry.text, style: th.bodyLarge?.copyWith(color: AppShowcaseColors.onFocus)),
          ),
        ],
      ),
    );
    final button = _PillButton(
      buttonKey: ValueKey<String>('panel_odak_${entry.item.name}'),
      label: entry.action,
      semanticLabel: entry.semanticLabel,
      onDark: true,
      onTap: onTap,
    );
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Dar ekranda ya da büyük yazıda düğme metnin ALTINA iner (yan yana sığmayıp taşmasın).
        final sideBySide = constraints.maxWidth >= 420 && scale <= 1.3;
        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: text),
              const SizedBox(width: AppSpace.md),
              button,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            text,
            const SizedBox(height: AppSpace.sm),
            Align(alignment: AlignmentDirectional.centerStart, child: button),
          ],
        );
      },
    );
  }
}

/// Sakin hero kartı, borç durumu: "Güncel borcunuz" + tutar + vade bilgisi + "Borcum'a git".
///
/// Koyu odak kutusu YALNIZ ödenecek borç varken ([DebtSummary.hasDebt]); "Borcunuz yok" ve "Alacağınız" eylem istemez,
/// düz karttır. Ekran okuyucu görünen satırların TÜMÜNÜ tek düğümde okur (site / daire, tutar, vadesi geçen, sıradaki
/// vade, alacak); tutarlar Borcum ekranındaki gibi "üç bin iki yüz elli lira" biçimindedir ([moneySemanticLabel]).
/// "Borcum'a git" ayrı düğme düğümüdür (adı görünen metin).
class _DebtHero extends StatelessWidget {
  const _DebtHero({
    super.key,
    required this.summary,
    required this.siteLine,
    required this.onOpenDebt,
    this.onPay,
  });

  final DebtSummary summary;
  final String siteLine;
  final VoidCallback onOpenDebt;

  /// Verilirse (borç varken) birincil "Öde" düğmesi çıkar; "Borcum'a git" ikincil kalır.
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final s = summary;
    final focus = s.hasDebt;
    final strong = focus ? AppShowcaseColors.onFocus : p.text;
    final muted = focus ? AppShowcaseColors.onFocusMuted : _bodyInk(p);
    final String caption;
    final String amount;
    final String spokenAmount;
    if (s.hasDebt) {
      caption = 'Güncel borcunuz';
      amount = formatMinor(s.debtMinor);
      spokenAmount = moneySemanticLabel(s.debtMinor);
    } else if (s.hasCredit) {
      caption = 'Alacağınız';
      amount = formatMinor(s.creditMinor);
      spokenAmount = moneySemanticLabel(s.creditMinor);
    } else {
      caption = 'Borç durumunuz';
      amount = 'Borcunuz yok';
      spokenAmount = amount;
    }
    // (nokta, görünen metin, okunan metin)
    final lines = <(Color?, String, String)>[
      if (s.hasDebt && s.overdueMinor > 0)
        (
          AppShowcaseColors.statusCrit,
          'Vadesi geçen: ${formatMinor(s.overdueMinor)}',
          'Vadesi geçen: ${moneySemanticLabel(s.overdueMinor)}',
        ),
      if (s.hasDebt && s.nextDue != null)
        (
          AppShowcaseColors.statusWarn,
          'Sıradaki vade: ${formatCrmDate(s.nextDue)}',
          'Sıradaki vade: ${formatCrmDate(s.nextDue)}',
        ),
      if (s.hasDebt && s.hasCredit)
        (
          null,
          'Alacağınız: ${formatMinor(s.creditMinor)}',
          'Alacağınız: ${moneySemanticLabel(s.creditMinor)}',
        ),
    ];
    final spoken = <String>[
      // "Güneş Sitesi · A Blok / D:3": ayırıcı nokta okunmaz, virgül duraklatır.
      if (siteLine.isNotEmpty) siteLine.replaceAll(' · ', ', '),
      '$caption: $spokenAmount',
      for (final (_, _, said) in lines) said,
    ].join('. ');
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey<String>('panel_hero_ozet'),
          container: true,
          label: '$spoken.',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (siteLine.isNotEmpty) ...[
                  Text(siteLine, style: th.bodySmall?.copyWith(color: muted)),
                  const SizedBox(height: AppSpace.sm),
                ],
                Text(
                  caption,
                  style: th.bodyMedium?.copyWith(color: muted, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  amount,
                  key: const ValueKey<String>('panel_hero_tutar'),
                  style: th.headlineMedium?.copyWith(color: strong),
                ),
                for (final (dot, shown, _) in lines) ...[
                  const SizedBox(height: AppSpace.xs),
                  _HeroLine(dot: dot, text: shown, color: muted),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              if (onPay != null)
                _PillButton(
                  buttonKey: const ValueKey<String>('panel_hero_ode'),
                  label: 'Öde',
                  onDark: focus || p.isDark,
                  onTap: onPay!,
                ),
              _PillButton(
                buttonKey: const ValueKey<String>('panel_hero_borcuma_git'),
                label: "Borcum'a git",
                // Koyu kutuda ve koyu temanın düz kartında açık hap; açık temanın düz kartında koyu (#0F172A) ana düğme.
                onDark: focus || p.isDark,
                onTap: onOpenDebt,
              ),
            ],
          ),
        ),
      ],
    );
    return focus ? _FocusSurface(child: content) : _PlainSurface(child: content);
  }
}

class _HeroLine extends StatelessWidget {
  const _HeroLine({required this.dot, required this.text, required this.color, this.dotEdge});

  final Color? dot;
  final String text;
  final Color color;
  final Color? dotEdge;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dot != null) ...[
          Padding(padding: const EdgeInsets.only(top: 5), child: _Dot(color: dot!, edge: dotEdge)),
          const SizedBox(width: AppSpace.sm),
        ],
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Sakin hero kartı, selamlama (borç bilgisi yokken / alınamazken): "Merhaba, Ad" + site bilgisi. Eylem istemediği için
/// düz karttır (koyu değil); borç bilgisi alınamadıysa kısa not ve "Borcum'a git" ana düğmesi.
class _GreetingHero extends StatelessWidget {
  const _GreetingHero({
    super.key,
    required this.greeting,
    required this.siteLine,
    this.note,
    this.onOpenDebt,
  });

  final String greeting;
  final String siteLine;
  final String? note;
  final VoidCallback? onOpenDebt;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final muted = _bodyInk(p);
    return _PlainSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(greeting, style: th.headlineMedium),
          ),
          if (siteLine.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(siteLine, style: th.bodyMedium?.copyWith(color: muted)),
          ],
          if (note != null) ...[
            const SizedBox(height: AppSpace.sm),
            _HeroLine(
              dot: AppShowcaseColors.statusWarn,
              // Beyaz kartta kehribar nokta ~2,1:1: sınırı koyu kehribar kenarla seçilir (>= 3:1).
              dotEdge: p.isDark ? null : AppTone.warning.a,
              text: note!,
              color: muted,
            ),
          ],
          if (onOpenDebt != null) ...[
            const SizedBox(height: AppSpace.lg),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _PillButton(
                buttonKey: const ValueKey<String>('panel_hero_borcuma_git'),
                label: "Borcum'a git",
                onDark: p.isDark,
                onTap: onOpenDebt!,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
