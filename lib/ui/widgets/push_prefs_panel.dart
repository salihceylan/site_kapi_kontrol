import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/push_api.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Saat seçici (testlerde sahtesi verilir).
typedef PushTimePicker =
    Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initial, String helpText);

/// Profil -> Bildirim Tercihleri içindeki "Telefon bildirimi" bölümü (Platform Faz 3b-B, docs/PLATFORM_BELGELER.md
/// B7/B8). Yalnız sunucu `push_available: true` dediğinde gösterilir (değilse üst bölüm "Yakında…" der).
///
/// - Tercihler (`push_announcements`, başlık önizlemesi, sessiz saatler), cihaz listesi ve bu cihazın durumu
///   sunucudan / işletim sisteminden okunur; yüklenirken iskelet, hata olursa hata + "Tekrar Dene" (varsayılan
///   anahtar ASLA çizilmez).
/// - Her anahtar değişince KISMİ `PUT` gider; sürerken anahtarlar kilitli, başarısızsa eski değere döner ve hata
///   görünür kalır. Yanıt eski bir yüklemeyi ezmez (jeton).
/// - AÇIK RIZA: bu cihaz yalnız kullanıcı "Bu cihazda aç"a ya da "Telefon bildirimi" anahtarını açmaya dokununca
///   kaydolur; işletim sistemi izni de o anda, bağlam içinde istenir. Kalıcı retten (ve Android 13 öncesinde
///   ayarlardan kapatılmış bildirimde) yalnız "Telefon ayarlarını aç" sunulur; ayarlardan dönünce kayıt bitene dek
///   beklenir, durum sonra okunur.
/// - Acil duyurular bu tercihten ve sessiz saatlerden etkilenmez; ekran bunu açıkça yazar.
/// - Hesap değişince (yeni [authService]) her şey yeniden yüklenir.
class PushPrefsPanel extends StatefulWidget {
  const PushPrefsPanel({
    super.key,
    required this.authService,
    required this.pushService,
    this.pickTime,
  });

  final AuthService authService;
  final PushService pushService;

  /// Verilmezse [showTimePicker] (24 saat biçimi, Türkçe düğmeler).
  final PushTimePicker? pickTime;

  @override
  State<PushPrefsPanel> createState() => PushPrefsPanelState();
}

class PushPrefsPanelState extends State<PushPrefsPanel> {
  PushPreferences? _prefs;
  List<PushDevice> _devices = const <PushDevice>[];
  PushDeviceState? _device;
  bool _loading = false;
  String? _loadError;
  bool _saving = false;
  bool _deviceBusy = false;
  bool _testing = false;
  String? _removingId;
  String? _error;
  String? _notice;
  AppTone _noticeTone = AppTone.info;
  int _token = 0;
  int _deviceToken = 0;
  AppLifecycleListener? _lifecycle;
  PushService? _listening;

  static const String unsupportedNote =
      'Bu cihaz telefon bildirimi almaz; telefon bildirimleri Android ve iOS uygulamasında çalışır. '
      'Buradaki tercihler telefonlarınız için geçerlidir.';
  static const String preparingNote = 'Telefon bildirimi hazırlanıyor…';
  static const String notConfiguredNote = 'Bu uygulama sürümünde telefon bildirimi yok.';
  static const String settingsNote =
      'Bildirim izni kapalı. Telefon ayarlarından izin verin. İzin verdiğinizde bu cihaz telefon bildirimi için '
      'kaydedilir.';
  static const String cleanupPendingNote =
      'Bu cihazdaki önceki oturumun bildirim kaydı henüz temizlenemedi. Temizlenince bu cihaz kendiliğinden '
      'kaydedilir; biraz sonra tekrar deneyebilirsiniz.';
  static const String tokenUnavailableNote =
      'Bu cihaz şu an kaydedilemedi: telefonun bildirim kaydı hazır değil ya da bağlantı yok. Biraz sonra tekrar '
      'deneyin.';
  static const String disabledHereNote = 'Bu cihazda telefon bildirimi kapalı.';
  static const String noPermissionNote = 'Bu cihazda bildirim izni verilmedi.';
  static const String notRegisteredNote = 'Bu cihaz henüz kaydedilmedi.';
  static const String registeringNote = 'Bu cihaz kaydediliyor…';
  static const String emptyDevicesNote =
      'Kayıtlı cihaz yok. Telefon bildirimi almak için uygulamayı telefonunuzda açın ve "Bu cihazda aç"a dokunun.';

  AuthService get _auth => widget.authService;
  PushService get _push => widget.pushService;

  @override
  void initState() {
    super.initState();
    // Telefon ayarlarından dönünce: kayıt (gerekiyorsa) bitene dek beklenir, durum sonra okunur.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_afterResume()));
    _listen(_push);
    unawaited(reload());
  }

  @override
  void didUpdateWidget(PushPrefsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pushService, widget.pushService)) _listen(widget.pushService);
    if (!identical(oldWidget.authService, widget.authService) ||
        !identical(oldWidget.pushService, widget.pushService)) {
      // Hesap değişti: eski hesabın tercihi / cihazları yeni hesaba sızmasın.
      _prefs = null;
      _devices = const <PushDevice>[];
      _device = null;
      _saving = false;
      _deviceBusy = false;
      _testing = false;
      _removingId = null;
      _error = null;
      _notice = null;
      ++_deviceToken;
      unawaited(reload());
    }
  }

  @override
  void dispose() {
    ++_token;
    ++_deviceToken;
    _unlisten();
    _lifecycle?.dispose();
    super.dispose();
  }

  void _listen(PushService service) {
    _unlisten();
    _listening = service;
    service.changes.addListener(_onPushChanged);
    service.startState.addListener(_onPushChanged);
    service.busy.addListener(_onBusyChanged);
  }

  void _unlisten() {
    final service = _listening;
    if (service == null) return;
    service.changes.removeListener(_onPushChanged);
    service.startState.removeListener(_onPushChanged);
    service.busy.removeListener(_onBusyChanged);
    _listening = null;
  }

  /// Cihaz durumu değişti (kayıt bitti, başlatma tamamlandı / başarısız): durum yeniden okunur.
  void _onPushChanged() => unawaited(_refreshDevice());

  void _onBusyChanged() {
    if (!mounted) return;
    // Bildirim bir kare kurulurken gelebilir: yeniden çizim sonraki kareye bırakılır.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _afterResume() async {
    if (!mounted || _prefs == null) return;
    // İzin durumu hemen okunur (kayıt sürerken "kaydediliyor" görünür); kayıt bitince durum yeniden okunur.
    final sync = _push.syncNow(_auth);
    unawaited(_refreshDevice());
    await sync;
    await _refreshDevice();
  }

  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _loadError = null;
      _saving = false;
    });
    try {
      final results = await Future.wait<Object>(<Future<Object>>[
        _push.getPreferences(_auth),
        _push.listDevices(_auth),
        _push.deviceState(_auth),
      ]);
      if (!mounted || token != _token) return;
      setState(() {
        _prefs = results[0] as PushPreferences;
        _devices = results[1] as List<PushDevice>;
        _device = results[2] as PushDeviceState;
        _loading = false;
      });
      if (_refreshAgain) unawaited(_refreshDevice());
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _loadError = crmMessageOf(
          e,
          'Telefon bildirimi ayarları yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  bool _refreshing = false;
  bool _refreshAgain = false;

  /// Bu cihazın durumu ve cihaz listesi sessizce yeniden okunur (iskelet yok; hata yok sayılır). Art arda gelen
  /// istekler birleştirilir; ilk yükleme sürerken gelen istek yüklemeden sonra çalışır.
  Future<void> _refreshDevice() async {
    if (!mounted) return;
    if (_prefs == null || _refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        await _refreshOnce();
      } while (_refreshAgain && mounted);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshOnce() async {
    final token = _deviceToken;
    try {
      final results = await Future.wait<Object>(<Future<Object>>[
        _push.listDevices(_auth),
        _push.deviceState(_auth),
      ]);
      if (!mounted || token != _deviceToken) return;
      setState(() {
        _devices = results[0] as List<PushDevice>;
        _device = results[1] as PushDeviceState;
      });
    } catch (_) {
      // Liste güncellenemedi: eski görünüm kalır; "Tekrar Dene" üst yüklemede.
    }
  }

  bool get _thisDeviceRegistered {
    final id = _device?.installId;
    return id != null && _devices.any((d) => d.installId == id);
  }

  /// Bu cihaz şu an bildirim alabilir mi (destekleniyor, rıza var, izin var, sunucuda kayıtlı)?
  bool get _thisDeviceActive {
    final device = _device;
    return device != null &&
        device.supported &&
        device.enabledHere &&
        device.permission == PushPermission.granted &&
        _thisDeviceRegistered;
  }

  bool get _busy => _saving || _deviceBusy || _testing || _removingId != null;

  void _clearMessages() {
    _error = null;
    _notice = null;
  }

  /// [keepMessages]: önceki adımın (ör. cihazı açma) sonucu ekranda kalır; yalnız yeni hata yazılır.
  Future<void> _save(PushPreferencesPatch patch, {bool keepMessages = false}) async {
    final before = _prefs;
    if (before == null || _saving) return;
    final token = ++_token;
    setState(() {
      _saving = true;
      if (!keepMessages) _clearMessages();
      _prefs = patch.applyTo(before);
    });
    try {
      final saved = await _push.updatePreferences(_auth, patch, before);
      if (!mounted || token != _token) return;
      setState(() {
        _prefs = saved;
        _saving = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _prefs = before;
        _saving = false;
        _error = crmMessageOf(
          e,
          'Tercih kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  /// "Telefon bildirimi" anahtarı. Açarken bu cihaz henüz bildirim almıyorsa bu dokunuş bu cihaz için de AÇIK
  /// RIZADIR: izin burada istenir ve cihaz kaydedilir. İzin verilmese de hesap tercihi kaydedilir (diğer telefonlar
  /// için geçerlidir) ve cihaz durumu ekranda görünür kalır.
  Future<void> _setAnnouncements(bool value) async {
    if (_prefs == null || _busy) return;
    final device = _device;
    var enabledDevice = false;
    if (value && device != null && device.supported && !_thisDeviceActive) {
      await _enableThisDevice();
      if (!mounted) return;
      enabledDevice = true;
    }
    await _save(PushPreferencesPatch(announcements: value), keepMessages: enabledDevice);
  }

  /// Rıza + (gerekirse) izin + kayıt.
  Future<void> _enableThisDevice() async {
    if (_deviceBusy) return;
    final token = ++_deviceToken;
    setState(() {
      _deviceBusy = true;
      _clearMessages();
    });
    try {
      final outcome = await _push.enableOnThisDevice(_auth);
      if (!mounted || token != _deviceToken) return;
      setState(() {
        _deviceBusy = false;
        switch (outcome) {
          case PushEnableOutcome.registered:
            _notice = 'Bu cihaz telefon bildirimi için kaydedildi.';
            _noticeTone = AppTone.success;
          case PushEnableOutcome.pushUnavailable:
            _notice = PushApi.pushUnavailableMessage;
            _noticeTone = AppTone.warning;
          case PushEnableOutcome.tokenUnavailable:
            _notice = tokenUnavailableNote;
            _noticeTone = AppTone.warning;
          case PushEnableOutcome.cleanupPending:
            _notice = cleanupPendingNote;
            _noticeTone = AppTone.warning;
          case PushEnableOutcome.unsupported:
          case PushEnableOutcome.permissionDenied:
          case PushEnableOutcome.permissionPermanentlyDenied:
            // Cihaz durumu satırı (izin / destek) aşağıda zaten yazar.
            break;
        }
      });
      await _refreshDevice();
    } catch (e) {
      if (!mounted || token != _deviceToken) return;
      setState(() {
        _deviceBusy = false;
        _error = crmMessageOf(
          e,
          'Cihaz kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
      await _refreshDevice();
    }
  }

  Future<void> _openSettings() async {
    setState(_clearMessages);
    final opened = await _push.openSettingsToEnable(_auth);
    if (!mounted || opened) return;
    setState(() {
      _error = 'Telefon ayarları açılamadı. Ayarlar > Uygulamalar bölümünden bildirim iznini açın.';
    });
  }

  Future<void> _pickQuiet({required bool start}) async {
    final prefs = _prefs;
    if (prefs == null || _busy) return;
    final current = start ? prefs.quietStart : prefs.quietEnd;
    final picker = widget.pickTime ?? _showPicker;
    final picked = await picker(
      context,
      TimeOfDay(hour: current ~/ 60, minute: current % 60),
      start ? 'Sessiz saat başlangıcı' : 'Sessiz saat bitişi',
    );
    if (picked == null || !mounted) return;
    final latest = _prefs;
    if (latest == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    final other = start ? latest.quietEnd : latest.quietStart;
    if (minutes == (start ? latest.quietStart : latest.quietEnd)) return;
    if (minutes == other) {
      setState(() {
        _clearMessages();
        _error = 'Başlangıç ve bitiş saati aynı olamaz.';
      });
      return;
    }
    await _save(
      start ? PushPreferencesPatch(quietStart: minutes) : PushPreferencesPatch(quietEnd: minutes),
    );
  }

  static Future<TimeOfDay?> _showPicker(BuildContext context, TimeOfDay initial, String helpText) {
    return showTimePicker(
      context: context,
      initialTime: initial,
      helpText: helpText,
      cancelText: 'Vazgeç',
      confirmText: 'Tamam',
      hourLabelText: 'Saat',
      minuteLabelText: 'Dakika',
      errorInvalidText: 'Geçerli bir saat girin',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
  }

  Future<void> _remove(PushDevice device) async {
    if (_busy) return;
    final isThis = device.installId == _device?.installId;
    final confirmed = await confirmCrmAction(
      context,
      title: 'Cihaz kaldırılsın mı?',
      message: isThis
          ? 'Bu cihaz telefon bildirimi almayı bırakır (acil duyurular dahil). İstediğinizde buradan yeniden '
                'açabilirsiniz.'
          : '${device.platformLabel} telefon bildirimi almayı bırakır. O cihazda oturum açıksa uygulama cihazı '
                'daha sonra yeniden kaydedebilir; kalıcı olarak durdurmak için o cihazda çıkış yapın.',
      confirmLabel: 'Kaldır',
      icon: Icons.phonelink_erase_rounded,
      tone: AppTone.danger,
    );
    if (!confirmed || !mounted) return;
    final token = ++_deviceToken;
    setState(() {
      _removingId = device.installId;
      _clearMessages();
    });
    try {
      await _push.removeDevice(_auth, device.installId);
      if (!mounted || token != _deviceToken) return;
      setState(() {
        _removingId = null;
        _devices = <PushDevice>[
          for (final d in _devices)
            if (d.installId != device.installId) d,
        ];
        _notice = 'Cihaz kaldırıldı.';
        _noticeTone = AppTone.success;
      });
      await _refreshDevice();
    } catch (e) {
      if (!mounted || token != _deviceToken) return;
      setState(() {
        _removingId = null;
        _error = crmMessageOf(
          e,
          'Cihaz kaldırılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  Future<void> _sendTest() async {
    if (_busy || _devices.isEmpty) return;
    final token = _token;
    setState(() {
      _testing = true;
      _clearMessages();
    });
    try {
      final result = await _push.sendTest(_auth);
      if (!mounted || token != _token) return;
      setState(() {
        _testing = false;
        if (result.sent > 0 && result.failed == 0) {
          _notice =
              'Test bildirimi gönderildi (${result.sent} cihaz). Uygulama açıkken bu cihazda ekranın altında kısa '
              'bir bilgi olarak, kapalıyken telefonunuzun bildirimlerinde görünür.';
          _noticeTone = AppTone.success;
        } else if (result.sent > 0) {
          _notice =
              'Test bildirimi ${result.sent} cihaza gönderildi, ${result.failed} cihaza gönderilemedi.';
          _noticeTone = AppTone.warning;
        } else {
          _notice =
              'Test bildirimi hiçbir cihaza ulaşmadı. Bildirim izninin açık olduğunu ve cihazın listede '
              'göründüğünü kontrol edin.';
          _noticeTone = AppTone.warning;
        }
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _testing = false;
        _error = crmMessageOf(
          e,
          'Test bildirimi gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    if (prefs == null) {
      return KeyedSubtree(
        key: const ValueKey<String>('push_panel_loading'),
        child: _loading || _loadError == null
            ? const ListSkeleton(rows: 2, inCard: true)
            : InlineNotice(message: _loadError!, onRetry: reload),
      );
    }
    final th = Theme.of(context).textTheme;
    final locked = _busy;
    return Column(
      key: const ValueKey<String>('push_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loadError != null) ...[
          InlineNotice(message: _loadError!, onRetry: reload),
          const SizedBox(height: AppSpace.md),
        ],
        if (_error != null) ...[
          InlineNotice(key: const ValueKey<String>('push_error'), message: _error!),
          const SizedBox(height: AppSpace.md),
        ],
        if (_notice != null) ...[
          InlineNotice(
            key: const ValueKey<String>('push_notice'),
            message: _notice!,
            tone: _noticeTone,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        SwitchListTile(
          key: const ValueKey<String>('push_announcements_switch'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.phone_android_rounded),
          title: const Text('Telefon bildirimi'),
          subtitle: const Text(
            'Normal duyurular telefonunuza bildirim olarak gelir. Acil duyurular bu tercihten etkilenmez.',
          ),
          value: prefs.announcements,
          onChanged: locked ? null : _setAnnouncements,
        ),
        ..._deviceStatus(context),
        SwitchListTile(
          key: const ValueKey<String>('push_preview_switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Bildirimde duyuru başlığını göster'),
          subtitle: const Text(
            'Açıkken duyurunun başlığı kilit ekranında görünür ve başkaları tarafından okunabilir. Kapalıyken '
            'yalnız "Yönetimden yeni bir duyuru var." yazar.',
          ),
          value: prefs.showPreview,
          onChanged: locked ? null : (v) => _save(PushPreferencesPatch(showPreview: v)),
        ),
        SwitchListTile(
          key: const ValueKey<String>('push_quiet_switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Sessiz saatler'),
          subtitle: const Text(
            'Bu saatlerde normal duyuruların bildirimi bekletilir, sessiz saat bitince gelir. Acil duyurular '
            'sessiz saatlerde de gelir.',
          ),
          value: prefs.quietEnabled,
          onChanged: locked ? null : (v) => _save(PushPreferencesPatch(quietEnabled: v)),
        ),
        if (prefs.quietEnabled) ...[
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              OutlinedButton.icon(
                key: const ValueKey<String>('push_quiet_start'),
                onPressed: locked ? null : () => _pickQuiet(start: true),
                icon: const Icon(Icons.bedtime_outlined, size: 18),
                label: Text('Başlangıç: ${formatPushClock(prefs.quietStart)}'),
              ),
              OutlinedButton.icon(
                key: const ValueKey<String>('push_quiet_end'),
                onPressed: locked ? null : () => _pickQuiet(start: false),
                icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                label: Text('Bitiş: ${formatPushClock(prefs.quietEnd)}'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text('Saatler Türkiye saatine göredir.', style: th.bodySmall),
        ],
        const SizedBox(height: AppSpace.lg),
        Text('Cihazlarım', style: th.titleSmall),
        const SizedBox(height: AppSpace.xs),
        if (_devices.isEmpty)
          Text(
            emptyDevicesNote,
            key: const ValueKey<String>('push_devices_empty'),
            style: th.bodySmall,
          )
        else
          for (final device in _devices)
            _DeviceRow(
              key: ValueKey<String>('push_device_${device.installId}'),
              device: device,
              isThis: device.installId == _device?.installId,
              removing: _removingId == device.installId,
              onRemove: locked ? null : () => _remove(device),
            ),
        const SizedBox(height: AppSpace.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey<String>('push_test_button'),
            onPressed: locked || _devices.isEmpty ? null : _sendTest,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active_outlined, size: 18),
            label: Text(_testing ? 'Gönderiliyor...' : 'Test bildirimi gönder'),
          ),
        ),
      ],
    );
  }

  /// Bu cihazın durumu: desteklenmiyor / hazırlanıyor / bu sürümde yok / kalıcı ret / kapalı / izin yok /
  /// kaydediliyor / kayıtsız. Her şey yolundaysa boş.
  List<Widget> _deviceStatus(BuildContext context) {
    final device = _device;
    if (device == null) return const <Widget>[];
    final locked = _busy;
    String message;
    AppTone tone = AppTone.warning;
    final actions = <Widget>[];
    Widget enableButton(String label) => FilledButton.tonalIcon(
      key: const ValueKey<String>('push_enable_device'),
      onPressed: locked ? null : _enableThisDevice,
      icon: _deviceBusy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.notifications_rounded, size: 18),
      label: Text(label),
    );
    Widget settingsButton() => OutlinedButton.icon(
      key: const ValueKey<String>('push_open_settings'),
      onPressed: locked ? null : _openSettings,
      icon: const Icon(Icons.settings_outlined, size: 18),
      label: const Text('Telefon ayarlarını aç'),
    );
    switch (device.support) {
      case PushSupport.unsupportedPlatform:
        message = unsupportedNote;
        tone = AppTone.info;
      case PushSupport.preparing:
        message = preparingNote;
        tone = AppTone.info;
      case PushSupport.notConfigured:
        message = notConfiguredNote;
        tone = AppTone.info;
      case PushSupport.ready:
        final permission = device.permission;
        if (permission == PushPermission.permanentlyDenied) {
          // Sistem bir daha sormaz (iOS'ta ret, Android 13 öncesinde ayarlardan kapatma): yalnız ayarlar.
          message = settingsNote;
          actions.add(settingsButton());
        } else if (!device.enabledHere) {
          message = disabledHereNote;
          tone = AppTone.info;
          actions.add(enableButton('Bu cihazda aç'));
        } else if (permission == null || !permission.isGranted) {
          message = noPermissionNote;
          actions.add(enableButton('İzin ver'));
          if (permission == PushPermission.denied) actions.add(settingsButton());
        } else if (!_thisDeviceRegistered) {
          tone = AppTone.info;
          if (_push.busy.value || _deviceBusy) {
            message = registeringNote;
          } else {
            message = notRegisteredNote;
            actions.add(enableButton('Bu cihazı kaydet'));
          }
        } else {
          return const <Widget>[];
        }
    }
    return <Widget>[
      const SizedBox(height: AppSpace.xs),
      InlineNotice(key: const ValueKey<String>('push_device_status'), message: message, tone: tone),
      if (actions.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: actions),
      ],
      const SizedBox(height: AppSpace.sm),
    ];
  }
}

/// Cihaz listesi satırı: platform simgesi, ad (+ "Bu cihaz"), son etkinlik, sürüm ve "Kaldır". Dar ekranda ve
/// büyük yazıda taşmaz: metin sarar, düğme metnin altındadır.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    super.key,
    required this.device,
    required this.isThis,
    required this.removing,
    required this.onRemove,
  });

  final PushDevice device;
  final bool isThis;
  final bool removing;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final version = device.appVersion;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              device.platform == 'ios' ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
              size: 22,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      device.platformLabel,
                      style: th.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (isThis)
                      const StatusChip(
                        key: ValueKey<String>('push_this_device'),
                        label: 'Bu cihaz',
                        tone: AppTone.info,
                      ),
                  ],
                ),
                Text(
                  'Son etkinlik: ${formatDateTimeOrUnknown(device.lastSeenAt)}',
                  style: th.bodySmall,
                ),
                if (version != null) Text('Uygulama sürümü: $version', style: th.bodySmall),
                TextButton.icon(
                  onPressed: removing ? null : onRemove,
                  icon: removing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(removing ? 'Kaldırılıyor...' : 'Kaldır'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(64, 48),
                    alignment: AlignmentDirectional.centerStart,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
