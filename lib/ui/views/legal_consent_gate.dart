import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/views/legal_consent_page.dart';
import 'package:site_kapi_kontrol/ui/views/legal_markdown.dart';

/// Giriş yapmış kullanıcı için "Güncellenen koşullar" kapısı.
///
/// [child] (ana sayfa) her zaman ağaçta kalır; kapı açılışta `GET /me/consents` çağırır:
/// - `pending` BOŞSA hiçbir şey görünmez (kapı şeffaftır),
/// - `pending` DOLUYSA [child] üstüne tam ekran [LegalConsentPage] biner (alttaki sayfa odak ve ekran
///   okuyucudan dışlanır); onaylanınca ya da oturum kapanınca kalkar,
/// - hata / zaman aşımında kullanıcı KİLİTLENMEZ: uygulama açılır, kapı sessizce sonra yeniden dener
///   (artan aralıklarla; uygulama öne gelince de). 401'de oturum sunucudan doğrulanır.
///
/// [onSettled]: ilk denetim sonuçlandığında (bekleyen yok / hata / onay verildi) BİR kez çağrılır; ilk
/// kullanım turu gibi "onaydan sonra" işler buradan başlar.
class LegalConsentGate extends StatefulWidget {
  const LegalConsentGate({
    super.key,
    required this.authService,
    required this.child,
    this.api,
    this.onSettled,
    this.retryDelays = const <Duration>[
      Duration(seconds: 45),
      Duration(minutes: 3),
      Duration(minutes: 10),
    ],
    this.recheckAfter = const Duration(hours: 6),
    this.resumeRecheckGap = const Duration(seconds: 10),
    this.clock,
    this.onOpenLink,
    this.enabled = true,
  });

  final AuthService authService;
  final Widget child;

  /// false: kapı hiçbir şey yapmaz, [child] doğrudan gösterilir (ağ denetimi kapalı testler / önizleme).
  final bool enabled;
  final LegalApi? api;
  final void Function(BuildContext context)? onSettled;

  /// Başarısız denetimden sonra yeniden deneme aralıkları (sonuncusu tekrarlanır).
  final List<Duration> retryDelays;

  /// Başarılı denetimden sonra, uygulama öne gelince yeniden denetim için asgari süre.
  final Duration recheckAfter;

  /// Kapı AÇIKKEN uygulama öne gelişlerinde yeniden denetim arasındaki asgari süre (art arda ön plana
  /// gelişler sunucuyu yormasın). Açık kapıda her denetim bu kadar aralıkla sınırlıdır.
  final Duration resumeRecheckGap;

  /// Şimdiki zaman kaynağı (testler için); verilmezse [DateTime.now].
  final DateTime Function()? clock;

  final LegalLinkOpener? onOpenLink;

  @override
  State<LegalConsentGate> createState() => _LegalConsentGateState();
}

class _LegalConsentGateState extends State<LegalConsentGate> with WidgetsBindingObserver {
  late final LegalApi _api = widget.api ?? LegalApi.defaultInstance();

  List<PendingConsent> _pending = const <PendingConsent>[];
  bool _checking = false;
  bool _settled = false;
  bool _lastFailed = false;
  int _failures = 0;
  Timer? _timer;
  DateTime? _lastSuccessAt;

  /// Son denetimin BAŞLADIĞI an (öne gelişte kısıtlama için).
  DateTime? _lastCheckAt;

  /// Bir denetim sürerken yeni bir istek geldi (örn. onay sırasında bayat liste sinyali): denetim bitince BİR
  /// kez daha çalıştırılır; bayat liste bir sonraki olayı beklemez.
  bool _recheckQueued = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_check());
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _checking) return;
    // Kapı açıkken öne gelişte yeniden denetlenir: belge arada tamamlanmamış / onaysız hâle gelmiş ya da başka
    // cihazdan onaylanmış olabilir (liste boşalırsa kapı kapanır, değişirse güncel liste gösterilir). Denetimler
    // [LegalConsentGate.resumeRecheckGap] aralığıyla sınırlıdır (art arda ön plana gelişler sunucuyu yormaz).
    if (_pending.isNotEmpty) {
      final lastAt = _lastCheckAt;
      if (lastAt != null && _now().difference(lastAt) < widget.resumeRecheckGap) return;
      unawaited(_check());
      return;
    }
    final last = _lastSuccessAt;
    final stale = last == null || _now().difference(last) >= widget.recheckAfter;
    if (_lastFailed || stale) unawaited(_check());
  }

  Future<void> _check() async {
    if (!mounted) return;
    if (_checking) {
      // Sürmekte olan denetimin yanıtı bu isteğin gerektirdiği değişikliği içermeyebilir: bitince bir kez daha.
      _recheckQueued = true;
      return;
    }
    final token = widget.authService.session?.token;
    if (token == null) return;
    _checking = true;
    _lastCheckAt = _now();
    _timer?.cancel();
    try {
      final consents = await _api.getMyConsents(token: token);
      if (!mounted) return;
      _failures = 0;
      _lastFailed = false;
      _lastSuccessAt = _now();
      final wasBlocked = _pending.isNotEmpty;
      setState(() => _pending = consents.pending);
      if (consents.pending.isEmpty) {
        if (wasBlocked) announcePolite(context, 'Onay gerekmiyor; devam edebilirsiniz.');
        _notifySettled();
      }
    } catch (error) {
      if (!mounted) return;
      _lastFailed = true;
      final unauthorized = error is ApiException && error.isUnauthorized;
      if (unauthorized) {
        // Oturum geçersiz olabilir: sunucudan doğrula (gerekirse çıkış yapılır); kapı kilitlemez.
        unawaited(widget.authService.refreshSession(force: true));
      } else {
        _scheduleRetry();
      }
      _notifySettled();
    } finally {
      _checking = false;
      if (_recheckQueued) {
        _recheckQueued = false;
        if (mounted) unawaited(_check());
      }
    }
  }

  void _scheduleRetry() {
    final delays = widget.retryDelays;
    if (delays.isEmpty) return;
    final delay = delays[_failures < delays.length ? _failures : delays.length - 1];
    _failures++;
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (mounted) unawaited(_check());
    });
  }

  void _notifySettled() {
    if (_settled) return;
    _settled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSettled?.call(context);
    });
  }

  void _onAccepted(List<PendingConsent>? remaining) {
    // Sunucu hâlâ bekleyen belge bildiriyorsa kapı açık kalır (yeni listeyle); aksi hâlde kapanır.
    final next = remaining ?? const <PendingConsent>[];
    setState(() => _pending = next);
    if (next.isEmpty) {
      announcePolite(context, 'Koşullar onaylandı.');
      _notifySettled();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final blocked = _pending.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Alttaki sayfa ağaçta kalır (durumu korunur) ama kapı açıkken dokunma, odak ve ekran okuyucudan dışlanır.
        ExcludeFocus(
          excluding: blocked,
          child: ExcludeSemantics(
            excluding: blocked,
            child: IgnorePointer(ignoring: blocked, child: widget.child),
          ),
        ),
        if (blocked)
          Positioned.fill(
            child: FocusScope(
              autofocus: true,
              // Üst katman şeffaf Scaffold kullanır: altındaki sayfa görünmesin diye zemin burada boyanır.
              child: DecoratedBox(
                decoration: AppDecorations.pageBackground(context),
                child: LegalConsentPage(
                  pending: _pending,
                  api: _api,
                  tokenProvider: () => widget.authService.session?.token,
                  onAccepted: _onAccepted,
                  onDecline: () => unawaited(widget.authService.logout()),
                  onStale: _check,
                  onSessionProblem: () =>
                      unawaited(widget.authService.refreshSession(force: true)),
                  onOpenLink: widget.onOpenLink,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
