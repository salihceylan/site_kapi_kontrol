import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/ble_wifi_provision_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/qr_scan_page.dart';

class WifiQrCredentials {
  const WifiQrCredentials({
    required this.ssid,
    required this.password,
    this.authType = 'WPA',
    this.hidden = false,
  });

  final String ssid;
  final String password;
  final String authType;
  final bool hidden;

  static WifiQrCredentials? tryParse(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;

    // 1. Standard WIFI URI: WIFI:T:WPA;S:MyNetwork;P:MyPassword;H:false;;
    if (text.toLowerCase().startsWith('wifi:')) {
      final content = text.substring(5);
      String ssid = '';
      String password = '';
      String authType = 'WPA';
      bool hidden = false;

      final regex = RegExp(r'([A-Za-z]+):((?:\\;|[^;])*)');
      final matches = regex.allMatches(content);

      for (final match in matches) {
        final key = match.group(1)?.toUpperCase();
        var val = match.group(2) ?? '';
        val = val
            .replaceAll(r'\;', ';')
            .replaceAll(r'\:', ':')
            .replaceAll(r'\\', r'\')
            .replaceAll(r'\"', '"')
            .replaceAll(r'\,', ',');

        if (key == 'S') {
          ssid = val;
        } else if (key == 'P') {
          password = val;
        } else if (key == 'T') {
          authType = val.toUpperCase();
        } else if (key == 'H') {
          hidden = val.toLowerCase() == 'true';
        }
      }

      if (ssid.isNotEmpty) {
        return WifiQrCredentials(
          ssid: ssid,
          password: password,
          authType: authType,
          hidden: hidden,
        );
      }
    }

    // 2. JSON format fallback e.g. {"ssid": "...", "password": "..."}
    if (text.startsWith('{') && text.endsWith('}')) {
      try {
        final Map<String, dynamic> json =
            jsonDecode(text) as Map<String, dynamic>;
        final dynamic rawSsid = json['ssid'] ?? json['SSID'];
        final dynamic rawPass =
            json['password'] ?? json['pass'] ?? json['key'] ?? '';
        if (rawSsid != null && rawSsid.toString().trim().isNotEmpty) {
          return WifiQrCredentials(
            ssid: rawSsid.toString().trim(),
            password: rawPass?.toString().trim() ?? '',
            authType: (json['type']?.toString() ?? 'WPA').toUpperCase(),
          );
        }
      } catch (_) {}
    }

    return null;
  }
}

class WifiProvisionPage extends StatefulWidget {
  const WifiProvisionPage({
    super.key,
    this.authService,
    this.title = 'Bluetooth ile Wi-Fi Kurulumu',
    this.accentColor,
    this.surfaceColor,
    this.service,
  });

  final AuthService? authService;
  final String title;
  final Color? accentColor;
  final Color? surfaceColor;

  /// Yalnız testler için: BLE servisi. Verilmezse gerçek [BleWifiProvisionService] kullanılır.
  @visibleForTesting
  final BleWifiProvisionService? service;

  @override
  State<WifiProvisionPage> createState() => _WifiProvisionPageState();
}

class _WifiProvisionPageState extends State<WifiProvisionPage> {
  late final BleWifiProvisionService _service =
      widget.service ?? BleWifiProvisionService();
  final TextEditingController _passwordController = TextEditingController();

  List<BleProvisionDevice> _devices = const <BleProvisionDevice>[];
  List<BleWifiNetwork> _networks = const <BleWifiNetwork>[];
  BleProvisionDevice? _selectedDevice;
  BleWifiState? _deviceState;
  BleWifiResult? _lastResult;
  String? _selectedSsid;
  bool _loadingDevices = false;
  bool _connectingDevice = false;
  bool _loadingNetworks = false;
  bool _savingWifi = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanDevices());
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _service.disconnect();
    super.dispose();
  }

  void _showMessage(String message) {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scanDevices() async {
    setState(() {
      _loadingDevices = true;
      _devices = const <BleProvisionDevice>[];
      _selectedDevice = null;
      _deviceState = null;
      _networks = const <BleWifiNetwork>[];
      _selectedSsid = null;
      _lastResult = null;
    });

    try {
      final List<BleProvisionDevice> devices = await _service.scanDevices();
      if (!mounted) return;
      setState(() => _devices = devices);
      if (devices.isEmpty) {
        _showMessage(
          'Kurulum modunda cihaz bulunamadı. Gerekirse cihazdaki butona 3 saniye basın.',
        );
      }
    } on BleProvisionException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _loadingDevices = false);
      }
    }
  }

  Future<void> _connectDevice(BleProvisionDevice device) async {
    setState(() {
      _connectingDevice = true;
      _selectedDevice = device;
      _deviceState = null;
      _networks = const <BleWifiNetwork>[];
      _selectedSsid = null;
      _lastResult = null;
    });

    try {
      final BleWifiState state = await _service.connect(device);
      final BleWifiResult result = await _service.readResult();
      if (!mounted) return;
      setState(() {
        _deviceState = state;
        _lastResult = result;
      });
      if (!state.provisioning) {
        _showMessage(
          'Cihaz kurulum modunda değil. Gerekirse butona 3 saniye basıp tekrar deneyin.',
        );
      }
    } on BleProvisionException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _connectingDevice = false);
      }
    }
  }

  Future<void> _loadNetworks() async {
    setState(() {
      _loadingNetworks = true;
      _networks = const <BleWifiNetwork>[];
      _selectedSsid = null;
    });

    try {
      final List<BleWifiNetwork> networks = await _service.scanNetworks();
      final BleWifiResult result = await _service.readResult();
      if (!mounted) return;
      setState(() {
        _networks = networks;
        _lastResult = result;
        _selectedSsid = networks.isEmpty ? null : networks.first.ssid;
      });
      if (networks.isEmpty) {
        _showMessage('Yakında görünen Wi-Fi ağı bulunamadı.');
      }
    } on BleProvisionException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _loadingNetworks = false);
      }
    }
  }

  Future<void> _scanWifiQr() async {
    final scannedData = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScanPage(
          title: 'Wi-Fi Karekodu Oku',
          instructionText:
              'Modemin veya paylaşılan Wi-Fi ağının karekodunu kameraya gösterin.',
          preserveCase: true,
        ),
      ),
    );

    if (scannedData == null || scannedData.trim().isEmpty) {
      return;
    }

    final creds = WifiQrCredentials.tryParse(scannedData);
    if (creds == null) {
      _showMessage(
        'Geçerli bir Wi-Fi karekodu bulunamadı. Lütfen modem veya Wi-Fi paylaşım karekodu okutun.',
      );
      return;
    }

    setState(() {
      _selectedSsid = creds.ssid;
      _passwordController.text = creds.password;
    });

    _showMessage(
      '"${creds.ssid}" ağı karekoddan okundu. "Wi-Fi Bilgilerini Cihaza Kaydet" butonuna basabilirsiniz.',
    );
  }

  Future<void> _saveWifi() async {
    final String? ssid = _selectedSsid;
    if (ssid == null || ssid.isEmpty) {
      _showMessage('Önce bir Wi-Fi ağı seçin veya karekod okutun.');
      return;
    }
    if (_passwordController.text.trim().isEmpty) {
      _showMessage('Seçilen ağ için şifre girin.');
      return;
    }

    setState(() => _savingWifi = true);
    try {
      final String deviceUid = (_deviceState?.deviceUid ?? '').trim();
      if (deviceUid.isEmpty) {
        throw const BleProvisionException(
          'Cihaz unique id okunamadı. Önce Bluetooth cihazına bağlanın.',
        );
      }

      final AuthService? authService = widget.authService;
      if (authService == null) {
        throw const BleProvisionException(
          'MQTT kimliği alınacak oturum bulunamadı.',
        );
      }

      final (Map<String, dynamic>? mqttCredentials, String? mqttError) =
          await authService.getDeviceMqttCredentials(deviceUid: deviceUid);
      if (mqttError != null || mqttCredentials == null) {
        throw BleProvisionException(
          mqttError ?? 'MQTT cihaz kimliği alınamadı.',
        );
      }

      final BleWifiResult result = await _service.provisionWifi(
        ssid: ssid,
        password: _passwordController.text.trim(),
        mqttCredentials: mqttCredentials,
      );
      final BleWifiState state = await _service.readState();
      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _deviceState = state;
      });
      _showMessage(
        result.message.isEmpty ? 'Wi-Fi ayarı kaydedildi.' : result.message,
      );
    } on BleProvisionException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _savingWifi = false);
      }
    }
  }

  String _signalText(int rssi) {
    if (rssi >= -55) return 'Çok güçlü';
    if (rssi >= -67) return 'Güçlü';
    if (rssi >= -75) return 'Orta';
    return 'Zayıf';
  }

  /// Sinyal rozeti tonu ([_signalText] ile aynı eşikler): çok güçlü = başarı, güçlü = bilgi,
  /// orta = uyarı, zayıf = hata. Renk tek başına anlam taşımaz: rozet metni de vardır.
  AppTone _signalTone(int rssi) {
    if (rssi >= -55) return AppTone.success;
    if (rssi >= -67) return AppTone.info;
    if (rssi >= -75) return AppTone.warning;
    return AppTone.danger;
  }

  Widget _signalChip(int rssi) {
    return StatusChip(
      label: '${_signalText(rssi)} ($rssi dBm)',
      tone: _signalTone(rssi),
      icon: Icons.signal_cellular_alt_rounded,
    );
  }

  Widget _sectionCard({required Widget child}) {
    return SizedBox(
      width: double.infinity,
      child: AppCard(child: child),
    );
  }

  Widget _buildInstructions() {
    final th = Theme.of(context).textTheme;

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text('Kurulum Sırası', style: th.titleLarge),
          ),
          const SizedBox(height: 8),
          const Text(
            '1. Wi-Fi ayarı olmayan veya resetlenen cihaz bu listede Bluetooth ile görünür.',
          ),
          const SizedBox(height: 4),
          const Text(
            '2. Cihaz önce şirket hesabına kaydedilmiş olmalıdır (MQTT kimliği hazırlanır).',
          ),
          const SizedBox(height: 4),
          const Text(
            '3. Cihaza bağlanın; Wi-Fi ağlarını tarayarak seçin veya modemin karekodunu okutun.',
          ),
          const SizedBox(height: 4),
          const Text(
            '4. Şifreyi onaylayıp kaydedin. Uygulama, MQTT kimliği ile birlikte cihazı internete bağlar.',
          ),
          const SizedBox(height: 4),
          const Text(
            '5. Ağ değişirse cihazdaki butona 3 saniye basılı tutarak Wi-Fi ayarını sıfırlayabilirsiniz.',
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'Bluetooth Cihazları',
            trailing: IconButton(
              onPressed: _loadingDevices ? null : _scanDevices,
              icon: _loadingDevices
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: 12),
          if (!_service.isSupportedPlatform)
            const Text(
              'Bu ekranı Android veya iPhone cihazdan açın. Masaüstü derlemelerinde BLE provisioning kapalı tutulur.',
            )
          else if (_devices.isEmpty && !_loadingDevices)
            const Text(
              'Kurulum modunda cihaz bulunamadı. Gerekirse cihazdaki butona 3 saniye basın ve yeniden tarayın.',
            )
          else if (_devices.isEmpty)
            // Tarama sürüyor: cihaz satırı iskeletleri (yalnız tarama süresince ağaçta).
            const _ScanSkeleton()
          else
            ..._devices.map(
              (BleProvisionDevice device) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  selected: _selectedDevice?.id == device.id,
                  child: ListTile(
                    selected: _selectedDevice?.id == device.id,
                    title: Text(device.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(device.id),
                        const SizedBox(height: AppSpace.xs),
                        _signalChip(device.rssi),
                      ],
                    ),
                    trailing:
                        _connectingDevice && _selectedDevice?.id == device.id
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bluetooth_connected_outlined),
                    onTap: _connectingDevice
                        ? null
                        : () => _connectDevice(device),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProvisionPanel() {
    final BleProvisionDevice? device = _selectedDevice;
    final BleWifiState? state = _deviceState;
    if (device == null) {
      return const SizedBox.shrink();
    }

    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final successInk = AppTone.success.ink(p);
    final hasScannedNetworks = _networks.isNotEmpty;
    final isSelectedFromQr =
        _selectedSsid != null &&
        _selectedSsid!.isNotEmpty &&
        !_networks.any((n) => n.ssid == _selectedSsid);

    const spinner = SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(device.name, style: th.titleLarge),
          ),
          const SizedBox(height: 8),
          Text('Bluetooth ID: ${device.id}'),
          if (state != null) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Unique ID: ${state.deviceUid.isEmpty ? '-' : state.deviceUid}',
                      ),
                      Text(
                        'Kayıtlı SSID: ${state.ssid.isEmpty ? '-' : state.ssid}',
                      ),
                      Text(
                        'Wi-Fi Durumu: ${state.wifiConnected ? 'Bağlı' : 'Bağlı değil'}',
                      ),
                      Text('IP: ${state.ip.isEmpty ? '-' : state.ip}'),
                      Text(
                        'MQTT Kimliği: ${state.mqttConfigured ? 'Hazır' : 'Eksik veya henüz yazılmadı'}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if ((_lastResult?.message ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(_lastResult!.message, style: th.bodySmall),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              ElevatedButton.icon(
                onPressed: _loadingNetworks || _savingWifi
                    ? null
                    : _loadNetworks,
                icon: _loadingNetworks
                    ? spinner
                    : const Icon(Icons.wifi_find_outlined),
                label: Text(
                  _loadingNetworks ? 'Taranıyor...' : 'Wi-Fi Ağlarını Tara',
                ),
              ),
              ElevatedButton.icon(
                onPressed: _savingWifi ? null : _scanWifiQr,
                // Beyaz etiket >= 4,5:1: eski camgöbeği #0D9488 3,7:1 idi; QR = başarı tonu.
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTone.success.a,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.qr_code_scanner_outlined),
                label: const Text('Karekod ile Wi-Fi Oku'),
              ),
              OutlinedButton.icon(
                onPressed: _connectingDevice
                    ? null
                    : () => _connectDevice(device),
                icon: const Icon(Icons.sync_outlined),
                label: const Text('Durumu Yenile'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingNetworks && !hasScannedNetworks)
            // Ağ taraması sürüyor: satır iskeletleri.
            const _ScanSkeleton()
          else if (!hasScannedNetworks && _selectedSsid == null)
            const Text(
              'Wi-Fi bilgisi girmek için "Wi-Fi Ağlarını Tara" butonuna basın veya "Karekod ile Wi-Fi Oku" seçeneğiyle modem karekodunu okutun.',
            )
          else ...<Widget>[
            Semantics(
              header: true,
              child: Text('Seçili Wi-Fi Ağı', style: th.titleMedium),
            ),
            const SizedBox(height: 8),
            if (isSelectedFromQr)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  tone: AppTone.success,
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(
                      Icons.qr_code_2_outlined,
                      color: successInk,
                      size: 28,
                    ),
                    title: Text(
                      _selectedSsid!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Karekoddan Okunan Ağ',
                      style: TextStyle(color: successInk),
                    ),
                    trailing: Icon(Icons.check_circle, color: successInk),
                  ),
                ),
              ),
            if (hasScannedNetworks)
              ..._networks.map(
                (BleWifiNetwork network) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    selected: _selectedSsid == network.ssid,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      selected: _selectedSsid == network.ssid,
                      leading: Icon(
                        _selectedSsid == network.ssid
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: AppTone.primary.ink(p),
                      ),
                      title: Text(network.ssid),
                      subtitle: Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xs,
                        children: <Widget>[
                          StatusChip(
                            label: network.secure ? 'Şifreli' : 'Açık ağ',
                            tone: network.secure
                                ? AppTone.neutral
                                : AppTone.warning,
                            icon: network.secure
                                ? Icons.lock_outline_rounded
                                : Icons.lock_open_rounded,
                          ),
                          _signalChip(network.rssi),
                        ],
                      ),
                      onTap: _savingWifi
                          ? null
                          : () => setState(() => _selectedSsid = network.ssid),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Wi-Fi Şifresi',
                helperText: _passwordController.text.isNotEmpty
                    ? 'Şifre hazır. Gerekirse değiştirebilirsiniz.'
                    : 'Seçilen ağ için şifre girin.',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _savingWifi ? null : _saveWifi,
                icon: _savingWifi
                    ? spinner
                    : const Icon(Icons.wifi_password_outlined),
                label: Text(
                  _savingWifi
                      ? 'Bağlanıyor ve Kaydediliyor...'
                      : 'Wi-Fi Bilgilerini Cihaza Kaydet',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Rol rengi ([AppTone.hue]) üstünde başlık metni 4,5:1 vermez (mavi 3,7; zümrüt 2,5): ton
  /// eşleşirse koyu ucu ([AppTone.a]) kullanılır; bilinmeyen renk olduğu gibi kalır.
  static Color _barColorFor(Color accent) {
    for (final tone in AppTone.values) {
      if (tone.hue == accent) return tone.a;
    }
    return accent;
  }

  /// [bar] üstünde daha okunur olan ön plan: beyaz ya da koyu slate.
  static Color _onBarColor(Color bar) {
    const Color light = Colors.white;
    const Color dark = AppColors.textDark;
    double ratio(Color a, Color b) {
      final double l1 = a.computeLuminance();
      final double l2 = b.computeLuminance();
      return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
    }

    return ratio(light, bar) >= ratio(dark, bar) ? light : dark;
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.accentColor ?? AppColors.primary;
    final barColor = _barColorFor(accentColor);
    final onBar = _onBarColor(barColor);
    final titleStyle =
        Theme.of(context).appBarTheme.titleTextStyle ??
        const TextStyle(fontSize: 18, fontWeight: FontWeight.w800);
    return Scaffold(
      backgroundColor: widget.surfaceColor,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: barColor,
        foregroundColor: onBar,
        titleTextStyle: titleStyle.copyWith(color: onBar),
      ),
      body: Container(
        key: const ValueKey<String>('wifi_provision_background'),
        // İçerik ekrandan kısaysa (SingleChildScrollView içeriğe göre küçülür) sayfa arka planı tüm
        // gövdeyi doldursun; aksi halde altta Scaffold'un koyu rol rengi şerit olarak görünür.
        width: double.infinity,
        height: double.infinity,
        decoration: AppDecorations.pageBackground(context),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double padding = constraints.maxWidth < 720 ? 16 : 24;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padding, 16, padding, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _buildInstructions(),
                        const SizedBox(height: 16),
                        _buildDeviceList(),
                        if (_selectedDevice != null) ...<Widget>[
                          const SizedBox(height: 16),
                          _buildProvisionPanel(),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Tarama sürerken (cihaz / Wi-Fi ağı) gösterilen iki satırlık iskelet; tek shimmer, tarama bitince kalkar.
class _ScanSkeleton extends StatelessWidget {
  const _ScanSkeleton();

  @override
  Widget build(BuildContext context) {
    return const ShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ScanSkeletonRow(),
          SizedBox(height: 10),
          _ScanSkeletonRow(),
        ],
      ),
    );
  }
}

class _ScanSkeletonRow extends StatelessWidget {
  const _ScanSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      padding: EdgeInsets.all(AppSpace.md),
      child: Row(
        children: <Widget>[
          SkeletonBox(width: 40, height: 40, radius: AppRadius.sm),
          SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: SkeletonBox(height: 14),
                ),
                SizedBox(height: AppSpace.sm),
                FractionallySizedBox(
                  widthFactor: 0.8,
                  child: SkeletonBox(height: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
