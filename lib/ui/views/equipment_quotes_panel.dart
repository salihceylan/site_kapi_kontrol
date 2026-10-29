// Ekipman ve Bakım > Teklifler sekmesi: yan yana karşılaştırma tablosu (P2-10) ve onaylı teklif revizyonu / sürüm geçmişi (P2-9, karar K14).
//
// - Aynı konuda iki ya da daha çok teklif varsa konu başlığının altında KARŞILAŞTIRMA TABLOSU çıkar (tutar, KDV esası, geçerlilik, teslim süresi, kapsam / not,
//   durum); "en düşük" ve "en hızlı" yalnız sunucunun işaretlediği tekliflerde görünür. Konudaki teklifler farklı KDV esasındaysa tutarlar kıyaslanamaz:
//   hiçbiri "en düşük" işaretlenmez ve tabloda uyarı çıkar.
// - Onaylı (kabul edilmiş) teklif yerinde değişmez: "Revizyon oluştur" yeni sürüm açar, önceki sürüme bağlanır; "Sürüm geçmişi" tüm sürümleri gösterir.
//   Eski onaylı fiyat "tarihli fiyat, güncel fiyat değildir" etiketiyle yazılır.
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
