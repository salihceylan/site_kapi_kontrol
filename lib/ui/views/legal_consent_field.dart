import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/views/legal_consent_controller.dart';
import 'package:site_kapi_kontrol/ui/views/legal_document_view.dart';
import 'package:site_kapi_kontrol/ui/views/legal_markdown.dart';
import 'package:site_kapi_kontrol/ui/views/legal_parts.dart';

/// Kayıt / site başvurusu formlarındaki yasal onay bölümü: "…okudum" kutusu + belge bağlantıları.
///
/// Durumlar ([LegalConsentController.status]):
/// - yükleniyor: kısa bilgi satırı (kutu YOK; gönderim kapalı),
/// - hata: neden + "Yeniden dene" (kutu YOK, sahte onay yok),
/// - hazır + onay gerektiren belge var: kutu + her belge için bağlantı düğmesi,
/// - hazır + belge yok: hiçbir şey çizilmez.
///
/// Kutu satırının tamamı dokunma alanıdır (>= 48 dp) ve ekran okuyucuya tek öğedir ("kutu, etiket,
/// işaretli/işaretsiz"). Belge bağlantıları ayrı düğmelerdir (>= 48 dp); belge sayfası açılırken ikinci
/// dokunuş yok sayılır.
class LegalConsentField extends StatefulWidget {
  const LegalConsentField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onOpenLink,
  });

  final LegalConsentController controller;

  /// false: gönderim sürerken kutu ve bağlantılar pasif.
  final bool enabled;

  /// Belge içindeki bağlantı açıcı (testler için).
  final LegalLinkOpener? onOpenLink;

  /// Bilinen belgeler için etiket ve Türkçe iyelik eki ("…'nı" / "…'ni").
  static const Map<String, (String, String)> _known = <String, (String, String)>{
    LegalDocumentIds.terms: ('Kullanım Koşulları', "'nı"),
    LegalDocumentIds.privacy: ('Gizlilik Politikası', "'nı"),
    LegalDocumentIds.kvkkNotice: ('KVKK Aydınlatma Metni', "'ni"),
    LegalDocumentIds.dpa: ('Veri İşleme Sözleşmesi', "'ni"),
  };

  /// Kutu etiketi. Kayıt belgeleri için sözleşmedeki cümle:
  /// "Kullanım Koşulları, Gizlilik Politikası ve KVKK Aydınlatma Metni'ni okudum."
  static String leadFor(List<LegalDocumentSummary> documents) {
    final ids = <String>[for (final d in documents) d.id];
    if (ids.isEmpty) return '';
    if (ids.length == 1 && ids.first == LegalDocumentIds.dpa) {
      return "Veri İşleme Sözleşmesi'ni okudum ve kabul ediyorum.";
    }
    final knownOnly = ids.every(
      (id) => id != LegalDocumentIds.dpa && _known.containsKey(id),
    );
    if (!knownOnly) return 'Aşağıdaki belgeleri okudum ve kabul ediyorum.';
    // Sözleşme sırası: koşullar, gizlilik, KVKK.
    final ordered = <String>[
      for (final id in const <String>[
        LegalDocumentIds.terms,
        LegalDocumentIds.privacy,
        LegalDocumentIds.kvkkNotice,
      ])
        if (ids.contains(id)) id,
    ];
    final names = <String>[for (final id in ordered) _known[id]!.$1];
    final suffix = _known[ordered.last]!.$2;
    final String joined;
    if (names.length == 1) {
      joined = names.first;
    } else {
      joined = '${names.sublist(0, names.length - 1).join(', ')} ve ${names.last}';
    }
    return '$joined$suffix okudum.';
  }

  @override
  State<LegalConsentField> createState() => _LegalConsentFieldState();
}

class _LegalConsentFieldState extends State<LegalConsentField> {
  bool _opening = false;
  late LegalLoadStatus _previousStatus = widget.controller.status;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(LegalConsentField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _previousStatus = widget.controller.status;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// Yükleme sonucu odak taşımadan değişir ("Yeniden dene" düğmesi kaybolur): ekran okuyucuya duyurulur.
  void _onControllerChanged() {
    final status = widget.controller.status;
    final previous = _previousStatus;
    _previousStatus = status;
    if (!mounted || status == previous) return;
    if (status == LegalLoadStatus.ready && widget.controller.needsConsent) {
      announcePolite(context, 'Belgeler yüklendi. Onay kutusunu işaretleyebilirsiniz.');
    }
  }

  Future<void> _openDocument(LegalDocumentSummary document) async {
    if (_opening || !widget.enabled) return;
    _opening = true;
    try {
      await LegalDocumentView.open(
        context,
        documentId: document.id,
        title: document.title,
        api: widget.controller.api,
        onOpenLink: widget.onOpenLink,
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        switch (controller.status) {
          case LegalLoadStatus.loading:
            return const _LoadingRow();
          case LegalLoadStatus.error:
            return LegalRetryNotice(
              message: controller.error ?? LegalMessages.loadFailed,
              onRetry: () => unawaited(controller.load()),
            );
          case LegalLoadStatus.ready:
            if (!controller.needsConsent) return const SizedBox.shrink();
            return _buildCheckbox(context, controller);
        }
      },
    );
  }

  Widget _buildCheckbox(BuildContext context, LegalConsentController controller) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final enabled = widget.enabled;
    final lead = LegalConsentField.leadFor(controller.documents);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Satırın tamamı dokunma alanı; kutu + etiket ekran okuyucuya tek öğe.
        MergeSemantics(
          child: InkWell(
            onTap: enabled ? () => controller.setAccepted(!controller.accepted) : null,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Checkbox(
                    value: controller.accepted,
                    onChanged: enabled ? (value) => controller.setAccepted(value ?? false) : null,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                      child: Text(
                        lead,
                        style: th.bodyMedium?.copyWith(color: p.text),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Belge bağlantıları: her biri ayrı, >= 48 dp düğme (satıra sığmazsa alta iner).
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: 0,
          children: <Widget>[
            for (final document in controller.documents)
              TextButton.icon(
                onPressed: enabled ? () => unawaited(_openDocument(document)) : null,
                icon: const Icon(Icons.description_outlined, size: 18),
                label: Text('${document.title} metnini oku'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  alignment: AlignmentDirectional.centerStart,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      label: 'Belgeler yükleniyor',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text('Belgeler yükleniyor...', style: th.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
