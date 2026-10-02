import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/geofence_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

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

/// Konum çemberi (geofence) alanlarının doğrulama sonucu.
class GeofenceFormValidation {
  const GeofenceFormValidation({
    this.latitude,
    this.longitude,
    this.latitudeError,
    this.longitudeError,
    this.radiusError,
  });

  final double? latitude;
  final double? longitude;
  final String? latitudeError;
  final String? longitudeError;
  final String? radiusError;

  bool get isValid =>
      latitudeError == null && longitudeError == null && radiusError == null;
}

/// Konum doğrulaması (geofence) açıkken geçerli enlem/boylam/yarıçap zorunludur.
/// Ondalık ayırıcı olarak virgül de kabul edilir (Türkçe klavye).
GeofenceFormValidation validateGeofenceForm({
  required String latitudeText,
  required String longitudeText,
  required double radiusMeters,
}) {
  double? parse(String raw) {
    final text = raw.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) return null;
    return value;
  }

  final lat = parse(latitudeText);
  final lng = parse(longitudeText);

  String? latError;
  String? lngError;
  String? radiusError;

  if (lat == null) {
    latError = 'Geçerli bir enlem girin.';
  } else if (lat < -90 || lat > 90) {
    latError = 'Enlem -90 ile 90 arasında olmalı.';
  }

  if (lng == null) {
    lngError = 'Geçerli bir boylam girin.';
  } else if (lng < -180 || lng > 180) {
    lngError = 'Boylam -180 ile 180 arasında olmalı.';
  }

  // (0, 0) noktası "tanımsız" kabul edilir: gerçek bir site konumu olamaz.
  if (latError == null && lngError == null && lat == 0 && lng == 0) {
    latError = 'Koordinatlar tanımsız görünüyor.';
    lngError = 'Koordinatlar tanımsız görünüyor.';
  }

  if (radiusMeters.isNaN || radiusMeters < 10 || radiusMeters > 2000) {
    radiusError = 'Mesafe 10 ile 2000 metre arasında olmalı.';
  }

  return GeofenceFormValidation(
    latitude: latError == null ? lat : null,
    longitude: lngError == null ? lng : null,
    latitudeError: latError,
    longitudeError: lngError,
    radiusError: radiusError,
  );
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
  String? _latError;
  String? _lngError;
  String? _radiusError;

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
    // Kayıtlı yarıçap olduğu gibi tutulur (sunucu 10-2000 m kabul eder): kaydırıcıya yalnız
    // GÖSTERİMDE sığdırılır; kullanıcı kaydırıcıyı oynatmadıkça kayıtlı değer sessizce değişmez.
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
      // Merkez konumu da istemci doğrulama kurallarına tabidir: doğruluk, tazelik, sahte konum.
      final fix = await GeofenceService.instance.acquireVerifiedPosition();
      final position = fix.position;
      if (position != null && mounted) {
        setState(() {
          _latController.text = position.latitude.toStringAsFixed(6);
          _lngController.text = position.longitude.toStringAsFixed(6);
          _latError = null;
          _lngError = null;
        });
        AppSnack.show(
          context,
          'Mevcut GPS konumu başarıyla alındı.',
          kind: AppSnackKind.success,
        );
      } else if (mounted) {
        AppSnack.show(
          context,
          fix.errorMessage ?? 'Konum alınamadı. Lütfen GPS iznini kontrol edin.',
          kind: AppSnackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _handleSave() async {
    double? lat = double.tryParse(_latController.text.trim().replaceAll(',', '.'));
    double? lng = double.tryParse(_lngController.text.trim().replaceAll(',', '.'));

    if (_requireGeofence) {
      // Konum doğrulaması açıkken boş/hatalı koordinatla kaydetmeyi engelle.
      final validation = validateGeofenceForm(
        latitudeText: _latController.text,
        longitudeText: _lngController.text,
        radiusMeters: _radiusMeters,
      );
      setState(() {
        _latError = validation.latitudeError;
        _lngError = validation.longitudeError;
        _radiusError = validation.radiusError;
      });
      if (!validation.isValid) {
        AppSnack.show(
          context,
          'Konum doğrulaması açıkken geçerli enlem, boylam ve mesafe girilmelidir.',
          kind: AppSnackKind.error,
        );
        return;
      }
      lat = validation.latitude;
      lng = validation.longitude;
    }

    setState(() => _isSaving = true);

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
        AppSnack.show(
          context,
          'Kaydedilemedi: ${e.toString().replaceFirst('Exception: ', '')}',
          kind: AppSnackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final site = widget.site;
    // Dar ekranlarda (ör. 320 px) kenar boşlukları küçültülür; içerik taşmaz.
    final isNarrow = MediaQuery.sizeOf(context).width < 400;
    final hintStyle = th.bodySmall?.copyWith(color: p.textSecondary);
    final accent = AppTone.primary.ink(p);
    // Büyük yazıda sabit başlık küçülür: alt başlık (site adı) kaydırılan içeriğin başına taşınır ve
    // eylem düğmeleri sabit satır yerine kaydırılan içeriğin SONUNA alınır (içerik için yer kalsın).
    final compactHeader = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final actionButtons = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _handleSave,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Değişiklikleri Kaydet'),
        ),
      ],
    );

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Başlık (+ sağ üstte kapatma; başlık düğmenin altına girmesin diye sağdan pay)
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 32),
                  child: AppDialogHeader(
                    title: 'Giriş & Güvenlik Politikaları',
                    subtitle: compactHeader ? null : site.name,
                    icon: Icons.admin_panel_settings_rounded,
                  ),
                ),
                PositionedDirectional(
                  top: AppSpace.sm,
                  end: AppSpace.sm,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),

            // Kaydırılabilir İçerik
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.md, AppSpace.xl, AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (compactHeader) ...[
                      Text(site.name, style: hintStyle),
                      const SizedBox(height: 12),
                    ],
                    // SÜPER KULLANICI GİRİŞ YÖNTEMİ SEÇİMİ
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_person_outlined, size: 18, color: accent),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Yetkili Giriş Yöntemi',
                                style: th.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        if (!widget.isSuperUser)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTone.neutral.tint(p),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Sadece Süper User',
                              style: th.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppTone.neutral.ink(p),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Site sakinlerinin kapıyı hangi yöntemlerle açabileceğini belirleyin.',
                      style: hintStyle,
                    ),
                    const SizedBox(height: 12),

                    _buildAccessModeCard(
                      mode: 'hybrid',
                      title: '🔄 Hibrit (Uygulama + QR Kod)',
                      subtitle: 'Sakinler hem uygulama butonundan hem de kapıdaki QR okuyucudan geçebilir.',
                    ),
                    const SizedBox(height: 8),
                    _buildAccessModeCard(
                      mode: 'app_only',
                      title: '📱 Sadece Mobil Uygulama Butonu',
                      subtitle: 'QR okuyucu devre dışıdır. Kapı yalnızca uygulama üzerinden internet/yerel ağ ile açılır.',
                    ),
                    const SizedBox(height: 8),
                    _buildAccessModeCard(
                      mode: 'qr_only',
                      title: '📷 Sadece QR Kod ile Giriş',
                      subtitle: 'Uygulamadan uzaktan butona basarak açma kapalıdır. Sakin yalnızca kapı önünde QR ile açabilir.',
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // MİSAFİR GEÇİŞ İZNİ
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('📦 Misafir & Kurye Geçiş İzni'),
                      subtitle: Text(
                        'Daire sakinlerinin tek kullanımlık veya süreli misafir linki üretmesine izin ver.',
                        style: hintStyle,
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
                          Icon(Icons.timer_outlined, size: 18, color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Dinamik QR Yenilenme Süresi',
                              style: th.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: p.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Seçici ayrı satırda ve tam genişlikte: dar ekranda yatay taşma olmaz.
                      DropdownButton<int>(
                        isExpanded: true,
                        value: _qrRotationSeconds,
                        dropdownColor: p.surface,
                        underline: const SizedBox(),
                        // Kayıtlı süre standart seçeneklerin dışındaysa (API 10-300 sn kabul eder)
                        // kaybolmaz / seçiciyi çökertmez: ek seçenek olarak listelenir.
                        items: [
                          for (final seconds in ({15, 30, 60, _qrRotationSeconds}.toList()..sort()))
                            DropdownMenuItem(
                              value: seconds,
                              child: Text(
                                seconds == 30 ? '30 saniye (Önerilen)' : '$seconds saniye',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: widget.isSuperUser
                            ? (val) {
                                if (val != null) setState(() => _qrRotationSeconds = val);
                              }
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // GPS GEOFENCE TOGGLE
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('📍 Konum Doğrulama (GPS Geofence)'),
                      subtitle: Text(
                        'QR kodun yalnızca site kapısına yakınken üretilmesini zorunlu kıl (ekran görüntüsü paylaşımını engeller).',
                        style: hintStyle,
                      ),
                      value: _requireGeofence,
                      onChanged: (val) => setState(() => _requireGeofence = val),
                    ),

                    if (_requireGeofence) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: p.surfaceMuted,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: p.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined, size: 18, color: accent),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Kapı / Site GPS Koordinatları',
                                    style: th.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: p.text,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: _isLocating ? null : _fetchCurrentLocation,
                                icon: _isLocating
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.my_location, size: 15),
                                label: const Text('Mevcut Konumu Al'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                // Büyük yazı / dar kutuda enlem ve boylam alt alta dizilir (hata iletileri okunur).
                                final stacked =
                                    MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                                    constraints.maxWidth < 260;
                                final latField = TextField(
                                  controller: _latController,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                                  onChanged: (_) {
                                    if (_latError != null) setState(() => _latError = null);
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Enlem (Latitude)',
                                    hintText: '41.0082',
                                    isDense: true,
                                    errorText: _latError,
                                    errorMaxLines: 3,
                                  ),
                                );
                                final lngField = TextField(
                                  controller: _lngController,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                                  onChanged: (_) {
                                    if (_lngError != null) setState(() => _lngError = null);
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Boylam (Longitude)',
                                    hintText: '28.9784',
                                    isDense: true,
                                    errorText: _lngError,
                                    errorMaxLines: 3,
                                  ),
                                );
                                if (stacked) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      latField,
                                      const SizedBox(height: 12),
                                      lngField,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: latField),
                                    const SizedBox(width: 12),
                                    Expanded(child: lngField),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  'İzin Verilen Azami Mesafe:',
                                  style: th.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: p.textSecondary,
                                  ),
                                ),
                                Text(
                                  '${_radiusMeters.round()} metre',
                                  maxLines: 1,
                                  style: th.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: accent,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              // Kaydırıcı aralığı dışındaki değerler (örn. API'den gelen 500 m) çökmesin.
                              value: _radiusMeters.clamp(25.0, 300.0).toDouble(),
                              min: 25,
                              max: 300,
                              divisions: 11,
                              label: '${_radiusMeters.round()} m',
                              onChanged: (val) => setState(() {
                                _radiusMeters = val;
                                _radiusError = null;
                              }),
                            ),
                            if (_radiusError != null)
                              Text(
                                _radiusError!,
                                style: th.bodySmall?.copyWith(
                                  color: AppTone.danger.ink(p),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (compactHeader) ...[
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      actionButtons,
                    ],
                  ],
                ),
              ),
            ),

            // Butonlar (sabit satır; büyük yazıda kaydırılan içeriğin sonunda)
            if (!compactHeader) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.xl, 14, AppSpace.xl, AppSpace.lg),
                child: actionButtons,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAccessModeCard({
    required String mode,
    required String title,
    required String subtitle,
  }) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final isSelected = _accessMode == mode;
    final isEnabled = widget.isSuperUser;
    final accent = AppTone.primary.ink(p);

    return AppCard(
      selected: isSelected,
      onTap: isEnabled ? () => setState(() => _accessMode = mode) : null,
      padding: const EdgeInsets.all(12),
      // Devre dışı (süper kullanıcı değil): içerik soluk gösterilir.
      child: Opacity(
        opacity: isEnabled ? 1 : 0.6,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20,
                color: isSelected ? accent : p.textMuted,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: th.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isSelected ? accent : p.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
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
