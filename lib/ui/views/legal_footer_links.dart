import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/legal_document_view.dart';
import 'package:site_kapi_kontrol/ui/views/legal_markdown.dart';

/// Giriş ekranı altındaki "Kullanım Koşulları · Gizlilik · KVKK" bağlantıları.
///
/// Oturum açılmadan önce belge listesi okunmaz: kimlikler sabittir ([LegalDocumentIds]) ve belge metni
/// tıklayınca [LegalDocumentView] ile yüklenir (hata / yeniden dene orada). Her bağlantı >= 48 dp
/// yüksekliğindedir ve ekran okuyucuya tam belge adıyla okunur. Geniş/normal yazıda yan yana ayırıcılı,
/// dar ekranda ya da büyük yazıda alt alta (ayırıcısız) dizilir; taşma olmaz.
class LegalFooterLinks extends StatefulWidget {
  const LegalFooterLinks({super.key, this.api, this.onOpenLink});

  final LegalApi? api;
  final LegalLinkOpener? onOpenLink;

  static const List<(String id, String short, String full)> entries = <(String, String, String)>[
    (LegalDocumentIds.terms, 'Kullanım Koşulları', 'Kullanım Koşulları'),
    (LegalDocumentIds.privacy, 'Gizlilik', 'Gizlilik Politikası'),
    (LegalDocumentIds.kvkkNotice, 'KVKK', 'KVKK Aydınlatma Metni'),
  ];

  @override
  State<LegalFooterLinks> createState() => _LegalFooterLinksState();
}

class _LegalFooterLinksState extends State<LegalFooterLinks> {
  bool _opening = false;

  Future<void> _open(String id, String title) async {
    if (_opening) return;
    _opening = true;
    try {
      await LegalDocumentView.open(
        context,
        documentId: id,
        title: title,
        api: widget.api,
        onOpenLink: widget.onOpenLink,
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final stacked = textScale > 1.3 || MediaQuery.sizeOf(context).width < 340;

    Widget link((String, String, String) entry) {
      final (id, short, full) = entry;
      return TextButton(
        onPressed: () => unawaited(_open(id, full)),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: p.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        ),
        // Kısa görünen ad yerine tam belge adı okunur.
        child: Semantics(
          label: '$full belgesini aç',
          excludeSemantics: true,
          child: Text(short, textAlign: TextAlign.center),
        ),
      );
    }

    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[for (final e in LegalFooterLinks.entries) link(e)],
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (var i = 0; i < LegalFooterLinks.entries.length; i++) ...<Widget>[
          if (i > 0)
            ExcludeSemantics(
              child: Text('·', style: Theme.of(context).textTheme.bodySmall),
            ),
          link(LegalFooterLinks.entries[i]),
        ],
      ],
    );
  }
}
