// Dekont önizlemesi (Dalga 2 / 2B): görüntü olduğu gibi (yakınlaştırılabilir), PDF'in ilk sayfası görüntüye çevrilerek. Bayt yüklemesi çağırandan gelir
// (yetkili uç); hata ya da PDF çizilemezse dürüst açıklama gösterilir ("görünmüyor" demek onaylamak için yeterli değildir).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';

class ReceiptFilePreview extends StatefulWidget {
  const ReceiptFilePreview({super.key, required this.load, required this.isPdf, this.height = 360});

  /// Dosya baytlarını getirir (yetkili uç).
  final Future<Uint8List> Function() load;
  final bool isPdf;
  final double height;

  @override
  State<ReceiptFilePreview> createState() => _ReceiptFilePreviewState();
}

class _ReceiptFilePreviewState extends State<ReceiptFilePreview> {
  Uint8List? _image;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.load();
      Uint8List? shown = bytes;
      if (widget.isPdf) {
        shown = null;
        await for (final page in Printing.raster(bytes, pages: const <int>[0], dpi: 110)) {
          shown = await page.toPng();
          break;
        }
        if (shown == null) throw StateError('pdf');
      }
      if (!mounted) return;
      setState(() {
        _image = shown;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = widget.isPdf && e is! ApiException
            ? 'PDF önizlenemedi. Dekontu sakinden ekran görüntüsüyle yeniden isteyebilirsiniz.'
            : financeMessageOf(e, 'Dekont yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final Widget child;
    if (_loading) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      child = Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, key: const ValueKey<String>('receipt_preview_error'), textAlign: TextAlign.center, style: th.bodyMedium),
            const SizedBox(height: AppSpace.sm),
            TextButton(onPressed: _load, child: const Text('Tekrar dene')),
          ],
        ),
      );
    } else {
      child = InteractiveViewer(
        maxScale: 5,
        child: Image.memory(_image!, fit: BoxFit.contain, semanticLabel: 'Dekont görüntüsü', errorBuilder: (_, _, _) => const Center(child: Text('Görüntü çizilemedi.'))),
      );
    }
    return Container(
      key: const ValueKey<String>('receipt_preview'),
      height: widget.height,
      decoration: BoxDecoration(color: p.surfaceMuted, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(AppRadius.md)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
