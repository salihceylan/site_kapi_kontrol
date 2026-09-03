import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage({
    super.key,
    this.accentColor,
    this.title = 'QR Kod Oku',
    this.instructionText = 'Cihazın QR kodunu kameraya gösterin.',
    this.preserveCase = false,
  });

  final Color? accentColor;
  final String title;
  final String instructionText;
  final bool preserveCase;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _handled = false;

  bool get _isSupportedPlatform {
    if (kIsWeb) {
      return true;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_handled) {
      return;
    }

    final rawValue = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    if (rawValue.isEmpty) {
      return;
    }

    _handled = true;
    await _controller.stop();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(
      widget.preserveCase ? rawValue : rawValue.toUpperCase(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.accentColor ?? AppColors.primaryLight;
    if (!_isSupportedPlatform) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: accentColor,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Bu platformda kamera ile QR tarama desteklenmiyor. Şirket uygulamasını Android veya iPhone üzerinde kullanın.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: accentColor,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final scanBoxSize =
              (constraints.maxWidth * 0.65).clamp(180.0, 280.0);
          return Stack(
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _handleDetect,
              ),
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    widget.instructionText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: scanBoxSize,
                  height: scanBoxSize,
                  decoration: BoxDecoration(
                    border: Border.all(color: accentColor, width: 3),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
