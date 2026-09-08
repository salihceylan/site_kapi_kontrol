import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/geofence_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

class SiteSecurityPolicyDialog extends StatefulWidget {
  const SiteSecurityPolicyDialog({
    super.key,
    required this.site,
    required this.isSuperUser,
    required this.onSave,
  });

  final SiteRecord site;
  final bool isSuperUser;
  final Future<void> Function({
    required bool featureRemoteOpenEnabled,
    required bool featureQrEnabled,
    required bool featureGuestPassEnabled,
    required bool qrEntryActive,
    required bool requireGeofence,
    required double? geofenceLatitude,
    required double? geofenceLongitude,
    required int geofenceRadiusMeters,
    required int qrRotationSeconds,
  }) onSave;

  static Future<bool?> show(
    BuildContext context, {
    required SiteRecord site,
    required AuthService authService,
  }) {
    final isSuper = authService.session?.role.name == 'superUser' ||
        authService.session?.role.name == 'super_user';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => SiteSecurityPolicyDialog(
        site: site,
        isSuperUser: isSuper,
        onSave: ({
          required bool featureRemoteOpenEnabled,
          required bool featureQrEnabled,
          required bool featureGuestPassEnabled,
          required bool qrEntryActive,
          required bool requireGeofence,
          required double? geofenceLatitude,
          required double? geofenceLongitude,
          required int geofenceRadiusMeters,
          required int qrRotationSeconds,
        }) async {
          final error = await authService.updateSiteSecurityPolicy(
            siteCode: site.id,
            featureRemoteOpenEnabled: isSuper ? featureRemoteOpenEnabled : null,
            featureQrEnabled: isSuper ? featureQrEnabled : null,
            featureGuestPassEnabled: isSuper ? featureGuestPassEnabled : null,
            qrEntryActive: qrEntryActive,
            requireGeofence: requireGeofence,
            geofenceLatitude: geofenceLatitude,
            geofenceLongitude: geofenceLongitude,
            geofenceRadiusMeters: geofenceRadiusMeters,
            qrRotationSeconds: isSuper ? qrRotationSeconds : null,
          );
          if (error != null) {
            throw Exception(error);
          }
        },
      ),
    );
  }

  @override
  State<SiteSecurityPolicyDialog> createState() => _SiteSecurityPolicyDialogState();
}

class _SiteSecurityPolicyDialogState extends State<SiteSecurityPolicyDialog> {
  late String _accessMode; // 'hybrid', 'app_only', 'qr_only'
  late bool _featureGuestPassEnabled;
  late bool _requireGeofence;
  late int _qrRotationSeconds;
  late TextEditingController _latController;
  late TextEditingController _lngController;
  late double _radiusMeters;
  bool _isLocating = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (!widget.site.featureRemoteOpenEnabled && widget.site.featureQrEnabled) {
      _accessMode = 'qr_only';
    } else if (widget.site.featureRemoteOpenEnabled && !widget.site.featureQrEnabled) {
      _accessMode = 'app_only';
    } else {
      _accessMode = 'hybrid';
    }

    _featureGuestPassEnabled = widget.site.featureGuestPassEnabled;
    _requireGeofence = widget.site.requireGeofence;
    _qrRotationSeconds = widget.site.qrRotationSeconds;
    _latController = TextEditingController(
      text: widget.site.geofenceLatitude != null
          ? widget.site.geofenceLatitude!.toStringAsFixed(6)
          : '',
    );
    _lngController = TextEditingController(
      text: widget.site.geofenceLongitude != null
          ? widget.site.geofenceLongitude!.toStringAsFixed(6)
          : '',
    );
    _radiusMeters = widget.site.geofenceRadiusMeters.toDouble();
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final position = await GeofenceService.instance.getCurrentPosition();
      if (position != null && mounted) {
        setState(() {
          _latController.text = position.latitude.toStringAsFixed(6);
          _lngController.text = position.longitude.toStringAsFixed(6);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mevcut GPS konumu basariyla alindi.'),
            backgroundColor: AppColors.emerald,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konum alinamadi. Lutfen GPS iznini kontrol edin.'),
            backgroundColor: AppColors.rose,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());

    final isQrActive = _accessMode != 'app_only';
    final isRemoteActive = _accessMode != 'qr_only';

    try {
      await widget.onSave(
        featureRemoteOpenEnabled: isRemoteActive,
        featureQrEnabled: isQrActive,
        featureGuestPassEnabled: _featureGuestPassEnabled,
        qrEntryActive: isQrActive,
        requireGeofence: _requireGeofence,
        geofenceLatitude: lat,
        geofenceLongitude: lng,
        geofenceRadiusMeters: _radiusMeters.toInt(),
        qrRotationSeconds: _qrRotationSeconds,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kaydedilemedi: $e'),
            backgroundColor: AppColors.rose,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final site = widget.site;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Başlık
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Giriş & Güvenlik Politikaları',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        Text(
                          site.name,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Kaydırılabilir İçerik
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // SÜPER KULLANICI GİRİŞ YÖNTEMİ SEÇİMİ
                      Row(
                        children: [
                          const Icon(Icons.lock_person_outlined, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Yetkili Giriş Yöntemi',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                          const Spacer(),
                          if (!widget.isSuperUser)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Sadece Süper User',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Site sakinlerinin kapıyı hangi yöntemlerle açabileceğini belirleyin.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildAccessModeCard(
                        mode: 'hybrid',
                        title: '🔄 Hibrit (Uygulama + QR Kod)',
                        subtitle: 'Sakinler hem uygulama butonundan hem de kapıdaki QR okuyucudan geçebilir.',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 8),
                      _buildAccessModeCard(
                        mode: 'app_only',
                        title: '📱 Sadece Mobil Uygulama Butonu',
                        subtitle: 'QR okuyucu devre dışıdır. Kapı yalnızca uygulama üzerinden internet/yerel ağ ile açılır.',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 8),
                      _buildAccessModeCard(
                        mode: 'qr_only',
                        title: '📷 Sadece QR Kod ile Giriş',
                        subtitle: 'Uygulamadan uzaktan butona basarak açma kapalıdır. Sakin yalnızca kapı önünde QR ile açabilir.',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 18),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // MİSAFİR GEÇİŞ İZNİ
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '📦 Misafir & Kurye Geçiş İzni',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          'Daire sakinlerinin tek kullanımlık veya süreli misafir linki üretmesine izin ver.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                          ),
                        ),
                        value: _featureGuestPassEnabled,
                        onChanged: widget.isSuperUser
                            ? (val) => setState(() => _featureGuestPassEnabled = val)
                            : null,
                      ),
                      const SizedBox(height: 8),

                      // DİNAMİK QR YENİLENME SÜRESİ (Eğer QR aktifse)
                      if (_accessMode != 'app_only') ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.timer_outlined, size: 18, color: AppColors.primary),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Dinamik QR Yenilenme Süresi',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                            DropdownButton<int>(
                              value: _qrRotationSeconds,
                              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(value: 15, child: Text('15 saniye')),
                                DropdownMenuItem(value: 30, child: Text('30 saniye (Önerilen)')),
                                DropdownMenuItem(value: 60, child: Text('60 saniye')),
                              ],
                              onChanged: widget.isSuperUser
                                  ? (val) {
                                      if (val != null) setState(() => _qrRotationSeconds = val);
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // GPS GEOFENCE TOGGLE
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '📍 Konum Doğrulama (GPS Geofence)',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          'QR kodun yalnızca site kapısına yakınken üretilmesini zorunlu kıl (ekran görüntüsü paylaşımını engeller).',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                          ),
                        ),
                        value: _requireGeofence,
                        onChanged: (val) => setState(() => _requireGeofence = val),
                      ),

                      if (_requireGeofence) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? const Color(0x22FFFFFF) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 18, color: AppColors.primary),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Kapı / Site GPS Koordinatları',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _isLocating ? null : _fetchCurrentLocation,
                                    icon: _isLocating
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.my_location, size: 15),
                                    label: const Text('Mevcut Konumu Al', style: TextStyle(fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _latController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Enlem (Latitude)',
                                        hintText: '41.0082',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _lngController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Boylam (Longitude)',
                                        hintText: '28.9784',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'İzin Verilen Azami Mesafe:',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    '${_radiusMeters.round()} metre',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: _radiusMeters,
                                min: 25,
                                max: 300,
                                divisions: 11,
                                label: '${_radiusMeters.round()} m',
                                onChanged: (val) => setState(() => _radiusMeters = val),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // Butonlar
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    child: const Text('İptal'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Değişiklikleri Kaydet'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccessModeCard({
    required String mode,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    final isSelected = _accessMode == mode;
    final isEnabled = widget.isSuperUser;

    return InkWell(
      onTap: isEnabled ? () => setState(() => _accessMode = mode) : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.08)
              : (isDark ? const Color(0xFF0F172A).withValues(alpha: 0.4) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (isDark ? const Color(0x22FFFFFF) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20,
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: isSelected
                          ? (isDark ? const Color(0xFF93C5FD) : AppColors.primary)
                          : (isDark ? Colors.white : AppColors.textDark),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
