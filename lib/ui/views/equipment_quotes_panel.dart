// Ekipman ve Bakım > Teklifler sekmesi: yan yana karşılaştırma tablosu (P2-10) ve onaylı teklif revizyonu / sürüm geçmişi (P2-9, karar K14).
//
// - Aynı konuda iki ya da daha çok teklif varsa konu başlığının altında KARŞILAŞTIRMA TABLOSU çıkar (tutar, KDV esası, geçerlilik, teslim süresi, kapsam / not,
//   durum); "en düşük" ve "en hızlı" yalnız sunucunun işaretlediği tekliflerde görünür. Konudaki teklifler farklı KDV esasındaysa tutarlar kıyaslanamaz:
//   hiçbiri "en düşük" işaretlenmez ve tabloda uyarı çıkar.
// - Onaylı (kabul edilmiş) teklif yerinde değişmez: "Revizyon oluştur" yeni sürüm açar, önceki sürüme bağlanır; "Sürüm geçmişi" tüm sürümleri gösterir.
//   Eski onaylı fiyat "tarihli fiyat, güncel fiyat değildir" etiketiyle yazılır.
// - "Firma formu (dış firma teklifi)" bölümü ([QuoteRequestsSection], 113 / P2-8): tek kullanımlık form bağlantısı, firmanın gönderdiği TASLAK teklifler
//   (onayla = açık teklif oluşur; gider / sözleşme oluşmaz, kabul ayrı karardır) ve bekleyen bağlantılar.
// - Bu dosya yalnız sunum katmanıdır: eylemler (form, onay, istek) çağıranın geri çağrılarıdır ([EquipmentViewState]).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/equipment_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show InfoChip;

/// 2026-10-24 -> 24.10.2026
String quoteDate(String iso) => iso.length >= 10 ? '${iso.substring(8, 10)}.${iso.substring(5, 7)}.${iso.substring(0, 4)}' : iso;

/// Kuruşu form alanına "3200,00" olarak yazar ([parseKurus] ile geri okunur).
String kurusToInput(int kurus) => '${kurus ~/ 100},${(kurus % 100).toString().padLeft(2, '0')}';

/// "+600,00 TL" / "-150,00 TL" / "±0" (sürümler arası tutar farkı).
String quoteDelta(int deltaKurus) {
  if (deltaKurus == 0) return 'Tutar değişmedi';
  return '${deltaKurus > 0 ? '+' : '-'}${formatKurus(deltaKurus.abs())}';
}

String quoteStatusLabel(EquipmentQuote q) {
  if (q.status == 'accepted') return q.acceptedAs == 'contract' ? 'Kabul: sözleşme' : 'Kabul: gider';
  if (q.status == 'rejected') return q.isRevision ? 'Revizyon reddedildi' : 'Reddedildi';
  if (q.expired) return 'Süresi doldu';
  return q.isRevision ? 'Revizyon: onay bekliyor' : 'Açık';
}

AppTone quoteStatusTone(EquipmentQuote q) {
  if (q.status == 'accepted') return AppTone.success;
  if (q.status == 'rejected') return AppTone.danger;
  return q.expired ? AppTone.danger : AppTone.warning;
}

typedef QuoteAction = void Function(EquipmentQuote quote);

/// Teklifler sekmesinin gövdesi: konu başına başlık, (iki ve daha çok teklifte) karşılaştırma tablosu, teklif kartları.
class EquipmentQuotesPanel extends StatelessWidget {
  const EquipmentQuotesPanel({
    super.key,
    required this.quotes,
    required this.canWrite,
    this.onAccept,
    this.onReject,
    this.onEdit,
    this.onRevise,
    this.onHistory,
  });

  /// Sunucunun liste yanıtı (yalnız EN SON sürümler).
  final List<EquipmentQuote> quotes;
  final bool canWrite;
  final QuoteAction? onAccept;
  final QuoteAction? onReject;
  final QuoteAction? onEdit;
  final QuoteAction? onRevise;
  final QuoteAction? onHistory;

  @override
  Widget build(BuildContext context) {
    if (quotes.isEmpty) {
      return const AppCard(child: Text('Henüz teklif yok. Aynı konuda birden çok teklif girerseniz yan yana karşılaştırılır ve en düşük tutar işaretlenir.'));
    }
    final topics = <String>[];
    for (final q in quotes) {
      if (!topics.contains(q.topic)) topics.add(q.topic);
    }
    final th = Theme.of(context).textTheme;
    return Column(
      key: const ValueKey<String>('quotes_panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final topic in topics) ...<Widget>[
          Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.sm), child: Text(topic, style: th.titleMedium)),
          if (quotes.where((x) => x.topic == topic).length >= 2)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: QuoteComparisonTable(quotes: <EquipmentQuote>[for (final q in quotes) if (q.topic == topic) q]),
            ),
          for (final q in quotes.where((x) => x.topic == topic))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: QuoteCard(
                key: ValueKey<String>('quote_card_${q.id}'),
                quote: q,
                canWrite: canWrite,
                onAccept: onAccept,
                onReject: onReject,
                onEdit: onEdit,
                onRevise: onRevise,
                onHistory: onHistory,
              ),
            ),
        ],
      ],
    );
  }
}

/// Tek teklif kartı: tutar, durum, KDV / geçerlilik / teslim, kapsam / not, sürüm ve onay bilgisi, eylemler.
class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key, required this.quote, required this.canWrite, this.onAccept, this.onReject, this.onEdit, this.onRevise, this.onHistory});

  final EquipmentQuote quote;
  final bool canWrite;
  final QuoteAction? onAccept;
  final QuoteAction? onReject;
  final QuoteAction? onEdit;
  final QuoteAction? onRevise;
  final QuoteAction? onHistory;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    final th = Theme.of(context).textTheme;
    final approved = q.approvedVersion;
    final open = q.status == 'open';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Firma adı ve tutar: sığmazsa tutar alt satıra iner (dar ekran + büyük yazıda taşma olmaz).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: <Widget>[
              Text(q.vendorName, style: th.titleSmall),
              Text(formatKurus(q.amountKurus), style: th.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.xs,
            children: <Widget>[
              StatusDot(label: quoteStatusLabel(q), tone: quoteStatusTone(q), maxLines: 2),
              if (q.lowest) const StatusDot(label: 'En düşük', tone: AppTone.success),
              if (q.fastest) const StatusDot(label: 'En hızlı', tone: AppTone.success),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: <Widget>[
              InfoChip(q.vatLabel),
              if (q.validUntil != null) InfoChip('Geçerlilik: ${quoteDate(q.validUntil!)}'),
              if (q.deliveryLabel != null) InfoChip('Teslim: ${q.deliveryLabel}'),
              if (q.isRevision) InfoChip('Sürüm ${q.revisionNo}'),
            ],
          ),
          if (q.note != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text('Kapsam / not: ${q.note}')),
          if (q.documentNote != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text('Belge: ${q.documentNote}')),
          if (q.isRevision && q.revisionReason != null)
            Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text('Değişiklik gerekçesi: ${q.revisionReason}')),
          if (q.basisMixed)
            const Padding(
              padding: EdgeInsets.only(top: AppSpace.sm),
              child: Text('Bu konudaki teklifler farklı KDV esasında; tutarlar doğrudan kıyaslanamaz.'),
            ),
          if (q.status == 'accepted' && q.decidedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Text(
                'Onay tarihi ${quoteDate(q.decidedAt!)}: bu tutar o günkü onaylı fiyattır, güncel fiyat sayılmaz.',
                key: const ValueKey<String>('quote_dated_price'),
                style: th.bodySmall,
              ),
            ),
          if (approved != null && q.status != 'accepted')
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Text(
                'Onaylı sürüm (${approved.revisionNo}. sürüm): ${formatKurus(approved.amountKurus)}'
                '${approved.decidedAt == null ? '' : ' (${quoteDate(approved.decidedAt!)})'}'
                '${approved.recordLabel == null ? '' : ' - ${approved.recordLabel} olarak kayıtlı'}. Bu sürüm onaylanana dek onaylı sürüm geçerlidir.',
                key: const ValueKey<String>('quote_approved_version'),
                style: th.bodySmall,
              ),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: <Widget>[
              if (q.hasHistory && onHistory != null) TextButton(onPressed: () => onHistory!(q), child: const Text('Sürüm geçmişi')),
              if (canWrite && open && q.editable && onEdit != null) TextButton(onPressed: () => onEdit!(q), child: const Text('Düzenle')),
              if (canWrite && open && onReject != null) TextButton(onPressed: () => onReject!(q), child: const Text('Reddet')),
              if (canWrite && q.revisable && onRevise != null) OutlinedButton(onPressed: () => onRevise!(q), child: const Text('Revizyon oluştur')),
              if (canWrite && open && !q.expired && onAccept != null) FilledButton(onPressed: () => onAccept!(q), child: const Text('Kabul et')),
            ],
          ),
        ],
      ),
    );
  }
}

String quoteRequestStatusLabel(QuoteRequest r) {
  switch (r.status) {
    case 'draft':
      return 'Taslak teklif: onayınızı bekliyor';
    case 'approved':
      return 'Onaylandı: açık teklif oluştu';
    case 'rejected':
      return 'Reddedildi';
    case 'revoked':
      return 'Bağlantı iptal edildi';
    default:
      return r.expired ? 'Bağlantının süresi doldu' : 'Firmanın göndermesi bekleniyor';
  }
}

AppTone quoteRequestStatusTone(QuoteRequest r) {
  switch (r.status) {
    case 'draft':
      return AppTone.warning;
    case 'approved':
      return AppTone.success;
    case 'rejected':
      return AppTone.danger;
    default:
      return r.expired ? AppTone.danger : AppTone.neutral;
  }
}

typedef QuoteRequestAction = void Function(QuoteRequest request);

/// "Firma formu (dış firma teklifi)" bölümü (113, P2-8): tek kullanımlık form bağlantısı oluşturma, bekleyen bağlantılar, firmanın gönderdiği TASLAK teklifler
/// (onayla = AÇIK teklif oluşur, gider / sözleşme oluşmaz; reddet) ve son kapanan kayıtlar. Yalnız sunum katmanıdır: eylemler çağıranın geri çağrılarıdır.
/// Bağlantı belirteci bu bölümde ASLA görünmez (yalnız oluşturma anında çağıranın penceresinde gösterilir).
class QuoteRequestsSection extends StatelessWidget {
  const QuoteRequestsSection({super.key, required this.requests, required this.canWrite, this.onCreate, this.onRevoke, this.onApprove, this.onReject});

  final List<QuoteRequest> requests;
  final bool canWrite;
  final VoidCallback? onCreate;
  final QuoteRequestAction? onRevoke;
  final QuoteRequestAction? onApprove;
  final QuoteRequestAction? onReject;

  @override
  Widget build(BuildContext context) {
    if (!canWrite && requests.isEmpty) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    final drafts = <QuoteRequest>[for (final r in requests) if (r.isDraft) r];
    final waiting = <QuoteRequest>[for (final r in requests) if (r.status == 'invited') r];
    final closed = <QuoteRequest>[for (final r in requests) if (!r.isDraft && r.status != 'invited') r].take(5).toList();
    Widget heading(String label) => Padding(padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xs), child: Text(label, style: th.titleSmall));
    return Column(
      key: const ValueKey<String>('quote_requests_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.sm), child: Text('Firma formu (dış firma teklifi)', style: th.titleMedium)),
        const Text('Dış firmaya tek kullanımlık form bağlantısı gönderin. Firmanın girdiği teklif TASLAK olarak gelir; siz onaylamadan teklif, gider ya da sözleşme oluşmaz. Bağlantı yalnızca oluşturulduğu anda gösterilir.'),
        if (canWrite && onCreate != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: OutlinedButton.icon(key: const ValueKey<String>('quote_request_create'), onPressed: onCreate, icon: const Icon(Icons.link_rounded), label: const Text('Form bağlantısı oluştur')),
          ),
        if (requests.isEmpty) const Padding(padding: EdgeInsets.only(top: AppSpace.sm), child: Text('Henüz firma formu yok.')),
        if (drafts.isNotEmpty) ...<Widget>[
          heading('Onay bekleyen taslaklar (${drafts.length})'),
          for (final r in drafts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _QuoteDraftCard(key: ValueKey<String>('quote_draft_${r.id}'), request: r, canWrite: canWrite, onApprove: onApprove, onReject: onReject),
            ),
        ],
        if (waiting.isNotEmpty) ...<Widget>[
          heading('Bekleyen bağlantılar'),
          for (final r in waiting)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _QuoteWaitingCard(key: ValueKey<String>('quote_waiting_${r.id}'), request: r, canWrite: canWrite, onRevoke: onRevoke),
            ),
        ],
        if (closed.isNotEmpty) ...<Widget>[
          heading('Son kapananlar'),
          for (final r in closed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Wrap(
                key: ValueKey<String>('quote_closed_${r.id}'),
                spacing: AppSpace.md,
                runSpacing: AppSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(r.vendorName == null ? r.topic : '${r.vendorName} - ${r.topic}'),
                  StatusDot(label: quoteRequestStatusLabel(r), tone: quoteRequestStatusTone(r), maxLines: 2),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpace.md),
      ],
    );
  }
}

/// Firmanın gönderdiği taslak teklif: tutar, KDV, geçerlilik, teslim, irtibat ve not; onayla / reddet.
class _QuoteDraftCard extends StatelessWidget {
  const _QuoteDraftCard({super.key, required this.request, required this.canWrite, this.onApprove, this.onReject});

  final QuoteRequest request;
  final bool canWrite;
  final QuoteRequestAction? onApprove;
  final QuoteRequestAction? onReject;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final th = Theme.of(context).textTheme;
    final contact = <String>[if (r.vendorContact != null) 'Yetkili: ${r.vendorContact}', if (r.vendorPhone != null) 'Telefon: ${r.vendorPhone}'].join(' - ');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: <Widget>[
              Text(r.vendorName ?? '-', style: th.titleSmall),
              Text(r.amountKurus == null ? '-' : formatKurus(r.amountKurus!), style: th.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text('Konu: ${r.topic}'),
          const SizedBox(height: AppSpace.xs),
          StatusDot(label: quoteRequestStatusLabel(r), tone: quoteRequestStatusTone(r), maxLines: 2),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: <Widget>[
              InfoChip(r.vatLabel),
              if (r.validUntil != null) InfoChip('Geçerlilik: ${quoteDate(r.validUntil!)}'),
              if (r.deliveryLabel != null) InfoChip('Teslim: ${r.deliveryLabel}'),
            ],
          ),
          if (contact.isNotEmpty) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(contact)),
          if (r.note != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text('Kapsam / not: ${r.note}')),
          if (canWrite)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: <Widget>[
                if (onReject != null) TextButton(onPressed: () => onReject!(r), child: const Text('Reddet')),
                if (onApprove != null) FilledButton(onPressed: () => onApprove!(r), child: const Text('Onayla: açık teklif oluştur')),
              ],
            ),
        ],
      ),
    );
  }
}

/// Firmanın henüz göndermediği (ya da süresi dolan) bağlantı: konu, beklenen firma, son geçerlilik, iptal.
class _QuoteWaitingCard extends StatelessWidget {
  const _QuoteWaitingCard({super.key, required this.request, required this.canWrite, this.onRevoke});

  final QuoteRequest request;
  final bool canWrite;
  final QuoteRequestAction? onRevoke;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final th = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(r.topic, style: th.titleSmall),
          if (r.vendorHint != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text('Beklenen firma: ${r.vendorHint}')),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.xs,
            children: <Widget>[
              StatusDot(label: quoteRequestStatusLabel(r), tone: quoteRequestStatusTone(r), maxLines: 2),
              if (r.expiresAt != null) InfoChip('Son geçerlilik: ${quoteDate(r.expiresAt!)}'),
            ],
          ),
          if (canWrite && onRevoke != null)
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => onRevoke!(r), child: Text(r.expired ? 'Kaydı kapat' : 'Bağlantıyı iptal et'))),
        ],
      ),
    );
  }
}

/// Aynı konudaki tekliflerin yan yana tablosu: satırlar alanlar, sütunlar teklifler. Dar ekranda yatay kayar.
class QuoteComparisonTable extends StatelessWidget {
  const QuoteComparisonTable({super.key, required this.quotes});

  final List<EquipmentQuote> quotes;

  static const double labelWidth = 104;
  static const double columnWidth = 156;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final mixed = quotes.any((q) => q.basisMixed);
    final labelStyle = th.bodySmall?.copyWith(color: p.textMuted, fontWeight: FontWeight.w600);

    Widget cell(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.sm), child: child);
    TableRow line(String label, Widget Function(EquipmentQuote q) build) => TableRow(
      children: <Widget>[
        cell(Text(label, style: labelStyle)),
        for (final q in quotes) cell(build(q)),
      ],
    );
    Widget text(String value, {bool strong = false}) => Text(value, style: strong ? th.bodyMedium?.copyWith(fontWeight: FontWeight.w700) : th.bodyMedium);

    return AppCard(
      key: const ValueKey<String>('quote_compare_table'),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Karşılaştırma', style: th.titleSmall),
          const SizedBox(height: AppSpace.xs),
          Text('Kapsamlar farklı olabilir: tutarla birlikte KDV esasını, geçerliliği, teslim süresini ve notu okuyun. Eski onaylı fiyat güncel fiyat sayılmaz.', style: th.bodySmall),
          if (mixed) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            const InlineNotice(
              key: ValueKey<String>('quote_compare_mixed'),
              tone: AppTone.warning,
              message: 'Tutarlar farklı KDV esaslarında (dahil / hariç / belirtilmedi). Doğrudan kıyaslanamaz; "en düşük" işaretlenmedi.',
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const FixedColumnWidth(columnWidth),
              columnWidths: const <int, TableColumnWidth>{0: FixedColumnWidth(labelWidth)},
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              border: TableBorder(horizontalInside: BorderSide(color: p.border)),
              children: <TableRow>[
                line('Firma', (q) => text('${q.vendorName}${q.isRevision ? ' (sürüm ${q.revisionNo})' : ''}', strong: true)),
                line(
                  'Tutar',
                  (q) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      text(formatKurus(q.amountKurus), strong: true),
                      if (q.lowest) const StatusDot(label: 'En düşük', tone: AppTone.success),
                    ],
                  ),
                ),
                line('KDV', (q) => text(q.vatLabel)),
                line('Geçerlilik', (q) => text(q.validUntil == null ? '-' : '${quoteDate(q.validUntil!)}${q.expired ? ' (doldu)' : ''}')),
                line(
                  'Teslim süresi',
                  (q) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      text(q.deliveryLabel ?? '-'),
                      if (q.fastest) const StatusDot(label: 'En hızlı', tone: AppTone.success),
                    ],
                  ),
                ),
                line('Kapsam / not', (q) => text(q.note ?? '-')),
                line('Durum', (q) => StatusDot(label: quoteStatusLabel(q), tone: quoteStatusTone(q), maxLines: 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Teklifin sürüm geçmişi (eskiden yeniye): sürüm no, durum, tutar ve önceki sürüme göre fark, tarih, gerekçe, bağlı gider / sözleşme.
class QuoteHistorySheet extends StatefulWidget {
  const QuoteHistorySheet({super.key, required this.service, required this.site, required this.quote});

  final EquipmentService service;
  final EquipmentSite site;
  final EquipmentQuote quote;

  /// Alt sayfa olarak açar.
  static Future<void> show(BuildContext context, {required EquipmentService service, required EquipmentSite site, required EquipmentQuote quote}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(heightFactor: 0.85, child: QuoteHistorySheet(service: service, site: site, quote: quote)),
    );
  }

  @override
  State<QuoteHistorySheet> createState() => _QuoteHistorySheetState();
}

class _QuoteHistorySheetState extends State<QuoteHistorySheet> {
  QuoteHistory? _history;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final h = await widget.service.quoteHistory(widget.site.code, widget.quote.id);
      if (mounted) setState(() => _history = h);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final h = _history;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.xl),
      children: <Widget>[
        Text('Sürüm geçmişi', style: th.headlineSmall),
        Text('${widget.quote.vendorName} - ${widget.quote.topic}', style: th.bodyMedium),
        const SizedBox(height: AppSpace.sm),
        const Text('Onaylı sürümler değişmez; her değişiklik yeni bir sürüm olarak önceki sürüme bağlanır.'),
        const SizedBox(height: AppSpace.md),
        if (_error != null)
          InlineNotice(message: _error!, onRetry: () {
            setState(() => _error = null);
            _load();
          })
        else if (h == null)
          const Center(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: CircularProgressIndicator()))
        else
          for (var i = 0; i < h.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _VersionTile(
                key: ValueKey<String>('quote_version_${h.items[i].id}'),
                version: h.items[i],
                previous: i == 0 ? null : h.items[i - 1],
                isLatest: h.items[i].id == h.latestId,
                isApproved: h.items[i].id == h.approvedId,
              ),
            ),
      ],
    );
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({super.key, required this.version, required this.previous, required this.isLatest, required this.isApproved});

  final EquipmentQuote version;
  final EquipmentQuote? previous;
  final bool isLatest;
  final bool isApproved;

  @override
  Widget build(BuildContext context) {
    final v = version;
    final th = Theme.of(context).textTheme;
    final prev = previous;
    final record = v.expenseId != null ? 'Gider #${v.expenseId}' : (v.contractId != null ? 'Sözleşme #${v.contractId}' : null);
    return AppCard(
      selected: isApproved,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: <Widget>[
              Text('${v.revisionNo}. sürüm', style: th.titleSmall),
              Text(formatKurus(v.amountKurus), style: th.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.xs,
            children: <Widget>[
              StatusDot(label: quoteStatusLabel(v), tone: quoteStatusTone(v), maxLines: 2),
              if (isApproved) const StatusDot(label: 'Geçerli onaylı sürüm', tone: AppTone.success),
              if (isLatest) const InfoChip('En son sürüm'),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          if (prev != null) Text('Önceki sürüme göre: ${quoteDelta(v.amountKurus - prev.amountKurus)}'),
          Text('${v.vatLabel}${v.validUntil == null ? '' : ' - geçerlilik ${quoteDate(v.validUntil!)}'}${v.deliveryLabel == null ? '' : ' - teslim ${v.deliveryLabel}'}'),
          if (v.note != null) Text('Kapsam / not: ${v.note}'),
          if (v.revisionReason != null) Text('Değişiklik gerekçesi: ${v.revisionReason}'),
          if (v.decidedAt != null) Text('Karar tarihi: ${quoteDate(v.decidedAt!)}'),
          if (record != null) Text('Oluşan kayıt: $record'),
        ],
      ),
    );
  }
}
