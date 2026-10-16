import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/views/legal_markdown.dart';
import 'package:site_kapi_kontrol/ui/views/legal_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Tek bir yasal belgeyi tam ekranda gösterir (Kullanım Koşulları, Gizlilik, KVKK, DPA...).
///
/// Durumlar: yükleniyor (iskelet) | hata (bildirim + "Yeniden dene"; ASLA boş belge gibi görünmez) | belge.
/// Metin boyutu ölçeğine uyar, uzun belge kaydırılır; aşağı çekince yenilenir. Bağlantılar yalnız https
/// ve dış uygulamada açılır ([LegalMarkdown]).
class LegalDocumentView extends StatefulWidget {
  const LegalDocumentView({
    super.key,
    required this.documentId,
    this.titleHint,
    this.api,
    this.onOpenLink,
  });

  final String documentId;

  /// Belge yüklenene dek (ya da yüklenemezse) başlıkta gösterilen ad.
  final String? titleHint;

  /// Verilmezse varsayılan sunucuya bağlanan bir [LegalApi] kurulur.
  final LegalApi? api;

  /// Bağlantı açıcı (testler için).
  final LegalLinkOpener? onOpenLink;

  /// Belgeyi yeni sayfada açar. Çift dokunuşta ikinci sayfa açılmasın diye çağıranın düğmesi tek
  /// dokunuşluk olmalıdır; sayfa kendisi zaten kimliği sabit, yan etkisiz bir okumadır.
  static Future<void> open(
    BuildContext context, {
    required String documentId,
    String? title,
    LegalApi? api,
    LegalLinkOpener? onOpenLink,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentView(
          documentId: documentId,
          titleHint: title,
          api: api,
          onOpenLink: onOpenLink,
        ),
      ),
    );
  }

  @override
  State<LegalDocumentView> createState() => _LegalDocumentViewState();
}

class _LegalDocumentViewState extends State<LegalDocumentView> {
  late final LegalApi _api = widget.api ?? LegalApi.defaultInstance();
  final FocusNode _titleFocus = FocusNode(debugLabel: 'legal_document_title');

  LegalDocument? _document;
  String? _error;
  bool _loading = true;

  /// İstek sürerken ikinci istek açılmaz (çift dokunma / yenileme).
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted || _inFlight) return;
    _inFlight = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    LegalDocument? document;
    String? failure;
    try {
      document = await _api.getDocument(widget.documentId);
    } on ApiException catch (e) {
      failure = e.message;
    } catch (_) {
      failure = LegalMessages.loadFailed;
    }
    _inFlight = false;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (document != null) {
        _document = document;
        _error = null;
      } else {
        // İlk yükleme başarısızsa hata ekranı; yenileme başarısızsa eski metin kalır, hata üstte görünür.
        _error = failure;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (document != null) {
        _titleFocus.requestFocus();
        announcePolite(context, 'Belge yüklendi: ${document.title}');
      } else if (failure != null) {
        announcePolite(context, failure);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _document?.title ?? widget.titleHint ?? 'Belge';
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: wrappedTitleToolbarHeight(context),
        titleTextStyle: wrappedTitleStyle(context),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 400 ? AppSpace.md : AppSpace.lg,
              AppSpace.sm,
              MediaQuery.sizeOf(context).width < 400 ? AppSpace.md : AppSpace.lg,
              AppSpace.xxl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: _buildBody(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final document = _document;
    if (document == null) {
      if (_loading) return const _DocumentSkeleton();
      return Padding(
        padding: const EdgeInsets.only(top: AppSpace.lg),
        child: LegalRetryNotice(
          message: _error ?? LegalMessages.loadFailed,
          onRetry: _load,
        ),
      );
    }
    final th = Theme.of(context).textTheme;
    final effective = formatLegalDate(document.summary.effectiveDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_error != null) ...<Widget>[
          LegalRetryNotice(message: _error!, onRetry: _load, busy: _loading),
          const SizedBox(height: AppSpace.md),
        ],
        AppCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Focus(
                focusNode: _titleFocus,
                child: Semantics(
                  header: true,
                  child: Text(document.title, style: th.headlineMedium),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: <Widget>[
                  InfoChip('Sürüm: ${document.version}'),
                  if (effective != null) InfoChip('Yürürlük: $effective'),
                ],
              ),
              if (!document.summary.complete) ...<Widget>[
                const SizedBox(height: AppSpace.md),
                const InlineNotice(
                  tone: AppTone.warning,
                  message:
                      'Bu belgedeki köşeli parantezli [……] alanlar henüz doldurulmamıştır. '
                      'Belge taslak niteliğindedir.',
                ),
              ],
              const Divider(height: AppSpace.xl),
              if (document.contentMd.trim().isEmpty)
                Text('Bu belgenin metni boş döndü. Daha sonra tekrar deneyin.', style: th.bodyMedium)
              else
                LegalMarkdown(
                  source: document.contentMd,
                  onOpenLink: widget.onOpenLink,
                  // Belge sınırı aşılıp kesilirse tam metin için sunucunun web sayfası (/legal/:id).
                  fullTextUri: _api.webPageUri(document.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Belge yüklenirken iskelet (başlık + birkaç paragraf satırı). Ekran okuyucu "Yükleniyor" okur.
class _DocumentSkeleton extends StatelessWidget {
  const _DocumentSkeleton();

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const FractionallySizedBox(
              widthFactor: 0.6,
              alignment: Alignment.centerLeft,
              child: SkeletonBox(height: 24),
            ),
            const SizedBox(height: AppSpace.lg),
            for (var i = 0; i < 8; i++) ...<Widget>[
              FractionallySizedBox(
                widthFactor: i % 4 == 3 ? 0.7 : 1,
                alignment: Alignment.centerLeft,
                child: const SkeletonBox(),
              ),
              const SizedBox(height: AppSpace.md),
            ],
          ],
        ),
      ),
    );
  }
}
