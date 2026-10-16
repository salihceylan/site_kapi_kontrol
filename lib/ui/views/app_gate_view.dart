import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/config/app_config.dart' as build_config;
import 'package:site_kapi_kontrol/models/app_config.dart';
import 'package:site_kapi_kontrol/services/app_config_service.dart';
import 'package:site_kapi_kontrol/services/app_gate_state.dart';
import 'package:site_kapi_kontrol/services/app_version.dart';
import 'package:site_kapi_kontrol/services/stored_session_probe.dart';
import 'package:site_kapi_kontrol/services/theme_service.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/maintenance_view.dart';
import 'package:site_kapi_kontrol/ui/views/update_required_view.dart';

/// Açılış kapısı: sunucudaki `/public/app-config` yanıtına göre uygulamanın önüne
///
/// - **bakım ekranı** (bakım modu açıksa),
/// - **zorunlu güncelleme ekranı** (kurulu sürüm `min_supported_version` altındaysa),
/// - kapatılabilir **yumuşak güncelleme uyarısı** (`latest_version` üstündeyse)
///
/// koyar. Tasarım kuralları:
/// - Yapılandırma YÜKLENEMEZSE (ağ yok, sunucu hatası, 4 sn zaman aşımı) uygulama ENGELLENMEZ.
/// - Açılış beklemez: [child] hemen çizilir, yapılandırma arka planda gelir. Engel çıkarsa [child]
///   ağaçtan çıkarılmaz ([Offstage]); bakım bitince oturum/durum kaybı olmadan geri dönülür.
/// - Engel ekranı kendi küçük `MaterialApp`'ında çizilir (uygulama navigatörüne dokunulmaz).
/// - **Yönetici kaçışı**: cihazda kayıtlı oturum `super_user` ise bakım ve zorunlu güncelleme engelleri
///   GEÇİLİR (aksi hâlde bakımı kapatacak Platform Ayarları'na hiç girilemezdi) ve altta küçük bir
///   "yönetici görünümü" şeridi gösterilir. Kaçış kalıcı bir mandal DEĞİLDİR: kayıtlı oturum 2 sn'de bir
///   yoklanır; süper kullanıcı çıkış yapıp başka rolden biri girerse engel geri gelir. Oturum yoksa engel
///   ekranındaki "Yönetici girişi" düğmesi geçici olarak giriş ekranını açar; giriş yapılan hesap süper
///   kullanıcı değilse engel geri gelir.
/// - Alt şerit/uyarı uygulamanın ÜZERİNE binmez, uygulamaya yer ayırır (alttaki düğmeleri kapatmaz; alt
///   güvenli alan çift sayılmaz); en çok ekranın %35'i kadardır, aşarsa kendi içinde kayar; klavye açıkken
///   gizlenir.
class AppGate extends StatefulWidget {
  const AppGate({
    super.key,
    required this.child,
    this.themeService,
    this.configService,
    this.installedInfoLoader,
    this.platform,
    this.launcher = openStoreUrl,
    this.prefsLoader,
    this.sessionProbe,
    this.recheckInterval = const Duration(minutes: 10),
    this.entryPollInterval = const Duration(seconds: 2),
  });

  /// Asıl uygulama (genelde `MyApp`).
  final Widget child;

  /// Engel ekranlarının teması için (tercih edilen tema modu); yoksa sistem teması.
  final ThemeService? themeService;

  /// Varsayılan: [AppConfigService.instance].
  final AppConfigService? configService;

  /// Varsayılan: [loadInstalledAppInfo].
  final Future<InstalledAppInfo> Function()? installedInfoLoader;

  /// Varsayılan: [defaultTargetPlatform] (mağaza bağlantısı seçimi).
  final TargetPlatform? platform;

  final StoreLauncher launcher;
  final Future<SharedPreferences> Function()? prefsLoader;

  /// Varsayılan: [probeStoredSession] (güvenli depodaki oturumun rolü).
  final StoredSessionProbe? sessionProbe;

  /// Uygulama ön plana dönünce yapılandırma bu süreden eskiyse yeniden sorulur.
  final Duration recheckInterval;

  /// Yönetici kaçışı/girişi sırasında kayıtlı oturumun yoklanma aralığı.
  final Duration entryPollInterval;

  /// Yumuşak uyarının kapatıldığı son sürüm (SharedPreferences anahtarı).
  static const String dismissedLatestKey = 'app_gate.dismissed_latest';

  /// Alt şeridin/uyarının ekran yüksekliğine oranla üst sınırı.
  static const double bottomBarMaxHeightFraction = 0.35;

  /// "Yönetici girişi" modu en çok bu kadar yoklama yapar (varsayılan aralıkta ~15 dk), sonra engel döner.
  static const int maxEntryPolls = 450;

  /// Yönetici kaçışı açıkken ardışık bu kadar yoklamada süper kullanıcı oturumu görülmezse kaçış kalkar
  /// (tek seferlik geçici okuma hatası ekranı yanıp söndürmesin).
  static const int operatorMissLimit = 2;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> with WidgetsBindingObserver {
  AppGateDecision _decision = AppGateDecision.open;
  InstalledAppInfo? _installed;
  String? _dismissedLatest;
  DateTime? _lastCheck;
  bool _checking = false;
  bool _firstCheckDone = false;

  /// Kayıtlı oturum süper kullanıcı: bakım/güncelleme engelleri geçilir.
  bool _operator = false;
  int _operatorMisses = 0;

  /// "Yönetici girişi" modu: oturum yokken giriş ekranı için engel geçici olarak kalkar.
  bool _entryMode = false;
  int _entryPolls = 0;

  Timer? _watchTimer;
  bool _polling = false;
  String? _operatorNotice;

  AppConfigService get _service =>
      widget.configService ?? AppConfigService.instance;
  TargetPlatform get _platform => widget.platform ?? defaultTargetPlatform;

  bool get _bypass => _operator || _entryMode;

  /// Uygulama bir engel ekranının altında gizli mi?
  bool get _hidden => _decision.blocked && !_bypass;

  /// Kayıtlı oturum yoklanmalı mı? (engel var ve yönetici kaçışı/girişi açık)
  bool get _needsWatch => _decision.blocked && _bypass;

  @override
  void initState() {
    super.initState();
    // Gözlemci kaydı çocuk uygulamadan ÖNCE yapılır: geri tuşunu önce kapı görür.
    WidgetsBinding.instance.addObserver(this);
    // Kapı ağaçta: ilk denetim bitene kadar bekleyen derin bağlantılar bekletilir (AppGateBlock).
    AppGateBlock.pendingFirstCheck.value = true;
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchTimer?.cancel();
    AppGateBlock.active.value = false;
    AppGateBlock.pendingFirstCheck.value = false;
    super.dispose();
  }

  /// Gizli durumu dışarıya (derin bağlantı koruması) duyurur.
  void _publish() {
    AppGateBlock.active.value = _hidden;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    final stale =
        last == null || DateTime.now().difference(last) > widget.recheckInterval;
    // Bakım/güncelleme ekranındaysak her dönüşte yeniden sor (bakım bitmiş olabilir).
    if (_decision.blocked || stale) {
      unawaited(_check(force: true));
    }
  }

  @override
  void didChangeMetrics() {
    // Alt şerit varken güvenli alan değişirse (döndürme, klavye, gezinme çubuğu) yerleşim yenilenir.
    if (mounted && _barContent() != null) setState(() {});
  }

  /// Engel varken geri tuşu uygulamadan çıkar (altındaki uygulamaya dönmez).
  @override
  Future<bool> didPopRoute() async {
    if (!_hidden) return false;
    await SystemNavigator.pop();
    return true;
  }

  Future<StoredSessionKind> _probe() async {
    try {
      return await (widget.sessionProbe ?? probeStoredSession)();
    } catch (_) {
      return StoredSessionKind.none;
    }
  }

  Future<AppConfig?> _check({bool force = false}) async {
    if (_checking) return _service.current;
    _checking = true;
    try {
      final installed =
          _installed ??= await (widget.installedInfoLoader ??
              loadInstalledAppInfo)();
      final config = await _service.load(force: force);
      _lastCheck = DateTime.now();
      await _loadDismissed();
      if (!mounted) return config;
      if (config == null) {
        // Yüklenemedi: engel yoksa açık kal; zaten engelliyse (bakım/güncelleme) engeli koru.
        return null;
      }
      final decision = evaluateAppGate(
        installedVersion: installed.version,
        config: config,
        platform: _platform,
      );
      // Yönetici kaçışı: yalnız engel varsa kayıtlı oturumun rolüne bakılır.
      final operatorNow =
          decision.blocked &&
          (await _probe()) == StoredSessionKind.superUser;
      if (!mounted) return config;
      setState(() {
        _decision = decision;
        _operator = operatorNow;
        _operatorMisses = 0;
        if (!decision.blocked) {
          _entryMode = false;
          _operatorNotice = null;
        }
      });
      _syncWatch();
      _publish();
      return config;
    } catch (_) {
      return null; // Kapı hiçbir koşulda uygulamayı çökertmez/engellemez.
    } finally {
      _checking = false;
      _markFirstCheckDone();
    }
  }

  /// İlk denetim (başarılı ya da başarısız) bitti: bekleyen derin bağlantılar artık kararı görebilir.
  void _markFirstCheckDone() {
    if (_firstCheckDone) return;
    _firstCheckDone = true;
    AppGateBlock.pendingFirstCheck.value = false;
  }

  // --- yönetici girişi / kaçışı ---

  Future<void> _startOperatorLogin() async {
    final kind = await _probe();
    if (!mounted) return;
    switch (kind) {
      case StoredSessionKind.superUser:
        setState(() {
          _operator = true;
          _operatorMisses = 0;
          _operatorNotice = null;
        });
      case StoredSessionKind.none:
        setState(() {
          _entryMode = true;
          _entryPolls = 0;
          _operatorNotice = null;
        });
      case StoredSessionKind.other:
        setState(() {
          _operatorNotice =
              'Yönetici girişi yalnızca süper kullanıcı hesabıyla yapılabilir. '
              'Bu cihazda başka bir hesabın oturumu açık.';
        });
    }
    _syncWatch();
    _publish();
  }

  void _cancelOperatorLogin() {
    setState(() => _entryMode = false);
    _syncWatch();
    _publish();
  }

  /// Kayıtlı oturum yoklayıcısını gerektiği kadar çalıştırır (yönetici kaçışı ya da girişi sürerken).
  void _syncWatch() {
    if (_needsWatch) {
      _watchTimer ??= Timer.periodic(widget.entryPollInterval, (_) {
        unawaited(_pollSession());
      });
    } else {
      _watchTimer?.cancel();
      _watchTimer = null;
    }
  }

  /// - Giriş modunda: oturum açılınca rolüne bakar; süper kullanıcıysa engel kalkık kalır, değilse engel döner.
  /// - Kaçış açıkken: süper kullanıcı oturumu artık görünmüyorsa (çıkış yapıldı / başka rol girdi) kaçış kalkar.
  Future<void> _pollSession() async {
    if (_polling || !_needsWatch) return;
    // Arka plandayken yoklama yapılmaz (pil/güvenli depo erişimi).
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return;
    _polling = true;
    try {
      final kind = await _probe();
      if (!mounted || !_needsWatch) return;
      var changed = false;
      if (_entryMode) {
        _entryPolls++;
        if (kind == StoredSessionKind.superUser) {
          _operator = true;
          _operatorMisses = 0;
          _entryMode = false;
          changed = true;
        } else if (kind == StoredSessionKind.other ||
            _entryPolls >= AppGate.maxEntryPolls) {
          _entryMode = false;
          _operatorNotice = kind == StoredSessionKind.other
              ? 'Bu hesap süper kullanıcı değil; bakım/güncelleme sırasında yalnızca '
                    'yönetici hesabı kullanılabilir.'
              : null;
          changed = true;
        }
      } else if (_operator) {
        if (kind == StoredSessionKind.superUser) {
          _operatorMisses = 0;
        } else if (++_operatorMisses >= AppGate.operatorMissLimit) {
          _operator = false;
          _operatorMisses = 0;
          _operatorNotice = null;
          changed = true;
        }
      }
      if (changed) {
        setState(() {});
        _syncWatch();
        _publish();
      }
    } finally {
      _polling = false;
    }
  }

  // --- yumuşak uyarı ---

  Future<void> _loadDismissed() async {
    if (_dismissedLatest != null) return;
    try {
      final prefs = await (widget.prefsLoader ?? SharedPreferences.getInstance)();
      _dismissedLatest = prefs.getString(AppGate.dismissedLatestKey) ?? '';
    } catch (_) {
      _dismissedLatest = '';
    }
  }

  Future<void> _dismissSoft(String version) async {
    setState(() => _dismissedLatest = version);
    try {
      final prefs = await (widget.prefsLoader ?? SharedPreferences.getInstance)();
      await prefs.setString(AppGate.dismissedLatestKey, version);
    } catch (_) {}
  }

  ThemeMode get _mode => widget.themeService?.mode ?? ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    final hidden = _hidden;
    final content = _barContent();
    final bar = content == null ? null : _scopeBar(context, content);
    // Alt güvenli alan: şerit varken uygulama bu kadar fazla yer kaplar (şeridin güvenli alan dolgusu uygulamanın
    // kendi alt boşluğuyla örtüşür; çift sayılmaz). Uygulamanın MaterialApp'ı MediaQuery'sini görünümden
    // türettiği için üstten removePadding işe yaramaz; bu yüzden yerleşim burada ayarlanır.
    final view = View.of(context);
    final bottomInset = bar == null
        ? 0.0
        : EdgeInsets.fromViewPadding(view.padding, view.devicePixelRatio).bottom;

    return Stack(
      alignment: Alignment.topLeft,
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        // Alt şerit uygulamanın üstüne binmez: uygulama kalan alanı kullanır (alttaki düğmeler kapanmaz).
        // Engel varken uygulama ağaçta kalır (durum korunur) ama çizilmez, dokunulmaz, anlamsal ağaçta yoktur.
        CustomMultiChildLayout(
          delegate: _GateLayoutDelegate(bottomInset: bottomInset),
          children: [
            LayoutId(
              id: _GateSlot.app,
              child: Offstage(offstage: hidden, child: widget.child),
            ),
            if (bar != null) LayoutId(id: _GateSlot.bar, child: bar),
          ],
        ),
        if (hidden)
          Positioned.fill(
            key: const ValueKey<String>('app-gate-blocked'),
            child: _buildBlocked(_decision),
          ),
      ],
    );
  }

  Widget _buildBlocked(AppGateDecision decision) {
    final config = decision.config;
    final Widget home;
    if (decision.status == AppGateStatus.maintenance) {
      home = MaintenanceView(
        message: config?.maintenanceMessage,
        config: config,
        onRetry: () => _check(force: true),
        onOperatorLogin: _startOperatorLogin,
        operatorNotice: _operatorNotice,
      );
    } else {
      home = UpdateRequiredView(
        installedVersion:
            _installed?.version ?? build_config.AppConfig.appVersion,
        minimumVersion: config?.minSupportedVersion ?? '',
        storeUrl: decision.storeUrl,
        config: config,
        launcher: widget.launcher,
        onOperatorLogin: _startOperatorLogin,
        operatorNotice: _operatorNotice,
      );
    }

    final service = widget.themeService;
    Widget app(BuildContext context) => MaterialApp(
      title: build_config.AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: service?.mode ?? ThemeMode.system,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 2.0,
        child: Container(
          decoration: AppDecorations.pageBackground(context),
          child: child,
        ),
      ),
      home: home,
    );
    if (service == null) return Builder(builder: app);
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => app(context),
    );
  }

  /// Altta gösterilecek şerit içeriği: yönetici görünümü ya da yumuşak güncelleme uyarısı (yoksa null).
  Widget? _barContent() {
    final decision = _decision;
    if (decision.blocked && _bypass) {
      final String message;
      if (_entryMode) {
        message =
            'Yönetici girişi: yalnızca süper kullanıcı hesabıyla devam edilebilir.';
      } else if (decision.status == AppGateStatus.maintenance) {
        message =
            'Bakım modu açık (yönetici görünümü). Diğer kullanıcılar bakım ekranını görür.';
      } else {
        message =
            'Bu sürüm artık desteklenmiyor (yönetici görünümü). Diğer kullanıcılar güncelleme ekranını görür.';
      }
      return _OperatorStrip(
        message: message,
        onCancel: _entryMode ? _cancelOperatorLogin : null,
      );
    }
    if (!decision.blocked) {
      final version = decision.softUpdateVersion;
      if (version != null && _dismissedLatest != version) {
        return SoftUpdateBanner(
          latestVersion: version,
          storeUrl: decision.storeUrl,
          launcher: widget.launcher,
          onDismiss: () => _dismissSoft(version),
        );
      }
    }
    return null;
  }

  /// Şeridi uygulamanın MaterialApp'ının ÜSTÜNDE çizmek için kendi MediaQuery/Tema/Yerelleştirme kapsamına sarar.
  Widget _scopeBar(BuildContext context, Widget body) {
    final dark = switch (_mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        View.of(context).platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
    return MediaQuery.fromView(
      view: View.of(context),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Localizations(
          locale: const Locale('tr'),
          delegates: const [
            DefaultWidgetsLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
          ],
          child: Theme(
            data: dark ? AppTheme.dark() : AppTheme.light(),
            child: Material(
              type: MaterialType.transparency,
              child: Builder(
                builder: (scope) {
                  // Klavye açıkken şerit gizlenir (yazı alanına yer kalsın); kapanınca geri gelir.
                  if (MediaQuery.viewInsetsOf(scope).bottom > 0) {
                    return const SizedBox.shrink();
                  }
                  final maxHeight =
                      MediaQuery.sizeOf(scope).height *
                      AppGate.bottomBarMaxHeightFraction;
                  return SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        // Yükseklik içeriği kadar (aksi hâlde sınırlı yükseklikte Align tüm ekranı kaplar).
                        heightFactor: 1,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 520,
                            maxHeight: maxHeight,
                          ),
                          child: SingleChildScrollView(child: body),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _GateSlot { app, bar }

/// Uygulamayı ve (varsa) alt şeridi yerleştirir: şerit altta, uygulama kalan alanda. Şeridin alt güvenli alan
/// dolgusu ([bottomInset]) uygulamanın kendi alt boşluğuyla ÖRTÜŞÜR: uygulama içeriği şeridin üst kenarında
/// biter, aralarında çift güvenli alan boşluğu kalmaz.
class _GateLayoutDelegate extends MultiChildLayoutDelegate {
  _GateLayoutDelegate({required this.bottomInset});

  final double bottomInset;

  @override
  void performLayout(Size size) {
    var barHeight = 0.0;
    if (hasChild(_GateSlot.bar)) {
      final barSize = layoutChild(
        _GateSlot.bar,
        BoxConstraints(
          minWidth: size.width,
          maxWidth: size.width,
          maxHeight: size.height,
        ),
      );
      barHeight = barSize.height;
      positionChild(_GateSlot.bar, Offset(0, size.height - barHeight));
    }
    final overlap = math.min(bottomInset, barHeight);
    final appHeight = math.max(0.0, size.height - barHeight + overlap);
    if (hasChild(_GateSlot.app)) {
      layoutChild(
        _GateSlot.app,
        BoxConstraints.tight(Size(size.width, appHeight)),
      );
      positionChild(_GateSlot.app, Offset.zero);
    }
  }

  @override
  bool shouldRelayout(_GateLayoutDelegate oldDelegate) =>
      oldDelegate.bottomInset != bottomInset;
}

/// Süper kullanıcı engeli geçerken altta görünen "yönetici görünümü" şeridi.
class _OperatorStrip extends StatelessWidget {
  const _OperatorStrip({required this.message, this.onCancel});

  final String message;

  /// Verilirse "Vazgeç" düğmesi (yönetici girişi modundan çıkıp engel ekranına dönmek için).
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: AppCard(
        level: 3,
        tone: AppTone.warning,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: Theme.of(context).textTheme.bodySmall),
            if (onCancel != null) ...[
              const SizedBox(height: AppSpace.xs),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onCancel,
                  child: const Text('Vazgeç'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
