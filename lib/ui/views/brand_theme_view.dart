import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/brand/brand_theme.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/brand_theme_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

// Beyaz etiket tema düzenleyicisi (G9, docs/PLATFORM_BEYAZ_ETIKET.md): 5 renk + logo + uygulamada görünen ad. Yalnız süper kullanıcı
// ve firma sahibi açar (sunucu da denetler). Kaydedilen tema ilgili kullanıcılarda bir sonraki girişte (ya da uygulama açılışında) görünür.

/// Yönetim firması sayfasına gömülen bölüm: firmanın kendi teması + bağlı her site için ayrı tema.
class BrandThemeSection extends StatelessWidget {
  const BrandThemeSection({super.key, required this.authService, required this.companyId, required this.sites});

  final AuthService authService;
  final int companyId;

  /// Bağlı siteler: { 'site_code': int, 'name': String }.
  final List<Map<String, dynamic>> sites;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppCard(
      key: const ValueKey<String>('brand_section'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('Marka teması', style: th.titleLarge),
        const SizedBox(height: AppSpace.xs),
        Text('Uygulamanın renkleri, logosu ve adı. Site teması varsa o, yoksa firma teması kullanılır; ikisi de yoksa Güde teması.', style: th.bodySmall),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton(
          key: const ValueKey<String>('brand_company_edit'),
          onPressed: () => BrandThemeScreen.open(context, authService: authService, scopeType: 'company', scopeId: companyId, title: 'Firma teması'),
          child: const Text('Firma temasını düzenle'),
        ),
        for (final s in sites)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: OutlinedButton(
              key: ValueKey<String>('brand_site_${s['site_code']}'),
              onPressed: () => BrandThemeScreen.open(
                context,
                authService: authService,
                scopeType: 'site',
                scopeId: s['site_code'] as int,
                title: '${s['name']} teması',
              ),
              child: Text('${s['name']} temasını düzenle'),
            ),
          ),
      ]),
    );
  }
}

class BrandThemeScreen extends StatefulWidget {
  const BrandThemeScreen({
    super.key,
    required this.authService,
    required this.scopeType,
    required this.scopeId,
    required this.title,
    this.service,
  });

  final AuthService authService;
  final String scopeType;
  final int scopeId;
  final String title;
  final BrandThemeService? service;

  static Future<void> open(
    BuildContext context, {
    required AuthService authService,
    required String scopeType,
    required int scopeId,
    required String title,
  }) =>
      Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => BrandThemeScreen(authService: authService, scopeType: scopeType, scopeId: scopeId, title: title),
      ));

  @override
  State<BrandThemeScreen> createState() => _BrandThemeScreenState();
}

class _BrandThemeScreenState extends State<BrandThemeScreen> {
  static const int _maxLogoBytes = 150 * 1024;
  static const _labels = <String, String>{
    'primary': 'Ana renk (düğmeler)',
    'accent': 'Vurgu rengi (bağlantılar)',
    'background': 'Sayfa zemini',
    'surface': 'Kart rengi',
    'text': 'Yazı rengi',
  };
  static const _defaults = <String, String>{
    'primary': '#0F172A',
    'accent': '#1D4ED8',
    'background': '#F8FAFC',
    'surface': '#FFFFFF',
    'text': '#334155',
  };

  late final BrandThemeService _service = widget.service ?? BrandThemeService(authService: widget.authService);
  final Map<String, TextEditingController> _hex = <String, TextEditingController>{
    for (final k in _labels.keys) k: TextEditingController(text: _defaults[k]),
  };
  final TextEditingController _name = TextEditingController();
  String? _logoData;
  bool _logoChanged = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in _hex.values) {
      c.addListener(_refresh);
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in _hex.values) {
      c.dispose();
    }
    _name.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final t = await _service.forScope(widget.scopeType, widget.scopeId);
      if (!mounted) return;
      setState(() {
        if (t != null) _apply(t);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  void _apply(BrandTheme t) {
    _hex['primary']!.text = hexOf(t.primary);
    _hex['accent']!.text = hexOf(t.accent);
    _hex['background']!.text = hexOf(t.background);
    _hex['surface']!.text = hexOf(t.surface);
    _hex['text']!.text = hexOf(t.text);
    _name.text = t.displayName ?? '';
    _logoData = t.logoData;
    _logoChanged = false;
  }

  /// Alanlardan tema; herhangi bir renk geçersizse null.
  BrandTheme? _current() {
    final c = <String, Color?>{for (final e in _hex.entries) e.key: parseHexColor(e.value.text)};
    if (c.values.any((v) => v == null)) return null;
    final name = _name.text.trim();
    return BrandTheme(
      primary: c['primary']!,
      accent: c['accent']!,
      background: c['background']!,
      surface: c['surface']!,
      text: c['text']!,
      displayName: name.isEmpty ? null : name,
      logoData: _logoData,
    );
  }

  Future<void> _pickLogo() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Logo seçin (png, jpeg ya da webp; en çok 150 KB)',
        type: FileType.custom,
        allowedExtensions: const <String>['png', 'jpg', 'jpeg', 'webp'],
      );
      if (file == null) return;
      final bytes = <int>[];
      await for (final chunk in file.readAsByteStream()) {
        bytes.addAll(chunk);
        if (bytes.length > _maxLogoBytes) {
          if (mounted) AppSnack.show(context, 'Logo en çok 150 KB olabilir.', kind: AppSnackKind.error);
          return;
        }
      }
      final ext = file.name.toLowerCase().split('.').last;
      final mime = ext == 'png' ? 'png' : (ext == 'webp' ? 'webp' : 'jpeg');
      setState(() {
        _logoData = 'data:image/$mime;base64,${base64Encode(bytes)}';
        _logoChanged = true;
      });
    } on Exception {
      if (mounted) AppSnack.show(context, 'Dosya okunamadı.', kind: AppSnackKind.error);
    }
  }

  Future<void> _save() async {
    final theme = _current();
    if (theme == null) {
      AppSnack.show(context, 'Renkler #RRGGBB biçiminde olmalı (örn. #1D4ED8).', kind: AppSnackKind.error);
      return;
    }
    if (!theme.isReadable) {
      AppSnack.show(context, 'Renkler okunaklı değil: yazı ve vurgu rengi kart/zemin üzerinde yeterince karşıt olmalı.', kind: AppSnackKind.error);
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.save(
        widget.scopeType,
        widget.scopeId,
        theme,
        logoData: _logoChanged ? _logoData : null,
        removeLogo: _logoChanged && _logoData == null,
      );
      if (!mounted) return;
      AppSnack.show(context, 'Tema kaydedildi. Kullanıcılar yeniden giriş yaptığında görür.');
      setState(() => _logoChanged = false);
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    try {
      await _service.reset(widget.scopeType, widget.scopeId);
      if (!mounted) return;
      setState(() {
        for (final e in _hex.entries) {
          e.value.text = _defaults[e.key]!;
        }
        _name.clear();
        _logoData = null;
        _logoChanged = false;
      });
      AppSnack.show(context, 'Varsayılan Güde temasına dönüldü.');
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _colorField(String key) {
    final color = parseHexColor(_hex[key]!.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: TextField(
        key: ValueKey<String>('brand_color_$key'),
        controller: _hex[key],
        maxLength: 7,
        autocorrect: false,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: _labels[key],
          counterText: '',
          errorText: color == null ? '#RRGGBB biçiminde yazın' : null,
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color ?? Colors.transparent, shape: BoxShape.circle, border: Border.all(color: Colors.black26)),
              child: const SizedBox(width: 20, height: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _preview(BrandTheme theme, TextTheme th) {
    final p = theme.lightPalette();
    final bytes = theme.logoBytes;
    return Container(
      key: const ValueKey<String>('brand_preview'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: p.background, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          if (bytes != null) ...<Widget>[Image.memory(bytes, width: 32, height: 32, errorBuilder: (_, _, _) => const SizedBox(width: 32, height: 32)), const SizedBox(width: 8)],
          Expanded(child: Text(theme.displayName ?? 'Uygulama adı', style: th.titleMedium?.copyWith(color: p.text), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: AppSpace.sm),
        DecoratedBox(
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: p.border)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('Örnek kart', style: th.titleSmall?.copyWith(color: p.text)),
              Text('Gövde metni bu renkte görünür.', style: th.bodyMedium?.copyWith(color: p.textSecondary)),
              const SizedBox(height: 6),
              Text('Bir bağlantı', style: th.bodyMedium?.copyWith(color: p.link, decoration: TextDecoration.underline)),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(color: p.action, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Text('Ana düğme', style: TextStyle(color: p.onAction, fontWeight: FontWeight.w600))),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final theme = _current();
    final Widget body;
    if (_loading) {
      body = const Center(child: Padding(padding: EdgeInsets.all(AppSpace.xl), child: CircularProgressIndicator()));
    } else if (_error != null) {
      body = InlineNotice(message: _error!, onRetry: () {
        setState(() {
          _error = null;
          _loading = true;
        });
        unawaited(_load());
      });
    } else {
      final unreadable = theme != null && !theme.isReadable;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        TextField(
          key: const ValueKey<String>('brand_name'),
          controller: _name,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Uygulamada görünen ad (boşsa Güde)'),
        ),
        for (final k in _labels.keys) _colorField(k),
        if (unreadable)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text('Bu renklerle yazılar okunaklı olmaz: yazı ve vurgu rengi kart ve zemin üzerinde daha koyu/açık olmalı.', key: const ValueKey<String>('brand_low_contrast'), style: th.bodyMedium?.copyWith(color: context.palette.statusCrit)),
          ),
        Row(children: <Widget>[
          OutlinedButton(key: const ValueKey<String>('brand_logo_pick'), onPressed: _pickLogo, child: Text(_logoData == null ? 'Logo seç' : 'Logoyu değiştir')),
          if (_logoData != null) ...<Widget>[
            const SizedBox(width: AppSpace.sm),
            TextButton(key: const ValueKey<String>('brand_logo_remove'), onPressed: () => setState(() {
                  _logoData = null;
                  _logoChanged = true;
                }), child: const Text('Logoyu kaldır')),
          ],
        ]),
        const SizedBox(height: AppSpace.md),
        if (theme != null) _preview(theme, th),
        const SizedBox(height: AppSpace.md),
        FilledButton(key: const ValueKey<String>('brand_save'), onPressed: _saving || theme == null || unreadable ? null : _save, child: const Text('Kaydet')),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton(key: const ValueKey<String>('brand_reset'), onPressed: _saving ? null : _reset, child: const Text('Varsayılana dön')),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpace.lg), children: <Widget>[body])),
    );
  }
}
