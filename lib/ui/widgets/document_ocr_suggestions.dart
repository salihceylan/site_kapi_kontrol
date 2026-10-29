// "Görselden oku" (P2-13, karar K15): seçilen dekont / fatura görselinden CİHAZDA metin çıkarır, tutar / tarih / IBAN adaylarını ÖNERİ olarak sunar.
//
// Kullanıcı bir adaya dokunmadıkça forma hiçbir şey yazılmaz. Görüntü ve metin ağa gönderilmez. Düğme yalnız okuma desteklenen platformda
// (Android / iOS) ve seçilen dosya JPEG / PNG görselse görünür; web, masaüstü ve PDF'te hiçbir şey çizilmez (form eski haliyle çalışır).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/payment_info.dart' show groupIban;
import 'package:site_kapi_kontrol/services/document_text_parser.dart';
import 'package:site_kapi_kontrol/services/document_text_reader.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';

/// JPEG / PNG görsel mi (içerik imzasından; ML Kit PDF okumaz).
bool isOcrImage(Uint8List b) =>
    (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) || (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47);

class DocumentOcrSuggestions extends StatefulWidget {
  const DocumentOcrSuggestions({
    super.key,
    required this.bytes,
    this.sourceName,
    this.reader,
    this.onAmount,
    this.onDate,
    this.onIban,
    this.notBefore,
    this.notAfter,
    this.enabled = true,
    this.keyPrefix = 'ocr',
  });

  /// Seçilen dosyanın baytları; null ya da görsel değilse hiçbir şey çizilmez.
  final Uint8List? bytes;

  /// Birden çok dosya varken hangisinin okunacağını söyler (isteğe bağlı).
  final String? sourceName;

  /// Metin okuyucu (testlerde sahte); null ise platform varsayılanı.
  final DocumentTextReader? reader;

  /// Kullanıcı bir adaya DOKUNUNCA çağrılır (kuruş / tarih / boşluksuz IBAN). Verilmeyen alan türü için aday gösterilmez.
  final ValueChanged<int>? onAmount;
  final ValueChanged<DateTime>? onDate;
  final ValueChanged<String>? onIban;

  /// Formun kabul ettiği tarih aralığı (dışındaki adaylar elenir).
  final DateTime? notBefore;
  final DateTime? notAfter;
  final bool enabled;
  final String keyPrefix;

  @override
  State<DocumentOcrSuggestions> createState() => _DocumentOcrSuggestionsState();
}

class _DocumentOcrSuggestionsState extends State<DocumentOcrSuggestions> {
  DocumentTextReader? _platformReader;
  DocumentTextReader get _reader => widget.reader ?? (_platformReader ??= platformDocumentTextReader());
  bool _reading = false;
  bool _failed = false;
  DocumentSuggestions? _result;
  final Set<String> _applied = <String>{};
  int _token = 0;

  String _k(String suffix) => '${widget.keyPrefix}_$suffix';

  @override
  void didUpdateWidget(DocumentOcrSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Başka dosya seçildi: eski dosyanın önerileri geçmez, süren okumanın sonucu atılır.
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _token++;
      _reading = false;
      _failed = false;
      _result = null;
      _applied.clear();
    }
  }

  Future<void> _read() async {
    final bytes = widget.bytes;
    if (bytes == null || _reading) return;
    final token = ++_token;
    setState(() {
      _reading = true;
      _failed = false;
      _result = null;
      _applied.clear();
    });
    String? text;
    try {
      text = await _reader.read(bytes);
    } on Object {
      text = null;
    }
    if (!mounted || token != _token) return;
    setState(() {
      _reading = false;
      if (text == null || text.trim().isEmpty) {
        _failed = true;
      } else {
        _result = parseDocumentText(text, notBefore: widget.notBefore, notAfter: widget.notAfter);
      }
    });
  }

  void _apply(String id, VoidCallback write) {
    write();
    if (mounted) setState(() => _applied.add(id));
  }

  Widget _chip(String id, String label, VoidCallback write) {
    final done = _applied.contains(id);
    return ActionChip(
      key: ValueKey<String>(_k(id)),
      avatar: done ? const Icon(Icons.check_rounded, size: 18) : null,
      label: Text(label),
      onPressed: widget.enabled ? () => _apply(id, write) : null,
    );
  }

  Widget _group(String title, List<Widget> chips) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: th.bodySmall?.copyWith(color: p.textSecondary)),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: chips),
        ],
      ),
    );
  }

  String _ibanLabel(IbanCandidate c) {
    final text = groupIban(c.iban);
    return switch (c.role) {
      IbanRole.sender => 'Gönderen: $text',
      IbanRole.receiver => 'Alıcı: $text',
      IbanRole.unknown => text,
    };
  }

  Widget _panel(BuildContext context, DocumentSuggestions result) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final amounts = widget.onAmount == null ? const <AmountCandidate>[] : result.amounts;
    final dates = widget.onDate == null ? const <DateTime>[] : result.dates;
    final ibans = widget.onIban == null ? const <IbanCandidate>[] : result.ibans;
    final empty = amounts.isEmpty && dates.isEmpty && ibans.isEmpty;
    return Container(
      key: ValueKey<String>(_k('panel')),
      margin: const EdgeInsets.only(top: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Önerilen değerler', style: th.titleSmall),
          const SizedBox(height: AppSpace.xs),
          Text(
            empty
                ? 'Görselde tutar, tarih ya da IBAN bulunamadı. Alanları elle doldurun.'
                : 'Doğru olana dokunun; dokunmadığınız alana bir şey yazılmaz. Okuma telefonunuzda yapılır, görüntü internete gönderilmez.',
            key: ValueKey<String>(_k(empty ? 'none' : 'hint')),
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
          if (amounts.isNotEmpty)
            _group('Tutar', [
              for (var i = 0; i < amounts.length; i++) _chip('amount_$i', formatMinor(amounts[i].minor), () => widget.onAmount!(amounts[i].minor)),
            ]),
          if (dates.isNotEmpty)
            _group('Tarih', [for (var i = 0; i < dates.length; i++) _chip('date_$i', formatDateField(dates[i]), () => widget.onDate!(dates[i]))]),
          if (ibans.isNotEmpty)
            _group('IBAN', [for (var i = 0; i < ibans.length; i++) _chip('iban_$i', _ibanLabel(ibans[i]), () => widget.onIban!(ibans[i].iban))]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.bytes;
    if (bytes == null || !isOcrImage(bytes) || !_reader.supported) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final name = widget.sourceName;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(
        key: ValueKey<String>(_k('box')),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: ValueKey<String>(_k('read')),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: widget.enabled && !_reading ? _read : null,
              icon: _reading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_rounded),
              label: Text(_reading ? 'Okunuyor...' : 'Görselden oku'),
            ),
          ),
          if (name != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                'Okunacak görsel: $name',
                key: ValueKey<String>(_k('source')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                'Görselden metin okunamadı. Daha net ve düz bir fotoğraf deneyin ya da alanları elle doldurun.',
                key: ValueKey<String>(_k('failed')),
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
          if (_result != null) _panel(context, _result!),
        ],
      ),
    );
  }
}
