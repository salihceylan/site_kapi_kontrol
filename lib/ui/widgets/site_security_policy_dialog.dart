import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/geofence_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

class SiteSecurityPolicyDialog extends StatefulWidget {
  const SiteSecurityPolicyDialog({
    super.key,
    required this.site,
    required this.onSave,
  });

  final SiteRecord site;
  final Future<void> Function({
    required bool qrEntryActive,
    required bool requireGeofence,
    required double? geofenceLatitude,
    required double? geofenceLongitude,
    required int geofenceRadiusMeters,
  }) onSave;

  static Future<bool?> show(
    BuildContext context, {
    required SiteRecord site,
    required AuthService authService,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => SiteSecurityPolicyDialog(
        site: site,
        onSave: ({
          required bool qrEntryActive,
          required bool requireGeofence,
          required double? geofenceLatitude,
          required double? geofenceLongitude,
          required int geofenceRadiusMeters,
        }) async {
          final error = await authService.updateSiteSecurityPolicy(
            siteCode: site.id,
            qrEntryActive: qrEntryActive,
            requireGeofence: requireGeofence,
            geofenceLatitude: geofenceLatitude,
            geofenceLongitude: geofenceLongitude,
            geofenceRadiusMeters: geofenceRadiusMeters,
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
  late bool _qrEntryActive;
  late bool _requireGeofence;
  late TextEditingController _latController;
  late TextEditingController _lngController;
  late double _radiusMeters;
  bool _isLocating = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _qrEntryActive = widget.site.qrEntryActive;
    _requireGeofence = widget.site.requireGeofence;
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

    try {
      await widget.onSave(
        qrEntryActive: _qrEntryActive,
        requireGeofence: _requireGeofence,
        geofenceLatitude: lat,
        geofenceLongitude: lng,
        geofenceRadiusMeters: _radiusMeters.toInt(),
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
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.security_outlined,
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
                          'Giris & Guvenlik Politikalari',
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
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // QR Feature Toggle (if super user enabled QR module for this site)
              if (site.featureQrEnabled) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'QR Kod ile Giris',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Sakinlerin mobil uygulama uzerinden kapiyi QR okutarak acmasina izin ver.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _qrEntryActive,
                  onChanged: (val) => setState(() => _qrEntryActive = val),
                ),
                const SizedBox(height: 12),
              ],

              // GPS Geofence Toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Konum Dogrulama (GPS Geofence)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'QR kodun yalnizca kapi cevresi fiziksel menzilindeyken uretilmesini zorunlu kil.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _requireGeofence,
                onChanged: (val) => setState(() => _requireGeofence = val),
              ),

              if (_requireGeofence) ...[
                const SizedBox(height: 12),
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
                              'Kapi / Site Konumu (GPS)',
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
                                hintText: '39.9207',
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
                                hintText: '32.8541',
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
                            'Gecerlilik Mesafesi (Yaricap):',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            ' metre',
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
                        label: 'm',
                        onChanged: (val) => setState(() => _radiusMeters = val),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Iptal'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Kaydet'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
