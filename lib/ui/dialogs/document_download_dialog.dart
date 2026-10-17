// Belge indirme ilerleme penceresi ve "indir -> paylaş / aç" akışı (docs/PLATFORM_BELGELER.md A13).
//
// Belge geçici dosyaya AKIŞLA indirilir (bellek şişmez), ardından işletim sisteminin paylaşım menüsüne
// ("ile aç" / kaydet / gönder) verilir; geçici kopya sonra silinir ([DocumentFileSharer]). Pencere:
// - ilerleme çubuğu + "Vazgeç" (iptal: bağlantı kapanır, kısmi dosya silinir),
// - hata: Türkçe ileti + "Tekrar Dene" (odak yeniden-deneme düğmesine gelir), asla sessiz kapanmaz,
// - geri tuşu = iptal (indirme arka planda sürüp dosya bırakmaz).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_download.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';

/// İndirmeyi başlatan çağrı: ilerleme bildirimi ve iptal belirteci alır.
typedef DocumentDownloadCall =
    Future<DownloadedDocument> Function(
      void Function(int received, int? total) onProgress,
      DocumentCancelToken cancel,
    );

/// İlerleme penceresini açar ve indirmeyi yürütür. Tamamlanırsa belgeyle, iptal / kapatma halinde null ile
/// döner (kısmi dosya zaten silinmiştir).
Future<DownloadedDocument?> showDocumentDownload(
  BuildContext context, {
  required String title,
  required DocumentDownloadCall download,
}) {
  return showDialog<DownloadedDocument>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DocumentDownloadDialog(title: title, download: download),
  );
}

/// Dokunulan öğenin ekran dikdörtgeni (iPad / masaüstü paylaşım yaprağının bağlanacağı yer); bulunamazsa null.
Rect? documentShareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.attached && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return null;
}

/// İndir -> paylaşım menüsü akışının tamamı. Hata ve iptal penceresinde ele alınır; paylaşım menüsü açılamazsa
/// kısa bir bildirim gösterilir ve geçici kopya silinir. [originContext] dokunulan düğmenin bağlamıdır.
Future<void> downloadAndShareDocument(
  BuildContext context, {
  required String title,
  required DocumentDownloadCall download,
  DocumentFileSharer? sharer,
  BuildContext? originContext,
}) async {
  // Konum, pencereler açılmadan ÖNCE alınır (sonra düğmenin bağlamı geçersiz olabilir).
  final origin = documentShareOrigin(originContext ?? context);
  final doc = await showDocumentDownload(
    context,
    title: title,
    download: download,
  );
  if (doc == null) return;
  final share = sharer ?? DocumentFileSharer();
  try {
    await share.share(doc, sharePositionOrigin: origin);
  } catch (_) {
    await share.scheduleDelete(doc);
    if (context.mounted) {
      AppSnack.show(
        context,
        'Paylaşım menüsü açılamadı. Tekrar deneyin.',
        kind: AppSnackKind.error,
      );
    }
  }
}

class DocumentDownloadDialog extends StatefulWidget {
  const DocumentDownloadDialog({
    super.key,
    required this.title,
    required this.download,
  });

  /// Belge başlığı (pencere alt başlığı).
  final String title;
  final DocumentDownloadCall download;

  @override
  State<DocumentDownloadDialog> createState() => _DocumentDownloadDialogState();
}

class _DocumentDownloadDialogState extends State<DocumentDownloadDialog> {
  DocumentCancelToken _cancel = DocumentCancelToken();
  int _received = 0;
  int? _total;
  String? _error;
  bool _running = false;
  bool _closing = false;
  int _run = 0;
  int _lastPercent = -1;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _closing = true;
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_running) return;
    final run = ++_run;
    _cancel = DocumentCancelToken();
    setState(() {
      _running = true;
      _error = null;
      _received = 0;
      _total = null;
      _lastPercent = -1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) announcePolite(context, 'Belge indiriliyor');
    });
    try {
      final doc = await widget.download((received, total) {
        if (!mounted || run != _run) return;
        final percent = total == null || total <= 0
            ? -1
            : received * 100 ~/ total;
        // Her parçada değil, yüzde değişince çizilir (setState seli olmasın).
        if (percent == _lastPercent && total != null) return;
        _lastPercent = percent;
        setState(() {
          _received = received;
          _total = total;
        });
      }, _cancel);
      if (!mounted || _closing || run != _run) {
        // Pencere bu arada kapandı: indirilen kopya sahipsiz kalmasın.
        await TempFileDocumentSink.deleteDirectory(doc.directoryPath);
        return;
      }
      _closing = true;
      popIfCurrent<DownloadedDocument>(context, doc);
    } on DocumentTransferCancelled {
      if (!mounted || run != _run) return;
      _closing = true;
      popIfCurrent<DownloadedDocument>(context);
    } catch (e) {
      if (!mounted || run != _run) return;
      setState(() {
        _running = false;
        _error = e is ApiException
            ? e.message
            : 'Belge indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      });
      return;
    }
  }

  void _cancelAndClose() {
    if (_closing) return;
    _cancel.cancel();
    if (_error != null || !_running) {
      _closing = true;
      popIfCurrent<DownloadedDocument>(context);
    }
    // Çalışırken: indirme DocumentTransferCancelled ile biter ve pencere _start içinde kapanır.
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final failed = _error != null;
    final total = _total;
    final fraction = total == null || total <= 0
        ? null
        : (_received / total).clamp(0.0, 1.0);
    final percentLabel = fraction == null
        ? null
        : '%${(fraction * 100).round()}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelAndClose();
      },
      child: AppDialog(
        title: failed ? 'Belge indirilemedi' : 'Belge indiriliyor',
        subtitle: widget.title.trim().isEmpty ? null : widget.title.trim(),
        icon: failed ? Icons.error_outline_rounded : Icons.download_rounded,
        tone: failed ? AppTone.danger : AppTone.primary,
        actions: [
          TextButton(
            key: const ValueKey<String>('document_download_cancel'),
            onPressed: _cancelAndClose,
            child: Text(failed ? 'Kapat' : 'Vazgeç'),
          ),
          if (failed)
            ElevatedButton(
              key: const ValueKey<String>('document_download_retry'),
              // Hata çıkınca odak yeniden-deneme düğmesine gelir (klavye / ekran okuyucu kullanıcısı).
              autofocus: true,
              onPressed: _start,
              child: const Text('Tekrar Dene'),
            ),
        ],
        child: failed
            ? InlineNotice(message: _error!)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    label: percentLabel == null
                        ? 'İndiriliyor'
                        : 'İndiriliyor, yüzde ${(fraction! * 100).round()}',
                    child: ExcludeSemantics(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: LinearProgressIndicator(
                          key: const ValueKey<String>(
                            'document_download_progress',
                          ),
                          value: fraction,
                          minHeight: 8,
                          backgroundColor: p.surfaceMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    total == null
                        ? (_received > 0
                              ? formatDocumentSize(_received)
                              : 'Hazırlanıyor...')
                        : '$percentLabel · ${formatDocumentSize(_received)} / ${formatDocumentSize(total)}',
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
      ),
    );
  }
}
