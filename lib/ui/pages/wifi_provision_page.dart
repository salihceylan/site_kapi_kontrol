import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/ble_wifi_provision_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';

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
          'Provision modunda cihaz bulunamadi. Gerekirse cihazdaki butona 3 saniye basin.',
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
      _loadNetworks();
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

  Future<void> _saveWifi() async {
    final String? ssid = _selectedSsid;
    if (ssid == null || ssid.isEmpty) {
      _showMessage('Önce bir Wi-Fi ağı seçin.');
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
            'Kurulum Sirasi',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '1. Wi-Fi ayari olmayan veya resetlenen cihaz bu listede Bluetooth ile gorunur.',
          ),
          SizedBox(height: 4),
          Text(
            '2. Cihaz once sirket veritabanina kayitli olmalidir; unique id ile MQTT kimligi hazirlanir.',
          ),
          SizedBox(height: 4),
          Text(
            '3. Cihaza baglanin, yakindaki SSID listesini alin ve dogru agi secin.',
          ),
          SizedBox(height: 4),
          Text(
            '4. Wi-Fi sifresini girin. Uygulama, kayitli cihazin MQTT kimligini guvenli sekilde cihaza yazar.',
          ),
          SizedBox(height: 4),
          Text(
            '5. Ag degisirse cihazdaki butona 3 saniye basili tutarak Wi-Fi ayarini sifirlayin.',
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
                  'Bluetooth Cihazlari',
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
              'Bu ekrani Android veya iPhone cihazdan acin. Masaustu derlemelerinde BLE provisioning kapali tutulur.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else if (_devices.isEmpty && !_loadingDevices)
            const Text(
              'Provision modunda cihaz bulunamadi. Gerekirse cihazdaki butona 3 saniye basin ve yeniden tara.',
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
            Text('Kayitli SSID: ${state.ssid.isEmpty ? '-' : state.ssid}'),
            Text(
              'Wi-Fi Durumu: ${state.wifiConnected ? 'Bagli' : 'Bagli degil'}',
            ),
            Text('IP: ${state.ip.isEmpty ? '-' : state.ip}'),
            Text(
              'MQTT Kimligi: ${state.mqttConfigured ? 'Hazir' : 'Eksik veya henuz yazilmadi'}',
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
                  _loadingNetworks ? 'Taraniyor...' : 'Wi-Fi Aglarini Tara',
                ),
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
          if (_networks.isEmpty)
            const Text(
              'Wi-Fi listesi alinmadi. Once tarama yapin.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else ...<Widget>[
            const Text(
              'SSID Secimi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
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
                    '${network.secure ? 'Sifreli' : 'Acik ag'}  -  ${_signalText(network.rssi)} (${network.rssi} dBm)',
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
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Wi-Fi Sifresi',
                helperText: 'SSID otomatik gelir, yalnizca sifreyi girersiniz.',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _savingWifi ? null : _saveWifi,
                icon: const Icon(Icons.wifi_password_outlined),
                label: Text(
                  _savingWifi ? 'Baglaniyor...' : 'Wi-Fi Bilgilerini Kaydet',
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
