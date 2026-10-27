import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/account_platform_config.dart';
import 'package:site_kapi_kontrol/services/account_api.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/app_config_service.dart';
import 'package:site_kapi_kontrol/services/app_version.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/platform_rules_entry_card.dart';

/// "Platform Ayarları" ekranı (yalnız süper kullanıcı): `GET/PUT /admin/platform-config`.
///
/// Üç bölüm: uygulama sürümü ve bakım modu, destek iletişim bilgileri, şirket / yasal bilgiler ("onayları
/// zorunlu kıl" anahtarı dahil). Boş alan = ayarsız.
///
/// Kurallar:
/// - İlk yükleme başarısızsa FORM ÇİZİLMEZ (boş alanlar "ayarlar boş" gibi görünmesin): hata + "Tekrar Dene".
/// - Kaydetme KISMİ güncellemedir: yalnız değişen alanlar gönderilir. Kaydet, değişiklik yoksa pasiftir.
/// - Alanlar kaydetmeden önce doğrulanır (sürüm `1.2.3`, URL `https://`, e-posta, telefon, MERSİS, uzunluk);
///   ilk geçersiz alan görünür kılınıp odaklanır.
/// - Riskli değişiklikler (bakım modunu açmak, en düşük sürümü yükseltmek, onayları zorunlu kılmak) kaydetmeden
///   önce açıkça onaylatılır.
/// - Kaydedilmemiş değişiklik varken başka ekrana geçmek / yenilemek uyarı ister ([confirmDiscard]).
/// - Kayıt (ve yenileme) sürerken alanlar ve düğmeler kilitlidir (çift gönderim yok; bayat GET kaydedileni
///   ezemez); 429'da düğme süre dolana dek kilitlenir.
/// - En düşük desteklenen sürüm KURULU uygulama sürümünden yüksek olamaz: aksi hâlde yönetici kendi uygulamasını
///   da "güncelleme gerekli" ekranına düşürürdü. Son sürüm boş olsa da denetlenir.
class PlatformSettingsView extends StatefulWidget {
  const PlatformSettingsView({
    super.key,
    required this.authService,
    this.service,
    this.onSaved = refreshAppConfig,
    this.installedVersion = loadInstalledVersion,
  });

  final AuthService authService;

  /// Testler için; verilmezse [authService] üzerinden kurulur.
  final AccountService? service;

  /// Başarılı kayıttan sonra çağrılır (varsayılan: uygulama yapılandırmasını tazeler). Hataları yutulur.
  final Future<void> Function() onSaved;

  /// Kurulu uygulama sürümü (`major.minor.patch`); okunamazsa null (kurulu sürüm denetimi atlanır). Testler verir.
  final Future<String?> Function() installedVersion;

  /// Varsayılan [onSaved]: bellekteki uygulama yapılandırmasını zorla tazeler.
  static Future<void> refreshAppConfig() async {
    await AppConfigService.instance.load(force: true);
  }

  /// Varsayılan [installedVersion]: `package_info_plus` (okunamazsa derleme sabiti).
  static Future<String?> loadInstalledVersion() async => (await loadInstalledAppInfo()).version;

  @override
  State<PlatformSettingsView> createState() => PlatformSettingsViewState();
}

class PlatformSettingsViewState extends State<PlatformSettingsView> {
  static const List<String> _textKeys = <String>[
    'min_supported_version',
    'latest_version',
    'update_url_android',
    'update_url_ios',
    'maintenance_message',
    'email',
    'phone',
    'hours',
    'web_url',
    'company_name',
    'company_address',
    'mersis_no',
    'kep_address',
    'contact_email',
    'contact_phone',
  ];

  // Her taze ayar uygulamasında YENİLENİR: eski doğrulama hataları form durumuyla birlikte atılır
  // (FormState.reset() denetleyici metnini boşaltacağından kullanılmaz).
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _c = <String, TextEditingController>{
    for (final key in _textKeys) key: TextEditingController(),
  };
  final RetryLock _retry = RetryLock();
  AccountService? _ownService;

  /// Genel (alan dışı) kayıt hatasının odak düğümü: hata sonrası odak hata kutusuna gelir.
  final FocusNode _errorFocus = FocusNode(debugLabel: 'platform_save_error');

  /// Kurulu uygulama sürümü (yüklenene dek null: denetim atlanır). Form ağ yanıtından sonra çizildiğinden okuma
  /// kullanıcı düzenlemeye başlamadan çok önce biter; kayıt bunu BEKLEMEZ (platform kanalı yanıt vermezse takılmasın).
  String? _installed;

  PlatformConfig? _baseline;
  bool _maintenanceActive = false;
  bool _enforceConsents = false;
  bool _loading = true;
  bool _saving = false;
  bool _confirming = false;
  bool _dirty = false;
  String? _loadError;
  String? _formError;
  String? _saveError;
  String? _savedNotice;
  int _token = 0;

  /// Sunucunun alan bazlı itirazları (`grup.alan` -> metin); alan düzenlenince silinir.
  final Map<String, String> _serverErrors = <String, String>{};

  AccountService get _service =>
      widget.service ?? (_ownService ??= AccountService(authService: widget.authService));

  /// Kaydedilmemiş değişiklik var mı (ana sayfa başka menüye geçmeden önce sorar).
  bool get hasUnsavedChanges => _dirty;

  /// Alanlar ve eylemler kilitli mi: kayıt VEYA yenileme sürüyor. Yenileme sürerken düzenlemek / kaydetmek,
  /// gelen sunucu yanıtının yazılanları (ya da yeni kaydedileni) ezmesine yol açardı.
  bool get _busy => _saving || _loading;

  static const String noChangesText = 'Kaydedilecek değişiklik yok.';

  @override
  void initState() {
    super.initState();
    for (final controller in _c.values) {
      controller.addListener(_recomputeDirty);
    }
    unawaited(_loadInstalled());
    unawaited(_load());
  }

  Future<void> _loadInstalled() async {
    try {
      final raw = await widget.installedVersion();
      final parsed = AppVersion.tryParse(raw);
      if (parsed != null) _installed = parsed.toString();
    } catch (_) {
      // Okunamadı: kurulu sürüm denetimi atlanır (sunucu aralık denetimi yine çalışır).
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ++_token;
    _errorFocus.dispose();
    _retry.dispose();
    for (final controller in _c.values) {
      controller
        ..removeListener(_recomputeDirty)
        ..dispose();
    }
    super.dispose();
  }

  PlatformConfig _draft() => PlatformConfig(
    app: PlatformAppConfig(
      minSupportedVersion: _c['min_supported_version']!.text,
      latestVersion: _c['latest_version']!.text,
      updateUrlAndroid: _c['update_url_android']!.text,
      updateUrlIos: _c['update_url_ios']!.text,
      maintenanceActive: _maintenanceActive,
      maintenanceMessage: _c['maintenance_message']!.text,
    ),
    support: PlatformSupportConfig(
      email: _c['email']!.text,
      phone: phoneGroupedForSave(_c['phone']!.text, stored: _baseline?.support.phone),
      hours: _c['hours']!.text,
      webUrl: _c['web_url']!.text,
    ),
    legal: PlatformLegalConfig(
      companyName: _c['company_name']!.text,
      companyAddress: _c['company_address']!.text,
      mersisNo: _c['mersis_no']!.text,
      kepAddress: _c['kep_address']!.text,
      contactEmail: _c['contact_email']!.text,
      contactPhone: phoneGroupedForSave(_c['contact_phone']!.text, stored: _baseline?.legal.contactPhone),
      enforceConsents: _enforceConsents,
    ),
  );

  void _recomputeDirty() {
    final base = _baseline;
    final dirty = base != null && !_draft().sameAs(base);
    if (dirty != _dirty && mounted) {
      setState(() {
        _dirty = dirty;
        if (!dirty) _formError = null;
      });
    }
  }

  void _applyConfig(PlatformConfig config) {
    // Denetleyici dinleyicileri doldururken tek tek tetiklenmesin.
    for (final controller in _c.values) {
      controller.removeListener(_recomputeDirty);
    }
    _c['min_supported_version']!.text = config.app.minSupportedVersion;
    _c['latest_version']!.text = config.app.latestVersion;
    _c['update_url_android']!.text = config.app.updateUrlAndroid;
    _c['update_url_ios']!.text = config.app.updateUrlIos;
    _c['maintenance_message']!.text = config.app.maintenanceMessage;
    _c['email']!.text = config.support.email;
    // Telefonlar "+90 XXX XXX XX XX" biçiminde gösterilir (boşsa "+90 " hazır; eski serbest kayıt olduğu gibi).
    _c['phone']!.text = phoneFieldInitial(config.support.phone);
    _c['hours']!.text = config.support.hours;
    _c['web_url']!.text = config.support.webUrl;
    _c['company_name']!.text = config.legal.companyName;
    _c['company_address']!.text = config.legal.companyAddress;
    _c['mersis_no']!.text = config.legal.mersisNo;
    _c['kep_address']!.text = config.legal.kepAddress;
    _c['contact_email']!.text = config.legal.contactEmail;
    _c['contact_phone']!.text = phoneFieldInitial(config.legal.contactPhone);
    for (final controller in _c.values) {
      controller.addListener(_recomputeDirty);
    }
    _maintenanceActive = config.app.maintenanceActive;
    _enforceConsents = config.legal.enforceConsents;
    _baseline = config;
    _dirty = false;
    _serverErrors.clear();
    _formKey = GlobalKey<FormState>();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final config = await _service.getPlatformConfig();
      if (!mounted || token != _token) return;
      setState(() {
        _applyConfig(config);
        _loading = false;
        _formError = null;
        _saveError = null;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _loadError = e is ApiException && e.message.trim().isNotEmpty
            ? e.message
            : 'Platform ayarları yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      });
    }
  }

  /// Ayarları sunucudan yeniden okur. Kaydedilmemiş değişiklik varsa önce onay ister (aşağı çekip yenileme
  /// ve yenile düğmesi yazdıklarını sessizce ezmesin).
  Future<void> reload() async {
    if (!mounted || _saving || _confirming || _loading) return;
    if (!await confirmDiscard()) return;
    await _load();
  }

  /// Kaydedilmemiş değişiklik yoksa true; varsa "değişiklikleri sil" onayı ister (true = silinebilir). Onay açıkken
  /// gelen ikinci çağrı (aynı karede iki dokunuş, yenileme + menü) AYNI pencereyi ve sonucunu paylaşır; ikinci
  /// pencere açılmaz.
  Future<bool> confirmDiscard() => _discardPending ??= _askDiscard().whenComplete(() => _discardPending = null);

  Future<bool>? _discardPending;

  Future<bool> _askDiscard() async {
    if (!_dirty || !mounted) return true;
    return confirmCrmAction(
      context,
      title: 'Kaydedilmemiş değişiklikler',
      message:
          'Platform ayarlarında kaydedilmemiş değişiklikleriniz var. Devam ederseniz bu değişiklikler kaybolur.',
      confirmLabel: 'Değişiklikleri Sil',
      cancelLabel: 'Düzenlemeye Dön',
      icon: Icons.edit_off_rounded,
      tone: AppTone.warning,
    );
  }

  void _revert() {
    final base = _baseline;
    if (base == null || _busy) return;
    setState(() {
      _applyConfig(base);
      _formError = null;
      _saveError = null;
    });
  }

  /// Kaydetmeden önce kullanıcıya açıkça söylenmesi gereken riskli değişiklikler.
  List<String> _riskNotes(PlatformConfig base, PlatformConfig next) {
    final notes = <String>[];
    if (next.app.maintenanceActive && !base.app.maintenanceActive) {
      notes.add(
        'Bakım modu AÇILACAK: kullanıcılar bakım iletisini görür ve uygulamayı kullanamayabilir.',
      );
    }
    final newMin = next.app.minSupportedVersion.trim();
    final oldMin = base.app.minSupportedVersion.trim();
    if (newMin.isNotEmpty && newMin != oldMin) {
      final compared = oldMin.isEmpty ? 1 : comparePlatformVersions(newMin, oldMin);
      if (compared != null && compared > 0) {
        notes.add(
          'En düşük desteklenen sürüm $newMin olacak: bu sürümün altındaki uygulamalar güncellenmeden '
          'kullanılamaz${_installed == null ? '' : ' (şu an kullandığınız sürüm: $_installed, etkilenmez)'}.',
        );
      }
    }
    if (next.legal.enforceConsents && !base.legal.enforceConsents) {
      notes.add(
        'Onaylar ZORUNLU kılınacak: tamamlanmış yasal belgeleri onaylamayan kullanıcılar kayıt olamaz ve '
        'site başvurusu yapamaz.',
      );
    }
    return notes;
  }

  Future<void> _save() async {
    if (_busy || _confirming || _retry.locked) return;
    final base = _baseline;
    if (base == null) return;
    if (!_dirty) {
      // Değişiklik yok: sessizce dönmek yerine nedeni söyler (Enter / ekran okuyucu).
      announcePolite(context, noChangesText);
      return;
    }
    if (!validateForm(_formKey)) {
      setState(() {
        _formError = kFixFieldsMessage;
        _saveError = null;
        _savedNotice = null;
      });
      return;
    }
    final next = _draft();
    final patch = next.patchAgainst(base);
    if (patch.isEmpty) {
      setState(() => _formError = null);
      return;
    }
    final notes = _riskNotes(base, next);
    if (notes.isNotEmpty) {
      setState(() => _confirming = true);
      final bool ok;
      try {
        ok = await confirmCrmAction(
          context,
          title: 'Bu değişiklikleri kaydet?',
          message: notes.map((note) => '• $note').join('\n\n'),
          confirmLabel: 'Kaydet',
          cancelLabel: 'Vazgeç',
          icon: Icons.warning_amber_rounded,
          tone: AppTone.warning,
        );
      } finally {
        if (mounted) setState(() => _confirming = false);
      }
      if (!ok || !mounted) return;
    }
    FocusScope.of(context).unfocus();
    // Süren bir GET (varsa) yanıtı sayılmaz: kaydedilen değeri eski sunucu durumuyla ezmesin.
    ++_token;
    setState(() {
      _saving = true;
      _loading = false;
      _formError = null;
      _saveError = null;
      _savedNotice = null;
    });
    try {
      final updated = await _service.updatePlatformConfig(patch);
      if (!mounted) return;
      setState(() {
        _applyConfig(updated);
        _saving = false;
        _savedNotice = 'Ayarlar kaydedildi.';
      });
      announcePolite(context, 'Platform ayarları kaydedildi.');
      unawaited(_notifySaved());
    } catch (e) {
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      final mapped = !limited && _applyServerFieldErrors(e);
      setState(() {
        _saving = false;
        if (mapped) {
          // Sunucu alanlara itiraz etti: her alanın altında gösterilir, ilk hatalı alan odaklanır.
          _saveError = null;
          _formError = kFixFieldsMessage;
        } else {
          _saveError = limited
              ? (e is ApiException ? e.message : RetryLock.messageFor(e))
              : (e is ApiException && e.message.trim().isNotEmpty
                    ? e.message
                    : 'Ayarlar kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (mapped) {
          validateForm(_formKey);
        } else {
          // Genel (alan dışı) hata: odak hata kutusuna gelir (kayıt sırasında alan odağı bırakılmıştı).
          _errorFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _notifySaved() async {
    try {
      await widget.onSaved();
    } catch (_) {
      // Yapılandırma tazelenemedi: kayıt başarılıdır, sonraki açılışta okunur.
    }
  }

  // --- Alan üreticileri ------------------------------------------------------------------------

  Widget _field(
    String key,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    int maxLines = 1,
    int minLines = 1,
    IconData? icon,
    bool last = false,
    String? helper,
    String? hint,
  }) {
    final multiline = maxLines > 1;
    final serverKey = _serverKey(key);
    return TextFormField(
      key: ValueKey<String>('platform_$key'),
      controller: _c[key],
      enabled: !_busy,
      keyboardType: keyboardType ?? TextInputType.text,
      // Sunucu satır sonlarını boşluğa çevirir: çok satırlı alanlarda Enter "sonraki alan"a geçer.
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
      minLines: multiline ? minLines : 1,
      maxLines: maxLines,
      inputFormatters: <TextInputFormatter>[
        if (multiline) FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
        ...?formatters,
      ],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onFieldSubmitted: last ? (_) => _save() : null,
      // Düzenleme sunucunun bu alana ait itirazını eskitir.
      onChanged: (_) {
        if (_serverErrors.remove(serverKey) != null) setState(() {});
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        prefixIcon: icon == null ? null : Icon(icon),
        alignLabelWithHint: multiline,
      ),
      validator: (value) => validator?.call(value) ?? _serverErrors[serverKey],
    );
  }

  /// Alan adı -> sunucu grubu (sunucu hataları `grup.alan` anahtarıyla gelir).
  static const Map<String, String> _groupOf = <String, String>{
    'min_supported_version': 'app',
    'latest_version': 'app',
    'update_url_android': 'app',
    'update_url_ios': 'app',
    'maintenance_message': 'app',
    'email': 'support',
    'phone': 'support',
    'hours': 'support',
    'web_url': 'support',
    'company_name': 'legal',
    'company_address': 'legal',
    'mersis_no': 'legal',
    'kep_address': 'legal',
    'contact_email': 'legal',
    'contact_phone': 'legal',
  };

  static String _serverKey(String key) => '${_groupOf[key]}.$key';

  /// Sunucu `400 VALIDATION_FAILED` / `INVALID_VERSION_RANGE` gövdesindeki `fields` haritasını alan hatalarına
  /// çevirir ("en fazla 500 karakter olabilir." -> "En fazla 500 karakter olabilir."). Haritada bu ekranda
  /// karşılığı olmayan anahtar varsa false döner (çağıran genel hata gösterir).
  bool _applyServerFieldErrors(Object error) {
    if (error is! ApiException) return false;
    final fields = error.payload?['fields'];
    if (fields is! Map || fields.isEmpty) return false;
    final known = <String, String>{};
    for (final entry in fields.entries) {
      final key = entry.key.toString();
      final text = entry.value is String ? (entry.value as String).trim() : '';
      final bare = _groupOf.entries.any((g) => '${g.value}.${g.key}' == key);
      if (!bare || text.isEmpty) return false;
      known[key] = _capitalize(text);
    }
    _serverErrors
      ..clear()
      ..addAll(known);
    return true;
  }

  static String _capitalize(String text) {
    if (text.isEmpty) return text;
    final first = text.substring(0, 1);
    final upper = first == 'i' ? 'İ' : first.toUpperCase();
    return '$upper${text.substring(1)}';
  }

  String? _minVersionValidator(String? value) {
    final basic = validatePlatformVersion(value, 'En düşük desteklenen sürüm');
    if (basic != null) return basic;
    final latest = _c['latest_version']!.text.trim();
    final min = (value ?? '').trim();
    if (min.isNotEmpty && latest.isNotEmpty) {
      final compared = comparePlatformVersions(min, latest);
      if (compared != null && compared > 0) {
        return 'En düşük desteklenen sürüm, son sürümden büyük olamaz.';
      }
    }
    // Son sürüm boş olsa da: yeni değer KURULU uygulamadan yüksekse kayıt reddedilir (kendi uygulamanız da
    // "güncelleme gerekli" ekranına düşerdi). Değişmemiş eski değer başka alanların kaydını engellemesin.
    final installed = _installed;
    final base = _baseline?.app.minSupportedVersion.trim() ?? '';
    if (min.isNotEmpty && min != base && installed != null && isVersionOlder(installed, min)) {
      return 'En düşük desteklenen sürüm ($min), bu uygulamanın sürümünden ($installed) yüksek olamaz: '
          'kaydederseniz kendi uygulamanız da güncelleme ekranına düşer.';
    }
    return null;
  }

  static final List<TextInputFormatter> _versionFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final Widget content;
    if (_baseline == null) {
      content = _loading
          ? const ListSkeleton(rows: 4)
          : InlineNotice(
              message: _loadError ?? 'Platform ayarları yüklenemedi.',
              onRetry: _load,
            );
    } else {
      content = _form(context, th);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Platform Ayarları', icon: Icons.tune_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Uygulama sürümü, bakım modu, destek iletişimi ve şirket / yasal bilgiler. Boş bıraktığınız alan '
          '"ayarsız" sayılır.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        // Kurallar tablosu (G11; docs/PLATFORM_KURALLAR.md): platform geneli değerler ayrı sayfada değiştirilir (bu formun kaydından bağımsız).
        PlatformRulesEntryCard(authService: widget.authService, canEdit: true),
        const SizedBox(height: AppSpace.lg),
        content,
      ],
    );
  }

  /// Sabit yuva: [show] false iken boş kutu; içerik değişse de yuvanın listedeki sırası ve öğe sayısı DEĞİŞMEZ.
  Widget _slot(bool show, Widget Function() build) => show ? build() : const SizedBox.shrink();

  Widget _form(BuildContext context, TextTheme th) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // SABİT YUVALAR: koşullu öğeler listeden eklenip çıkarılmaz, aynı sıradaki yuvanın içeriği değişir. Aksi
          // hâlde üstten ekleme + alttan çıkarma birleşince Flutter alan kartlarını baştan kurar ve ilk tuş
          // vuruşunda odak / klavye kaybolurdu.
          _slot(
            _loadError != null,
            () => Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              // Yenileme başarısız: eldeki ayarlar korunur, hata görünür kalır.
              child: InlineNotice(message: _loadError!, onRetry: _loading ? null : reload),
            ),
          ),
          _slot(
            _dirty,
            () => const Padding(
              padding: EdgeInsets.only(bottom: AppSpace.md),
              child: InlineNotice(
                key: ValueKey<String>('platform_dirty_notice'),
                tone: AppTone.warning,
                message: 'Kaydedilmemiş değişiklikleriniz var.',
              ),
            ),
          ),
          AppCard(
            key: const ValueKey<String>('platform_section_app'),
            padding: listCardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Uygulama Sürümü ve Bakım', icon: Icons.system_update_rounded),
                const SizedBox(height: AppSpace.md),
                _field(
                  'min_supported_version',
                  'En düşük desteklenen sürüm',
                  icon: Icons.verified_rounded,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  formatters: _versionFormatters,
                  helper: 'Örn. 1.0.0. Bunun altındaki uygulamalar güncelleme ister.',
                  validator: _minVersionValidator,
                ),
                const SizedBox(height: AppSpace.md),
                _field(
                  'latest_version',
                  'Son sürüm',
                  icon: Icons.new_releases_outlined,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  formatters: _versionFormatters,
                  helper: 'Örn. 1.2.0',
                  validator: (v) => validatePlatformVersion(v, 'Son sürüm'),
                ),
                const SizedBox(height: AppSpace.md),
                _field(
                  'update_url_android',
                  'Android güncelleme bağlantısı',
                  icon: Icons.android_rounded,
                  keyboardType: TextInputType.url,
                  helper: 'https:// ile başlamalı.',
                  validator: (v) => validatePlatformUrl(v, 'Android güncelleme bağlantısı'),
                ),
                const SizedBox(height: AppSpace.md),
                _field(
                  'update_url_ios',
                  'iOS güncelleme bağlantısı',
                  icon: Icons.phone_iphone_rounded,
                  keyboardType: TextInputType.url,
                  helper: 'https:// ile başlamalı.',
                  validator: (v) => validatePlatformUrl(v, 'iOS güncelleme bağlantısı'),
                ),
                const SizedBox(height: AppSpace.sm),
                SwitchListTile(
                  key: const ValueKey<String>('platform_maintenance_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bakım modu'),
                  subtitle: const Text(
                    'Açıkken kullanıcılar aşağıdaki iletiyi görür ve uygulamayı kullanamayabilir.',
                  ),
                  value: _maintenanceActive,
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() => _maintenanceActive = value);
                          _recomputeDirty();
                        },
                ),
                _field(
                  'maintenance_message',
                  'Bakım iletisi',
                  icon: Icons.build_circle_outlined,
                  minLines: 2,
                  maxLines: 5,
                  validator: (v) => validatePlatformText(v, PlatformFieldLimits.message, 'Bakım iletisi'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          AppCard(
            key: const ValueKey<String>('platform_section_support'),
            padding: listCardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Destek İletişim', icon: Icons.support_agent_rounded),
                const SizedBox(height: AppSpace.md),
                _field(
                  'email',
                  'Destek e-postası',
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => validatePlatformEmail(v, 'Destek e-postası'),
                ),
                const SizedBox(height: AppSpace.md),
                _field(
                  'phone',
                  'Destek telefonu',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  formatters: const [PhoneInputFormatter(mobileOnly: false)],
                  hint: phoneFieldHintAny,
                  validator: (v) => validatePhoneInput(v, stored: _baseline?.support.phone, mobileOnly: false),
                ),
                const SizedBox(height: AppSpace.md),
                _field(
                  'hours',
                  'Çalışma saatleri',
                  icon: Icons.schedule_rounded,
                  helper: 'Örn. Hafta içi 09:00 - 18:00',
                  validator: (v) => validatePlatformText(v, PlatformFieldLimits.hours, 'Çalışma saatleri'),
                ),
                const SizedBox(height: AppSpace.md),
                _field(
                  'web_url',
                  'Destek web adresi',
                  icon: Icons.public_rounded,
                  keyboardType: TextInputType.url,
                  helper: 'https:// ile başlamalı.',
                  validator: (v) => validatePlatformUrl(v, 'Destek web adresi'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          AppCard(
            key: const ValueKey<String>('platform_section_legal'),
            padding: listCardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Şirket ve Yasal Bilgiler', icon: Icons.gavel_rounded),
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Gizlilik politikası ve sözleşme metinlerindeki şirket bilgilerini doldurur. MERSİS numarası ve KEP '
                  'adresi isteğe bağlıdır: boşken yasal metinlerde hiç yazılmaz. Diğer alanlardan boş kalan belgede [……] '
                  'olarak görünür ve belge "tamamlanmamış" sayılır.',
                  style: th.bodySmall,
                ),
                const SizedBox(height: AppSpace.md),
                _field(
                  'company_name',
                  'Şirket unvanı',
                  icon: Icons.business_rounded,
                  validator: (v) =>
                      validatePlatformLegalText(v, PlatformFieldLimits.companyName, 'Şirket unvanı'),
                ),
                const SizedBox(height: AppSpace.md),
                _field(
                  'company_address',
                  'Şirket adresi',
                  icon: Icons.location_on_outlined,
                  minLines: 2,
                  maxLines: 5,
                  validator: (v) =>
                      validatePlatformLegalText(v, PlatformFieldLimits.companyAddress, 'Şirket adresi'),
                ),
                const SizedBox(height: AppSpace.md),
                _field(
                  'mersis_no',
                  'MERSİS numarası',
                  icon: Icons.tag_rounded,
                  keyboardType: TextInputType.number,
                  formatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
                  helper: '16 rakam; isteğe bağlı.',
                  validator: validatePlatformMersis,
                ),
                const SizedBox(height: AppSpace.md),
                _field(
                  'kep_address',
                  'KEP adresi',
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  helper: 'İsteğe bağlı.',
                  validator: (v) => validatePlatformEmail(v, 'KEP adresi'),
                ),
                const SizedBox(height: AppSpace.md),
                _field(
                  'contact_email',
                  'İletişim e-postası',
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => validatePlatformEmail(v, 'İletişim e-postası'),
                ),
                const SizedBox(height: AppSpace.md),
                _field(
                  'contact_phone',
                  'İletişim telefonu',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  formatters: const [PhoneInputFormatter(mobileOnly: false)],
                  hint: phoneFieldHintAny,
                  last: true,
                  validator: (v) => validatePhoneInput(v, stored: _baseline?.legal.contactPhone, mobileOnly: false),
                ),
                const SizedBox(height: AppSpace.sm),
                SwitchListTile(
                  key: const ValueKey<String>('platform_enforce_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Onayları zorunlu kıl'),
                  subtitle: const Text(
                    'Açıkken kayıt ve site başvurusunda, tamamlanmış yasal belgeleri onaylamayan kullanıcılar '
                    'işlem yapamaz. Kapalıyken eski uygulama sürümleri de çalışır.',
                  ),
                  value: _enforceConsents,
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() => _enforceConsents = value);
                          _recomputeDirty();
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          _slot(
            _formError != null,
            () => CrmFormError(message: _formError!, reveal: false, announce: true),
          ),
          _slot(
            _saveError != null,
            () => Focus(
              key: const ValueKey<String>('platform_save_error_focus'),
              focusNode: _errorFocus,
              child: CrmFormError(message: _saveError!, announce: true),
            ),
          ),
          _slot(
            _savedNotice != null && !_dirty,
            () => Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: InlineNotice(
                key: const ValueKey<String>('platform_saved_notice'),
                tone: AppTone.success,
                message: _savedNotice!,
              ),
            ),
          ),
          PrimaryActionButton(
            key: const ValueKey<String>('platform_save'),
            label: 'Değişiklikleri Kaydet',
            icon: Icons.save_outlined,
            loading: _saving,
            onPressed: (!_dirty || _busy || _confirming || _retry.locked) ? null : _save,
          ),
          _slot(
            !_dirty && !_busy,
            () => Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                noChangesText,
                key: const ValueKey<String>('platform_no_changes'),
                style: th.bodySmall?.copyWith(color: context.palette.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey<String>('platform_revert'),
              onPressed: (!_dirty || _busy) ? null : _revert,
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Değişiklikleri Geri Al'),
            ),
          ),
        ],
      ),
    );
  }
}
