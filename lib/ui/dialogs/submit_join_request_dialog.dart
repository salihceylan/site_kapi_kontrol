import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/site_join_info.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/pages/qr_scan_page.dart';

class SubmitJoinRequestDialog extends StatefulWidget {
  const SubmitJoinRequestDialog({
    super.key,
    required this.authService,
    this.initialToken,
  });

  final AuthService authService;
  final String? initialToken;

  static Future<bool?> show(
    BuildContext context, {
    required AuthService authService,
    String? initialToken,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SubmitJoinRequestDialog(
        authService: authService,
        initialToken: initialToken,
      ),
    );
  }

  @override
  State<SubmitJoinRequestDialog> createState() => _SubmitJoinRequestDialogState();
}

class _SubmitJoinRequestDialogState extends State<SubmitJoinRequestDialog> {
  final _tokenController = TextEditingController();
  final _notesController = TextEditingController();

  bool _isLoadingInfo = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  SiteJoinInfo? _siteInfo;
  SiteJoinBlockInfo? _selectedBlock;
  SiteJoinApartmentInfo? _selectedApartment;

  @override
  void initState() {
    super.initState();
    if (widget.initialToken != null && widget.initialToken!.trim().isNotEmpty) {
      _tokenController.text = widget.initialToken!.trim();
      _fetchInfo(widget.initialToken!.trim());
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (!mounted || scanned == null || scanned.trim().isEmpty) return;

    final clean = scanned.replaceAll(RegExp(r'^SITE_JOIN:', caseSensitive: false), '').trim();
    _tokenController.text = clean;
    _fetchInfo(clean);
  }

  Future<void> _fetchInfo(String token) async {
    final clean = token.replaceAll(RegExp(r'^SITE_JOIN:', caseSensitive: false), '').trim();
    if (clean.isEmpty) return;

    setState(() {
      _isLoadingInfo = true;
      _errorMessage = null;
      _siteInfo = null;
      _selectedBlock = null;
      _selectedApartment = null;
    });

    final (info, error) = await widget.authService.fetchSiteJoinInfo(clean);
    if (!mounted) return;

    setState(() {
      _isLoadingInfo = false;
      if (error != null) {
        _errorMessage = error;
      } else {
        _siteInfo = info;
        if (info != null && info.blocks.isNotEmpty) {
          _selectedBlock = info.blocks.first;
          // İlk bloğun ilk dairesini seç
          final blockApts = info.apartments.where((a) => a.blockId == _selectedBlock!.id).toList();
          if (blockApts.isNotEmpty) {
            _selectedApartment = blockApts.first;
          }
        }
      }
    });
  }

  Future<void> _submit() async {
    if (_siteInfo == null || _selectedApartment == null) {
      setState(() => _errorMessage = 'Lütfen blok ve daire seçiniz.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final (res, error) = await widget.authService.submitJoinRequest(
      joinToken: _siteInfo!.token,
      blockId: _selectedBlock?.id,
      apartmentId: _selectedApartment!.id,
      notes: _notesController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (error != null) {
      setState(() => _errorMessage = error);
    } else {
      final msg = res?['message'] as String? ?? 'Katılım başvurunuz site yöneticisine iletildi.';
      HapticFeedback.lightImpact();
      AppSnack.show(context, msg, kind: AppSnackKind.success);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final availableApts = _selectedBlock != null && _siteInfo != null
        ? _siteInfo!.apartments.where((a) => a.blockId == _selectedBlock!.id).toList()
        : (_siteInfo?.apartments ?? const []);
    final site = _siteInfo;
    // Şehir / ilçe metni (boş taraf atılır); yoksa konum rozeti çizilmez.
    final location = site == null
        ? ''
        : ((site.city ?? '').isNotEmpty || (site.district ?? '').isNotEmpty)
            ? '${site.city ?? ''} / ${site.district ?? ''}'.replaceAll(RegExp(r'^ / | / $'), '')
            : '';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başlık (+ sağ üstte kapatma; başlık düğmenin altına girmesin diye sağdan pay)
              Stack(
                children: [
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 32),
                    child: AppDialogHeader(
                      title: 'Siteye Katıl',
                      subtitle: 'QR kod okutarak dairenizi seçin ve başvurun',
                      icon: Icons.person_add_alt_1_rounded,
                    ),
                  ),
                  PositionedDirectional(
                    top: AppSpace.sm,
                    end: AppSpace.sm,
                    child: IconButton(
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close_rounded),
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // QR Tarama / Token Girişi
                    if (_siteInfo == null) ...[
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // Büyük yazı / dar kutuda alan ve "Tara" düğmesi alt alta dizilir.
                          final stacked =
                              MediaQuery.textScalerOf(context).scale(1) > 1.2 ||
                              constraints.maxWidth < 300;
                          final tokenField = TextField(
                            controller: _tokenController,
                            // "Site Bilgilerini Getir" düğmesi metin dolunca görünsün (yeniden çizim şart).
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Katılım Kodu veya QR',
                              hintText: 'SJT-XXXXXX...',
                              prefixIcon: Icon(Icons.qr_code_2_rounded, size: 20),
                              isDense: true,
                            ),
                            onSubmitted: (val) => _fetchInfo(val),
                          );
                          final scanButton = ElevatedButton.icon(
                            onPressed: _isLoadingInfo ? null : _scanQr,
                            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                            label: const Text('Tara'),
                          );
                          if (stacked) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                tokenField,
                                const SizedBox(height: AppSpace.sm),
                                scanButton,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: tokenField),
                              const SizedBox(width: AppSpace.sm),
                              scanButton,
                            ],
                          );
                        },
                      ),
                      if (_tokenController.text.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpace.sm),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isLoadingInfo ? null : () => _fetchInfo(_tokenController.text.trim()),
                            icon: const Icon(Icons.search_rounded, size: 18),
                            label: const Text('Site Bilgilerini Getir'),
                          ),
                        ),
                      ],
                    ],

                    // Yükleniyor Durumu: gelecek site kartı + iki seçici iskeleti
                    if (_isLoadingInfo) ...[
                      const SizedBox(height: AppSpace.xl),
                      const ShimmerScope(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SkeletonBox(height: 68, radius: AppRadius.lg),
                            SizedBox(height: AppSpace.lg),
                            SkeletonBox(height: 48, radius: AppRadius.md),
                            SizedBox(height: AppSpace.md),
                            SkeletonBox(height: 48, radius: AppRadius.md),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      Center(
                        child: Text(
                          'Site bilgileri yükleniyor...',
                          textAlign: TextAlign.center,
                          style: th.bodySmall?.copyWith(color: p.textSecondary),
                        ),
                      ),
                    ],

                    // Hata Mesajı
                    if (_errorMessage != null) ...[
                      const SizedBox(height: AppSpace.md),
                      InlineNotice(message: _errorMessage!),
                    ],

                    // Site Bilgisi ve Blok/Daire Seçimi
                    if (site != null) ...[
                      const SizedBox(height: AppSpace.md),
                      StaggeredEntry(
                        index: 0,
                        child: AppCard(
                          padding: const EdgeInsets.all(AppSpace.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                runSpacing: AppSpace.xs,
                                children: [
                                  DialogInfoRow(
                                    icon: Icons.apartment_rounded,
                                    title: site.siteName,
                                    titleMaxLines: null,
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _siteInfo = null;
                                        _tokenController.clear();
                                      });
                                    },
                                    child: const Text('Değiştir'),
                                  ),
                                ],
                              ),
                              if (location.isNotEmpty)
                                Padding(
                                  // Rozet, başlık metninin hizasında (40 dp rozet + 12 dp boşluk).
                                  padding: EdgeInsets.only(
                                    left: dialogLargeText(context) ? 0 : 52,
                                  ),
                                  child: StatusChip(
                                    label: location,
                                    tone: AppTone.info,
                                    icon: Icons.location_on_rounded,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),

                      // Blok Seçimi
                      if (site.blocks.isNotEmpty) ...[
                        Text(
                          'Blok Seçiniz',
                          style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: p.text),
                        ),
                        const SizedBox(height: AppSpace.sm),
                        DropdownButtonFormField<SiteJoinBlockInfo>(
                          isExpanded: true,
                          // ignore: deprecated_member_use
                          value: _selectedBlock,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            prefixIcon: Icon(Icons.apartment_rounded),
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          dropdownColor: p.surface,
                          menuMaxHeight: 320,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          style: th.bodyLarge,
                          items: site.blocks.map((b) {
                            return DropdownMenuItem(
                              value: b,
                              child: Text(b.blockName, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (b) {
                            setState(() {
                              _selectedBlock = b;
                              final apts = _siteInfo!.apartments.where((a) => a.blockId == b?.id).toList();
                              _selectedApartment = apts.isNotEmpty ? apts.first : null;
                            });
                          },
                        ),
                        const SizedBox(height: AppSpace.lg),
                      ],

                      // Daire Seçimi
                      Text(
                        'Daire Seçiniz',
                        style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: p.text),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      DropdownButtonFormField<SiteJoinApartmentInfo>(
                        isExpanded: true,
                        // ignore: deprecated_member_use
                        value: _selectedApartment,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          prefixIcon: Icon(Icons.home_rounded),
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        dropdownColor: p.surface,
                        menuMaxHeight: 320,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        style: th.bodyLarge,
                        items: availableApts.map((a) {
                          return DropdownMenuItem(
                            value: a,
                            child: Text(a.unitLabel, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (a) => setState(() => _selectedApartment = a),
                      ),
                      const SizedBox(height: AppSpace.lg),

                      // Not (İsteğe Bağlı)
                      TextField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Yöneticiye Not (İsteğe bağlı)',
                          hintText: 'Örn: Ev sahibiyim / Kiracıyım...',
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: AppSpace.xl),

                      // Gönder Butonu
                      ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _submit,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(_isSubmitting ? 'Başvuru Gönderiliyor...' : 'Katılım Başvurusunu Gönder'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
