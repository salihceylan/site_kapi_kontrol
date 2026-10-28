// P2-21: bağlam şeridi. Ekranın üstünde, uygulamanın hangi site + daire + rolle gösterildiğini söyleyen küçük şerit
// ("Ay Sitesi · A Blok / 5 · Sakin"). YALNIZ birden çok siteye ya da daireye bağlı kullanıcıda çıkar (tek site + tek
// dairede karışacak bir şey yoktur; ekran eskisi gibidir). Dokununca değiştirme varsa oraya götürür: yönetici
// kitlesinde site seçici, sakin kitlesinde "Dairem" (tüm dairelerin listesi).
//
// - [composeContextStrip]: saf mantık (görünürlük, metinler, dokunma eylemi); widget testi gerektirmez.
// - [ContextStrip]: yalnız çizim (düz yüzey + 1 px kenar, 44 dp dokunma hedefi, taşma yok).
// - [ContextStripHost]: dairelerini (ilk açılışta ve her başarılı yenilemede) yükler ve şeridi kurar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart' show ShowcaseAudience;
import 'package:site_kapi_kontrol/ui/helpers/refresh_status.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show isLargeText;

/// Şeritteki site ve sitedeki rolü (`my-modules`).
@immutable
class ContextSite {
  const ContextSite({required this.code, required this.name, this.role = 'resident'});

  final int code;
  final String name;

  /// `manager`, `resident`, `board_member` ya da `staff`.
  final String role;

  /// Görünen ad; ad boşsa teknik site kodu gösterilmez.
  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();
}

/// Kullanıcının bir dairesi (şeritte "A Blok / 5").
@immutable
class ContextApartment {
  const ContextApartment({required this.siteCode, required this.label});

  final int siteCode;
  final String label;
}

/// Şeride dokunulunca ne olur?
enum ContextStripAction {
  /// Dokunma eylemi yok (yalnız bilgi).
  none,

  /// Site seçici açılır (yönetici kitlesi, en az iki site).
  pickSite,

  /// "Dairem" sayfası açılır (sakin kitlesi: tüm daireler orada).
  openApartments,
}

/// Şeridin içeriği (saf veri).
@immutable
class ContextStripData {
  const ContextStripData({
    required this.siteLabel,
    required this.roleLabel,
    this.apartmentLabel,
    this.action = ContextStripAction.none,
  });

  final String siteLabel;
  final String roleLabel;
  final String? apartmentLabel;
  final ContextStripAction action;

  /// Ekran okuyucu özeti.
  String get semanticsLabel {
    final apartment = apartmentLabel;
    return '$siteLabel${apartment == null ? '' : ', $apartment'}, $roleLabel olarak görüntüleniyor';
  }

  /// Dokunma eyleminin ekran okuyucu ipucu; eylem yoksa null.
  String? get semanticsHint => switch (action) {
        ContextStripAction.pickSite => 'Siteyi değiştirmek için dokunun',
        ContextStripAction.openApartments => 'Dairelerinizi görmek için dokunun',
        ContextStripAction.none => null,
      };
}

/// Şeridin içeriğini hesaplar; şerit gerekmiyorsa null.
///
/// - Gerekli mi: en az iki site YA DA (yönetici kitlesi dışında) en az iki daire. Tek site + tek dairede şerit yoktur.
/// - Site: seçili site; yoksa tek site adı; yoksa "Tüm siteler (N)" (seçici varken) ya da "İlk site +N site".
/// - Daire (yönetici kitlesinde yok): kapsamdaki tek dairenin adı, birden çoksa "N daire", hiç yoksa yok.
/// - Rol: odaktaki sitedeki rol (Yönetim Kurulu / Görevli), yoksa kitle (Yönetici / Sakin / Bireysel).
/// - Eylem: [siteSelectable] ise site seçici; değilse [canOpenApartments] ise "Dairem"; yoksa yok.
ContextStripData? composeContextStrip({
  required ShowcaseAudience audience,
  required List<ContextSite> sites,
  int? scopeSiteCode,
  List<ContextApartment> apartments = const <ContextApartment>[],
  bool siteSelectable = false,
  bool canOpenApartments = false,
}) {
  if (sites.isEmpty) return null;
  final pool = audience == ShowcaseAudience.admin ? const <ContextApartment>[] : apartments;
  if (sites.length < 2 && pool.length < 2) return null;

  ContextSite? scope;
  for (final site in sites) {
    if (site.code == scopeSiteCode) scope = site;
  }
  final focus = scope ?? (sites.length == 1 ? sites.first : null);

  final String siteLabel;
  if (scope != null) {
    siteLabel = scope.label;
  } else if (sites.length == 1) {
    siteLabel = sites.first.label;
  } else if (siteSelectable) {
    siteLabel = 'Tüm siteler (${sites.length})';
  } else {
    siteLabel = '${sites.first.label} +${sites.length - 1} site';
  }

  final inScope = scope == null ? pool : pool.where((a) => a.siteCode == scope!.code).toList(growable: false);
  final String? apartmentLabel = switch (inScope.length) {
    0 => null,
    1 => inScope.single.label.trim().isEmpty ? 'Daire' : inScope.single.label.trim(),
    final n => '$n daire',
  };

  final roleLabel = switch (focus?.role) {
    'board_member' => 'Yönetim Kurulu',
    'staff' => 'Görevli',
    _ => switch (audience) {
        ShowcaseAudience.admin => 'Yönetici',
        ShowcaseAudience.resident => 'Sakin',
        ShowcaseAudience.individual => 'Bireysel',
      },
  };

  final action = siteSelectable && sites.length >= 2
      ? ContextStripAction.pickSite
      : (canOpenApartments ? ContextStripAction.openApartments : ContextStripAction.none);

  return ContextStripData(
    siteLabel: siteLabel,
    apartmentLabel: apartmentLabel,
    roleLabel: roleLabel,
    action: action,
  );
}

/// Bağlam şeridinin çizimi. [onTap] null ise yalnız bilgidir (dokunma eylemi ve ok yok).
///
/// Düz yüzey + 1 px kenar (sade stil); metin en çok 2 satır (büyük yazıda 3) ve elips: taşma yok. Dokunma hedefi
/// en az 44 dp. Ekran okuyucu tek düğüm okur: "Ay Sitesi, A Blok / 5, Sakin olarak görüntüleniyor".
class ContextStrip extends StatelessWidget {
  const ContextStrip({super.key, required this.data, this.onTap});

  final ContextStripData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final base = th.bodySmall?.copyWith(color: p.textSecondary);
    final strong = base?.copyWith(color: p.text, fontWeight: FontWeight.w700);
    final apartment = data.apartmentLabel;
    final text = Text.rich(
      TextSpan(
        style: base,
        children: <InlineSpan>[
          TextSpan(text: data.siteLabel, style: strong),
          if (apartment != null) TextSpan(text: ' · $apartment'),
          TextSpan(text: ' · ${data.roleLabel}'),
        ],
      ),
      maxLines: isLargeText(context) ? 3 : 2,
      overflow: TextOverflow.ellipsis,
    );
    final tappable = onTap != null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Row(
        children: [
          Icon(Icons.apartment_rounded, size: 18, color: p.textSecondary),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: text),
          if (tappable) ...[
            const SizedBox(width: AppSpace.sm),
            Icon(
              data.action == ContextStripAction.pickSite ? Icons.unfold_more_rounded : Icons.chevron_right_rounded,
              size: 20,
              color: p.textSecondary,
            ),
          ],
        ],
      ),
    );
    final surface = Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: tappable ? InkWell(onTap: onTap, child: row) : row,
    );
    return Semantics(
      key: const ValueKey<String>('baglam_seridi'),
      container: true,
      button: tappable,
      label: data.semanticsLabel,
      hint: data.semanticsHint,
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 44), child: surface),
    );
  }
}

/// Site seçimi: seçenek penceresinden dönen değer (null = "Tüm siteler"; pencere kapandıysa seçim yok).
class _SiteChoice {
  const _SiteChoice(this.code);

  final int? code;
}

/// Siteleri listeleyen alt sayfa: "Tüm siteler" + siteler, seçili olan işaretli. Büyük yazıda kaydırılır.
class ContextSitePickerSheet extends StatelessWidget {
  const ContextSitePickerSheet({super.key, required this.sites, required this.selectedCode});

  final List<ContextSite> sites;
  final int? selectedCode;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final options = <(int?, String)>[
      (null, 'Tüm siteler'),
      for (final site in sites) (site.code, site.label),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.sm),
              child: Semantics(
                header: true,
                child: Text('Site seçin', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: p.text)),
              ),
            ),
            for (final (code, label) in options)
              ListTile(
                key: ValueKey<String>('baglam_site_secenek_${code ?? 'tum'}'),
                leading: Icon(Icons.apartment_rounded, color: p.textSecondary),
                title: Text(label, maxLines: 3, overflow: TextOverflow.ellipsis),
                selected: code == selectedCode,
                selectedColor: p.text,
                trailing: code == selectedCode ? Icon(Icons.check_rounded, color: p.text) : null,
                onTap: () => Navigator.of(context).pop(_SiteChoice(code)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bağlam şeridinin sahibi: kullanıcının dairelerini (yönetici kitlesi dışında; ilk açılışta, kullanıcı değişince ve her
/// başarılı genel yenilemede) [loadApartments] ile yükler ve [composeContextStrip] sonucunu çizer; gerekmiyorsa hiçbir
/// şey çizmez. [loadApartments] null ise daire parçası olmaz (testler; uygulama kökü gerçek servisi bağlar).
///
/// Daire yüklemesi hata verirse şerit dairesiz çizilir (sessiz geri çekilme: şerit bilgi amaçlıdır, ekranı bozmaz).
class ContextStripHost extends StatefulWidget {
  const ContextStripHost({
    super.key,
    required this.userId,
    required this.audience,
    required this.sites,
    this.scopeSiteCode,
    this.loadApartments,
    this.refresh,
    this.onPickSite,
    this.onOpenApartments,
  });

  /// Oturumdaki kullanıcı (değişirse daireler yeniden yüklenir, eski kullanıcınınki gösterilmez).
  final int userId;
  final ShowcaseAudience audience;
  final List<ContextSite> sites;
  final int? scopeSiteCode;
  final Future<List<ContextApartment>> Function()? loadApartments;

  /// Genel yenileme durumu: her başarılı yenilemede daireler yeniden okunur.
  final RefreshStatus? refresh;

  /// Verilirse (yönetici kitlesi) şerit site seçicidir; seçim (null = tüm siteler) buraya iletilir.
  final ValueChanged<int?>? onPickSite;

  /// Verilirse (sakin kitlesi) şerit "Dairem"e götürür.
  final VoidCallback? onOpenApartments;

  @override
  State<ContextStripHost> createState() => _ContextStripHostState();
}

class _ContextStripHostState extends State<ContextStripHost> {
  List<ContextApartment> _apartments = const <ContextApartment>[];
  int _token = 0;
  int _seenRevision = 0;

  @override
  void initState() {
    super.initState();
    _seenRevision = widget.refresh?.revision ?? 0;
    widget.refresh?.addListener(_onRefresh);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ContextStripHost old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh) {
      old.refresh?.removeListener(_onRefresh);
      _seenRevision = widget.refresh?.revision ?? 0;
      widget.refresh?.addListener(_onRefresh);
    }
    final needsApartments = widget.audience != ShowcaseAudience.admin;
    final neededBefore = old.audience != ShowcaseAudience.admin;
    if (old.userId != widget.userId) {
      // Başka kullanıcı: eskisinin daireleri bir kare bile gösterilmez.
      _apartments = const <ContextApartment>[];
      unawaited(_load());
    } else if ((needsApartments && !neededBefore) || (old.loadApartments == null && widget.loadApartments != null)) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_onRefresh);
    ++_token;
    super.dispose();
  }

  void _onRefresh() {
    final status = widget.refresh;
    if (status == null || status.refreshing || status.revision == _seenRevision) return;
    _seenRevision = status.revision;
    unawaited(_load());
  }

  Future<void> _load() async {
    final loader = widget.loadApartments;
    if (loader == null || widget.audience == ShowcaseAudience.admin) return;
    final token = ++_token;
    try {
      final list = await loader();
      if (!mounted || token != _token) return;
      setState(() => _apartments = List<ContextApartment>.unmodifiable(list));
    } catch (_) {
      // Şerit bilgi amaçlıdır: daireler okunamazsa dairesiz çizilir, ekran bozulmaz.
    }
  }

  Future<void> _pickSite() async {
    final pick = widget.onPickSite;
    if (pick == null) return;
    final selected = widget.scopeSiteCode;
    final choice = await showModalBottomSheet<_SiteChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ContextSitePickerSheet(sites: widget.sites, selectedCode: selected),
    );
    if (choice == null || choice.code == selected) return;
    pick(choice.code);
  }

  @override
  Widget build(BuildContext context) {
    // Kısa pencerede (yatay telefon) sabit AppBar + şerit içeriğe yer bırakmaz: şerit çizilmez.
    if (MediaQuery.sizeOf(context).height < 480) return const SizedBox.shrink();
    final data = composeContextStrip(
      audience: widget.audience,
      sites: widget.sites,
      scopeSiteCode: widget.scopeSiteCode,
      apartments: _apartments,
      siteSelectable: widget.onPickSite != null,
      canOpenApartments: widget.onOpenApartments != null,
    );
    if (data == null) return const SizedBox.shrink();
    final VoidCallback? onTap = switch (data.action) {
      ContextStripAction.pickSite => () => unawaited(_pickSite()),
      ContextStripAction.openApartments => widget.onOpenApartments,
      ContextStripAction.none => null,
    };
    final horizontal = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 20.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, AppSpace.sm, horizontal, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ContextStrip(data: data, onTap: onTap),
        ),
      ),
    );
  }
}
