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

/// Odak kutusunun (koyu kart) zemini: yalnız dikkat isteyen yerde (Panel tasarım kuralı: %90 açık, %10 koyu).
const Color _kFocusColor = Color(0xFF0F172A);
const Color _kFocusText = Color(0xFFF8FAFC);
const Color _kFocusMuted = Color(0xFFCBD5E1);

/// Durum noktaları (metnin soluna küçük nokta; arka planı boyamaz).
const Color _kDotWarning = Color(0xFFF59E0B);
const Color _kDotDanger = Color(0xFFE11D48);

/// Panel: MODÜL VİTRİNİ. Girişten sonra herkesi karşılayan ekran; kapı paneli artık "Kapılar" kartının arkasındadır.
///
/// - Kartlar yan menünün hesapladığı öğe listesinden ([menuItems], `YanMenu.visibleItems`) türetilir; görünürlük
///   mantığı burada YOKTUR: listede olmayan (kapalı / yetkisiz) modülün kartı hiçbir koşulda çizilmez.
/// - Kart: modül görseli ([ModuleArt]) + menüdeki başlık + tek satır açıklama + (varsa) bekleyen / okunmamış rozeti.
///   Dokunmak çekmecede o öğeyi seçmekle AYNI gezinmedir ([onOpen]).
/// - [ShowcaseAudience.admin]: üstte koyu "Dikkat edilmesi gereken iş" barı (YALNIZ [badgeCounts] içinde bekleyen sayı
///   varsa; yeni veri kaynağı yok), altında ızgara.
/// - [ShowcaseAudience.resident]: üstte koyu tek kart (Borcum açıksa ve borç bilgisi alınabildiyse "Güncel borcunuz" +
///   "Borcum'a git"; değilse selamlama), altında hızlı işlemler (yalnız modülü açık olanlar), sonra ızgara.
/// - Hesap / ayar türü öğeler ([showcaseSecondaryItems]) ızgarada değil, altta küçük "Hesap ve ayarlar" satırındadır.
/// - Izgara duyarlıdır (telefonda 2, geniş ekranda 3-4 sütun; büyük yazıda azalır); kartlar yüksekliğe göre sabit
///   değildir (taşma yok). Hareket azaltmada giriş animasyonu yoktur.
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
    this.onOpenHelp,
    this.debtSiteCodes,
    this.quickActionItems,
    this.onCreateGuestPass,
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
      if (audience == ShowcaseAudience.resident) ...[
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
    ].join(' · ');
    if (summary != null) {
      return _DebtHero(
        key: const ValueKey<String>('panel_hero_borc'),
        summary: summary,
        siteLine: siteLine,
        onOpenDebt: () => _open(SirketMenuItem.borcum),
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
      side: BorderSide(color: p.border),
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
        color: p.surface,
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ModuleArt(kind: entry.art, size: 56),
                      const Spacer(),
                      if (entry.badge > 0) _CountDot(count: entry.badge),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(entry.title, style: th.titleMedium),
                  if (entry.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(entry.description, style: th.bodySmall?.copyWith(color: p.textSecondary)),
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

/// Rozet: metnin soluna durum noktası + sayı (arka planı boyamaz; 99'dan büyük "99+"). Dekoratiftir: sayı kartın
/// erişilebilirlik etiketindedir.
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
              const _Dot(color: _kDotDanger),
              const SizedBox(width: AppSpace.xs),
              Text(
                count > 99 ? '99+' : '$count',
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: p.text,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
        color: p.surface,
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

/// "Hesap ve ayarlar" satırındaki küçük düğme (profil, eller serbest, yardım vb.): en az 44 dp yüksek.
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
        color: p.surface,
        shape: _cardShape(p),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: p.textSecondary),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(
                    child: Text(label, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
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

/// Koyu odak yüzeyi (#0F172A): ince çerçeve koyu temada da kartı sayfa zemininden ayırır.
class _FocusSurface extends StatelessWidget {
  const _FocusSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.palette.isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kFocusColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: dark ? const Color(0x24FFFFFF) : const Color(0xFF1E293B)),
      ),
      child: Padding(padding: const EdgeInsets.all(AppSpace.lg), child: child),
    );
  }
}

/// Koyu bar üstündeki açık düğme (ana eylem): metin #0F172A, en az 44 dp.
class _OnDarkButton extends StatelessWidget {
  const _OnDarkButton({required this.label, required this.onTap, this.buttonKey});

  final String label;
  final VoidCallback onTap;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        key: buttonKey,
        color: _kFocusText,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: _kFocusColor,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  const Icon(Icons.arrow_forward_rounded, size: 18, color: _kFocusColor),
                ],
              ),
            ),
          ),
        ),
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
                  child: Icon(Icons.bolt_rounded, size: 20, color: _kDotWarning),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    'Dikkat edilmesi gereken $n iş var',
                    style: th.titleMedium?.copyWith(color: _kFocusText, fontWeight: FontWeight.w800),
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

class _FocusRow extends StatelessWidget {
  const _FocusRow({required this.entry, required this.onTap});

  final ShowcaseFocusEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final text = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: _Dot(color: _kDotWarning),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(entry.text, style: th.bodyLarge?.copyWith(color: _kFocusText)),
        ),
      ],
    );
    final button = _OnDarkButton(
      buttonKey: ValueKey<String>('panel_odak_${entry.item.name}'),
      label: entry.action,
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
class _DebtHero extends StatelessWidget {
  const _DebtHero({
    super.key,
    required this.summary,
    required this.siteLine,
    required this.onOpenDebt,
  });

  final DebtSummary summary;
  final String siteLine;
  final VoidCallback onOpenDebt;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final String caption;
    final String amount;
    if (summary.hasDebt) {
      caption = 'Güncel borcunuz';
      amount = formatMinor(summary.debtMinor);
    } else if (summary.hasCredit) {
      caption = 'Alacağınız';
      amount = formatMinor(summary.creditMinor);
    } else {
      caption = 'Borç durumunuz';
      amount = 'Borcunuz yok';
    }
    final lines = <Widget>[
      if (summary.hasDebt && summary.overdueMinor > 0)
        _HeroLine(
          dot: _kDotDanger,
          text: 'Vadesi geçen: ${formatMinor(summary.overdueMinor)}',
        ),
      if (summary.hasDebt && summary.nextDue != null)
        _HeroLine(dot: _kDotWarning, text: 'Sıradaki vade: ${formatCrmDate(summary.nextDue)}'),
      if (summary.hasDebt && summary.hasCredit)
        _HeroLine(dot: null, text: 'Alacağınız: ${formatMinor(summary.creditMinor)}'),
    ];
    return _FocusSurface(
      child: Semantics(
        container: true,
        label: '$caption: $amount',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (siteLine.isNotEmpty) ...[
                    Text(siteLine, style: th.bodySmall?.copyWith(color: _kFocusMuted)),
                    const SizedBox(height: AppSpace.sm),
                  ],
                  Text(
                    caption,
                    style: th.bodyMedium?.copyWith(color: _kFocusMuted, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    amount,
                    key: const ValueKey<String>('panel_hero_tutar'),
                    style: th.headlineMedium?.copyWith(color: _kFocusText),
                  ),
                  for (final line in lines) ...[
                    const SizedBox(height: AppSpace.xs),
                    line,
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _OnDarkButton(
                buttonKey: const ValueKey<String>('panel_hero_borcuma_git'),
                label: "Borcum'a git",
                onTap: onOpenDebt,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroLine extends StatelessWidget {
  const _HeroLine({required this.dot, required this.text});

  final Color? dot;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dot != null) ...[
          Padding(padding: const EdgeInsets.only(top: 5), child: _Dot(color: dot!)),
          const SizedBox(width: AppSpace.sm),
        ],
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _kFocusMuted),
          ),
        ),
      ],
    );
  }
}

/// Sakin hero kartı, selamlama (borç bilgisi yokken / alınamazken): "Merhaba, Ad" + site bilgisi.
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
    return _FocusSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(greeting, style: th.headlineMedium?.copyWith(color: _kFocusText)),
          ),
          if (siteLine.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(siteLine, style: th.bodyMedium?.copyWith(color: _kFocusMuted)),
          ],
          if (note != null) ...[
            const SizedBox(height: AppSpace.sm),
            _HeroLine(dot: _kDotWarning, text: note!),
          ],
          if (onOpenDebt != null) ...[
            const SizedBox(height: AppSpace.lg),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _OnDarkButton(
                buttonKey: const ValueKey<String>('panel_hero_borcuma_git'),
                label: "Borcum'a git",
                onTap: onOpenDebt!,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
