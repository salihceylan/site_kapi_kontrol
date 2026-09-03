import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/ble_wifi_provision_service.dart';
import 'package:site_kapi_kontrol/services/wifi_qr_parser.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/pages/qr_scan_page.dart';

class WifiProvisionPage extends StatefulWidget {
  const WifiProvisionPage({
    super.key,
    this.authService,
    this.title = 'Bluetooth ile Wi-Fi Kurulumu',
    this.accentColor,
    this.surfaceColor,
  });

  final AuthService? authService;
  final String title;
  final Color? accentColor;
  final Color? surfaceColor;

  @override
  State<WifiProvisionPage> createState() => _WifiProvisionPageState();
}

class _WifiProvisionPageState extends State<WifiProvisionPage> {
  final BleWifiProvisionService _service = BleWifiProvisionService();
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

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.glassCard,
      child: child,
    );
  }

  Widget _buildInstructions() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          Text(
            'Kurulum Sırası',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '1. Wi-Fi ayarı olmayan veya resetlenen cihaz bu listede Bluetooth ile görünür.',
          ),
          SizedBox(height: 4),
          Text(
            '2. Cihaz önce şirket hesabına kaydedilmiş olmalıdır (MQTT kimliği hazırlanır).',
          ),
          SizedBox(height: 4),
          Text(
            '3. Cihaza bağlanın; Wi-Fi ağlarını tarayarak seçin veya modemin karekodunu okutun.',
          ),
          SizedBox(height: 4),
          Text(
            '4. Şifreyi onaylayıp kaydedin. Uygulama, MQTT kimliği ile birlikte cihazı internete bağlar.',
          ),
          SizedBox(height: 4),
          Text(
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
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Bluetooth Cihazları',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: _loadingDevices ? null : _scanDevices,
                icon: _loadingDevices
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_service.isSupportedPlatform)
            const Text(
              'Bu ekranı Android veya iPhone cihazdan açın. Masaüstü derlemelerinde BLE provisioning kapalı tutulur.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else if (_devices.isEmpty && !_loadingDevices)
            const Text(
              'Kurulum modunda cihaz bulunamadı. Gerekirse cihazdaki butona 3 saniye basın ve yeniden tarayın.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else
            ..._devices.map(
              (BleProvisionDevice device) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  selected: _selectedDevice?.id == device.id,
                  title: Text(device.name),
                  subtitle: Text(
                    '${device.id}  -  ${_signalText(device.rssi)} (${device.rssi} dBm)',
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

    final hasScannedNetworks = _networks.isNotEmpty;
    final isSelectedFromQr =
        _selectedSsid != null &&
        _selectedSsid!.isNotEmpty &&
        !_networks.any((n) => n.ssid == _selectedSsid);

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            device.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text('Bluetooth ID: ${device.id}'),
          if (state != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Unique ID: ${state.deviceUid.isEmpty ? '-' : state.deviceUid}',
            ),
            Text('Kayıtlı SSID: ${state.ssid.isEmpty ? '-' : state.ssid}'),
            Text(
              'Wi-Fi Durumu: ${state.wifiConnected ? 'Bağlı' : 'Bağlı değil'}',
            ),
            Text('IP: ${state.ip.isEmpty ? '-' : state.ip}'),
            Text(
              'MQTT Kimliği: ${state.mqttConfigured ? 'Hazır' : 'Eksik veya henüz yazılmadı'}',
            ),
          ],
          if ((_lastResult?.message ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _lastResult!.message,
              style: const TextStyle(color: AppColors.textMuted),
            ),
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
                icon: const Icon(Icons.wifi_find_outlined),
                label: Text(
                  _loadingNetworks ? 'Taranıyor...' : 'Wi-Fi Ağlarını Tara',
                ),
              ),
              ElevatedButton.icon(
                onPressed: _savingWifi ? null : _scanWifiQr,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
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
          if (!hasScannedNetworks && _selectedSsid == null)
            const Text(
              'Wi-Fi bilgisi girmek için "Wi-Fi Ağlarını Tara" butonuna basın veya "Karekod ile Wi-Fi Oku" seçeneğiyle modem karekodunu okutun.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else ...<Widget>[
            const Text(
              'Seçili Wi-Fi Ağı',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (isSelectedFromQr)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: const Color(0xFFF0FDFA),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.qr_code_2_outlined,
                    color: Color(0xFF0D9488),
                    size: 28,
                  ),
                  title: Text(
                    _selectedSsid!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Karekoddan Okunan Ağ',
                    style: TextStyle(color: Color(0xFF0D9488)),
                  ),
                  trailing: const Icon(
                    Icons.check_circle,
                    color: Color(0xFF0D9488),
                  ),
                ),
              ),
            if (hasScannedNetworks)
              ..._networks.map(
                (BleWifiNetwork network) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
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
                      color: AppColors.primary,
                    ),
                    title: Text(network.ssid),
                    subtitle: Text(
                      '${network.secure ? 'Şifreli' : 'Açık ağ'}  -  ${_signalText(network.rssi)} (${network.rssi} dBm)',
                    ),
                    onTap: _savingWifi
                        ? null
                        : () => setState(() => _selectedSsid = network.ssid),
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
                icon: const Icon(Icons.wifi_password_outlined),
                label: Text(
                  _savingWifi
                      ? 'Bağlanıyor ve Kaydediliyor...'
                      : 'Wi-Fi Bilgilerini Cihaza Kaydet',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.accentColor ?? AppColors.primary;
    return Scaffold(
      backgroundColor: widget.surfaceColor,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: accentColor,
      ),
      body: Container(
        decoration: AppDecorations.pageBackground,
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
