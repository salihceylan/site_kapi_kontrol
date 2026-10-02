import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/site_join_token_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

class SiteJoinQrDialog extends StatefulWidget {
  const SiteJoinQrDialog({
    super.key,
    required this.site,
    required this.authService,
  });

  final SiteRecord site;
  final AuthService authService;

  static Future<void> show(
    BuildContext context, {
    required SiteRecord site,
    required AuthService authService,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SiteJoinQrDialog(
        site: site,
        authService: authService,
      ),
    );
  }

  @override
  State<SiteJoinQrDialog> createState() => _SiteJoinQrDialogState();
}

class _SiteJoinQrDialogState extends State<SiteJoinQrDialog> {
  SiteJoinTokenRecord? _tokenRecord;
  bool _isLoading = true;
  bool _isRotating = false;
  bool _isSharing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await widget.authService.getSiteJoinToken(
        siteCode: widget.site.id,
      );
      if (!mounted) return;
      setState(() {
        _tokenRecord = token;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiException ? e.message : e.toString();
      });
    }
  }

  Future<void> _rotateToken() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'QR Kodunu Yenile?',
        icon: Icons.warning_amber_rounded,
        tone: AppTone.warning,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTone.warning.a,
              foregroundColor: Colors.white,
            ),
            child: const Text('Evet, Yenile'),
          ),
        ],
        child: const Text(
          'Mevcut katılım QR kodu iptal edilecek ve yeni bir kod üretilecektir. '
          'Daha önce asılmış veya paylaşılmış eski QR kodlar artık katılım için kullanılamaz. Devam etmek istiyor musunuz?',
        ),
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isRotating = true;
      _errorMessage = null;
    });

    try {
      final token = await widget.authService.rotateSiteJoinToken(
        siteCode: widget.site.id,
      );
      if (!mounted) return;
      setState(() {
        _tokenRecord = token;
        _isRotating = false;
      });

      AppSnack.show(
        context,
        'Site katılım QR kodu başarıyla yenilendi.',
        kind: AppSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRotating = false;
        _errorMessage = e is ApiException ? e.message : e.toString();
      });
    }
  }

  void _copyToClipboard() {
    if (_tokenRecord == null) return;
    final textToCopy =
        '${widget.site.name} Site Katılım Bilgisi:\n'
        'Katılım Kodu: ${_tokenRecord!.qrPayload}\n\n'
        'Site sakinleri AHBU Site Kapı Kontrol uygulamasından "Siteye Katıl" seçeneğiyle '
        'bu kodu tarayabilir veya doğrudan girebilir.';

    Clipboard.setData(ClipboardData(text: textToCopy));
    AppSnack.show(context, 'Katılım bilgisi panoya kopyalandı.');
  }

  Future<void> _shareQrCode() async {
    if (_tokenRecord == null) return;

    setState(() => _isSharing = true);

    final shareText =
        '🏢 ${widget.site.name} - Site Katılım Bilgisi\n\n'
        'Değerli Sakinimiz,\n'
        'Sitemize ve dairenize katılım başvurusu yapmak için aşağıdaki katılım kodunu kullanabilir '
        'veya ekteki QR kodu AHBU Kapı Kontrol uygulamasından okutabilirsiniz.\n\n'
        '🔑 Katılım Kodu: ${_tokenRecord!.qrPayload}\n\n'
        'Nasıl Katılabilirsiniz?\n'
        '1. AHBU Kapı Kontrol uygulamasını açın.\n'
        '2. "Siteye Katıl" seçeneğine dokunun.\n'
        '3. Bu QR kodu tarayın veya katılım kodunu girin.\n'
        '4. Blok ve dairenizi seçerek başvurunuzu gönderin.';

    try {
      const double imageSize = 800.0;
      const double padding = 60.0;
      const double qrSize = imageSize - (padding * 2);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // WhatsApp koyu mod ve önizlemede siyah zemin oluşmaması için %100 opak bembeyaz tuval
      final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, imageSize, imageSize),
        bgPaint,
      );

      final painter = QrPainter(
        data: _tokenRecord!.qrPayload,
        version: QrVersions.auto,
        gapless: true,
        // ignore: deprecated_member_use
        emptyColor: const Color(0xFFFFFFFF),
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF0F172A),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF0F172A),
        ),
      );

      // QR kodu beyaz güvenlik çerçevesi (quiet zone) ile tam ortaya çiz
      canvas.save();
      canvas.translate(padding, padding);
      painter.paint(canvas, const Size(qrSize, qrSize));
      canvas.restore();

      final picture = recorder.endRecording();
      final image = await picture.toImage(imageSize.toInt(), imageSize.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final bytes = byteData.buffer.asUint8List();
        final safeSiteName = widget.site.name.replaceAll(RegExp(r'\s+'), '_');
        await SharePlus.instance.share(
          ShareParams(
            text: shareText,
            subject: '${widget.site.name} Site Katılım QR Kodu',
            files: [
              XFile.fromData(
                bytes,
                mimeType: 'image/png',
                name: '${safeSiteName}_katilim_qr.png',
              ),
            ],
          ),
        );
        if (mounted) setState(() => _isSharing = false);
        return;
      }
    } catch (e) {
      debugPrint('QR resim export hatası: $e');
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: shareText,
          subject: '${widget.site.name} Site Katılım QR Kodu',
        ),
      );
    } catch (e) {
      if (mounted) {
        AppSnack.show(
          context,
          'Paylaşım başlatılamadı: $e',
          kind: AppSnackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final cityDistrict =
        '${widget.site.city ?? ''} / ${widget.site.district ?? ''}'.replaceAll(RegExp(r'^ / | / $'), '');

    return AlertDialog(
      scrollable: true,
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
      // Başlık şeridi + sağ üstte kapatma düğmesi (başlık metni düğmenin altına girmesin diye sağdan pay).
      title: Stack(
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.only(end: 32),
            child: AppDialogHeader(
              title: 'Site Katılım QR Kodu',
              icon: Icons.qr_code_2_rounded,
            ),
          ),
          PositionedDirectional(
            top: AppSpace.sm,
            end: AppSpace.sm,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Kapat',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidthForScreen(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Site Başlık Kartı
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: p.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.apartment_rounded,
                          size: 16,
                          color: AppTone.primary.ink(p),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.site.name,
                          style: th.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if ((widget.site.city ?? '').isNotEmpty || (widget.site.district ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      cityDistrict,
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Bilgilendirme Rozeti
            const InlineNotice(
              tone: AppTone.info,
              message:
                  'Bu QR kod kapıyı açmaz. Sakinlerin telefonlarıyla okutup siteye ve dairelerine katılım başvurusu yapması içindir.',
            ),
            const SizedBox(height: 16),

            // Yükleniyor veya QR Gösterimi
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: InlineNotice(
                  message: _errorMessage!,
                  onRetry: _loadToken,
                ),
              )
            else if (_tokenRecord != null) ...[
              // QR Kod Kartı (QR okunabilirliği için her temada beyaz zemin üstünde koyu modüller)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: p.shadow(2),
                  ),
                  // Sabit boyutlu sarmalayıcı: QrImageView LayoutBuilder kullanır; AlertDialog (kaydırılabilir)
                  // içerik yüksekliğini içsel olarak ölçer ve LayoutBuilder buna izin vermez.
                  child: SizedBox(
                    width: 190,
                    height: 190,
                    child: QrImageView(
                      data: _tokenRecord!.qrPayload,
                      version: QrVersions.auto,
                      size: 190,
                      gapless: true,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF0F172A),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Token Metni (Tıklayınca Kopyalar)
              InkWell(
                onTap: _copyToClipboard,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 14, color: AppTone.primary.ink(p)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _tokenRecord!.token,
                            style: th.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppTone.primary.ink(p),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Karekodu Paylaş Butonu (WhatsApp / Diğer platformlar)
              ElevatedButton.icon(
                onPressed: (_isLoading || _tokenRecord == null || _isSharing) ? null : _shareQrCode,
                icon: _isSharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.share_rounded, size: 18),
                label: Text(
                  _isSharing ? 'Hazırlanıyor...' : 'Karekodu Paylaş',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTone.success.a,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 10),

              // Aksiyon Butonları (Kopyala & Yenile): sığmazsa alt alta dizilir.
              OverflowBar(
                alignment: MainAxisAlignment.center,
                spacing: 8,
                overflowSpacing: 8,
                overflowAlignment: OverflowBarAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _copyToClipboard,
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Kodu Kopyala'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isRotating ? null : _rotateToken,
                    icon: _isRotating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_rounded, size: 15),
                    label: Text(_isRotating ? '...' : 'QR Yenile'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTone.warning.a,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
