import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Pencere başlığı en çok 3 satırdır; bu uzunluğun üstündeki başlık (dar ekran + büyük yazıda kesilebilir)
/// gövdenin başında ayrıca TAM gösterilir.
const int kLongTitleRunes = 36;

bool isLongTitle(String title) => title.trim().runes.length > kLongTitleRunes;

/// Duyuru durum rozeti (Platform Faz 3a). Renk tek başına anlam taşımaz: etiket ve simge de farklıdır.
class AnnouncementStatusChip extends StatelessWidget {
  const AnnouncementStatusChip(this.status, {super.key});

  final AnnouncementStatus status;

  static AppTone toneOf(AnnouncementStatus status) => switch (status) {
    AnnouncementStatus.draft => AppTone.neutral,
    AnnouncementStatus.scheduled => AppTone.info,
    AnnouncementStatus.published => AppTone.success,
    AnnouncementStatus.withdrawn => AppTone.warning,
    AnnouncementStatus.unknown => AppTone.neutral,
  };

  static IconData iconOf(AnnouncementStatus status) => switch (status) {
    AnnouncementStatus.draft => Icons.edit_note_rounded,
    AnnouncementStatus.scheduled => Icons.schedule_rounded,
    AnnouncementStatus.published => Icons.campaign_rounded,
    AnnouncementStatus.withdrawn => Icons.undo_rounded,
    AnnouncementStatus.unknown => Icons.help_outline_rounded,
  };

  @override
  Widget build(BuildContext context) => StatusChip(
    label: status.label,
    tone: toneOf(status),
    icon: iconOf(status),
  );
}

/// "Acil" işareti (kırmızı + ünlem simgesi + etiket).
class UrgentChip extends StatelessWidget {
  const UrgentChip({super.key});

  @override
  Widget build(BuildContext context) => const StatusChip(
    label: 'Acil',
    tone: AppTone.danger,
    icon: Icons.priority_high_rounded,
  );
}

/// Yönetici listesi kartı: durum + acil işareti, başlık, önizleme, hedef, zaman ve okunma "12/48".
/// Dokununca ayrıntı penceresi açılır ([onTap]). Metinler sarar (kırpılmaz); çipler `Wrap` içindedir.
class AnnouncementAdminCard extends StatelessWidget {
  const AnnouncementAdminCard({
    super.key,
    required this.announcement,
    required this.onTap,
  });

  final AnnouncementSummary announcement;
  final VoidCallback onTap;

  String? get _timeLabel {
    switch (announcement.status) {
      case AnnouncementStatus.scheduled:
        return announcement.publishAt == null
            ? null
            : 'Yayın zamanı: ${formatIstanbulDateTime(announcement.publishAt)}';
      case AnnouncementStatus.published:
      case AnnouncementStatus.withdrawn:
        return announcement.publishedAt == null
            ? null
            : 'Yayınlandı: ${formatIstanbulDateTime(announcement.publishedAt)}';
      case AnnouncementStatus.draft:
      case AnnouncementStatus.unknown:
        return announcement.createdAt == null
            ? null
            : 'Oluşturuldu: ${formatIstanbulDateTime(announcement.createdAt)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final a = announcement;
    final title = a.title.trim().isEmpty ? 'Başlıksız duyuru' : a.title.trim();
    final preview = a.bodyPreview.trim();
    final time = _timeLabel;
    final readCount = a.readCount;
    final hidden = a.readHidden;
    final ratio = a.hasAudience && readCount != null
        ? '$readCount/${a.recipientCount}'
        : null;
    // Kartın TEK birleşik ekran okuyucu etiketi (içerik semantiği dışlanır: iki kez okunmaz).
    final semantic = StringBuffer('Duyuru: $title. ${a.status.label}.');
    if (a.isUrgent) semantic.write(' Acil.');
    semantic.write(' Hedef: ${a.targetType.label}.');
    if (time != null) semantic.write(' $time.');
    if (ratio != null) {
      semantic.write(
        ' $readCount kişi okudu, toplam ${a.recipientCount} alıcı.',
      );
    } else if (hidden) {
      semantic.write(
        ' Okunma sayısı gizli (küçük hedef), toplam ${a.recipientCount} alıcı.',
      );
    }
    if (a.sendEmail) semantic.write(' E-posta da gönderilir.');
    if (a.editedAt != null && a.status == AnnouncementStatus.published) {
      semantic.write(' Düzenlendi.');
    }

    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: semantic.toString(),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                AnnouncementStatusChip(a.status),
                if (a.isUrgent) const UrgentChip(),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            // Kartta en çok 3 satır; tam başlık ayrıntı penceresinde ve ekran okuyucu etiketindedir.
            Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: th.titleMedium,
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: th.bodyMedium?.copyWith(color: p.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                InfoChip('Hedef: ${a.targetType.label}'),
                if (time != null) InfoChip(time),
                if (ratio != null) InfoChip('Okunma: $ratio'),
                // Kurul + küçük hedef: sunucu okunma sayısını gizler; "0/3" yazılmaz.
                if (hidden)
                  const Tooltip(
                    message: 'Gizli: küçük hedef',
                    child: InfoChip('Okunma: —'),
                  ),
                if (a.sendEmail) const InfoChip('E-posta da gönderilir'),
                if (a.editedAt != null &&
                    a.status == AnnouncementStatus.published)
                  const InfoChip('Düzenlendi'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sakin gelen kutusu kartı: okunmamışta nokta + kalın başlık, acil rozeti, önizleme, site (birden çok
/// sitede), yayın zamanı ve "düzenlendi" notu. Dokununca tam metin açılır ([onTap]).
///
/// Okunmamış durumu yalnız renkle verilmez: nokta (şekil), kalın başlık ve ekran okuyucu etiketi
/// ("Okunmamış") birlikte kullanılır.
class AnnouncementInboxCard extends StatelessWidget {
  const AnnouncementInboxCard({
    super.key,
    required this.announcement,
    required this.onTap,
    this.showSite = false,
  });

  final ResidentAnnouncement announcement;
  final VoidCallback onTap;

  /// Birden çok sitesi olan sakinde site adı da gösterilir.
  final bool showSite;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final a = announcement;
    final title = a.title.trim().isEmpty ? 'Başlıksız duyuru' : a.title.trim();
    final preview = a.previewOrBody.trim();
    final site = a.siteName.trim();
    // Kartın TEK birleşik etiketi; içerik semantiği dışlanır (iki kez okunmaz). Okunmamış durumu metinle verilir.
    final semantic = StringBuffer(a.isRead ? 'Duyuru: ' : 'Okunmamış duyuru: ');
    if (a.isUrgent) semantic.write('Acil. ');
    semantic.write(title);
    if (showSite && site.isNotEmpty) semantic.write('. $site');
    if (a.publishedAt != null) {
      semantic.write('. ${formatIstanbulDateTime(a.publishedAt)}');
    }
    if (a.isEdited) semantic.write('. Düzenlendi');
    if (preview.isNotEmpty) semantic.write('. $preview');

    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: semantic.toString(),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Okunmamış noktası: şekil işareti (renk tek başına anlam taşımaz; kalın başlık ve etiket de var).
            ExcludeSemantics(
              child: SizedBox(
                width: 16,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: a.isRead
                      ? null
                      : DecoratedBox(
                          key: const ValueKey<String>(
                            'announcement_unread_dot',
                          ),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTone.primary.a,
                          ),
                          child: const SizedBox(width: 10, height: 10),
                        ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (a.isUrgent) ...[
                    const Wrap(children: [UrgentChip()]),
                    const SizedBox(height: AppSpace.xs),
                  ],
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: th.titleMedium?.copyWith(
                      fontWeight: a.isRead ? FontWeight.w600 : FontWeight.w800,
                    ),
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: th.bodyMedium?.copyWith(color: p.textSecondary),
                    ),
                  ],
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      if (showSite && site.isNotEmpty) InfoChip(site),
                      if (a.publishedAt != null)
                        InfoChip(formatIstanbulDateTime(a.publishedAt)),
                      if (a.isEdited) const InfoChip('Düzenlendi'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gövdenin üstüne sabitlenen kalıcı kırmızı şerit: okunmamış ACİL duyuru varken (Duyurular ekranı hariç)
/// her sayfada görünür, duyuru okununca kalkar. Dokununca duyuruyu açar ([onTap]). [title] bilinmiyorsa
/// genel metin yazılır.
///
/// Renk tek başına anlam taşımaz: simge ve "acil duyuru" metni vardır. Dokunma hedefi >= 48 dp; metin en
/// çok 3 satır (sabit şerit ekranı yemesin), tam metin ekran okuyucu etiketindedir. Ekran okuyucu için
/// canlı bölge + düğmedir.
class UrgentAnnouncementBanner extends StatelessWidget {
  const UrgentAnnouncementBanner({
    super.key,
    required this.count,
    required this.onTap,
    this.title,
  });

  final int count;
  final String? title;
  final VoidCallback onTap;

  String get message {
    final name = (title ?? '').trim();
    if (count > 1) {
      return name.isEmpty
          ? '$count okunmamış acil duyurunuz var'
          : '$count okunmamış acil duyurunuz var. En yenisi: $name';
    }
    return name.isEmpty
        ? 'Okunmamış acil duyurunuz var'
        : 'Okunmamış acil duyuru: $name';
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final text = message;
    return Semantics(
      container: true,
      liveRegion: true,
      button: true,
      label: '$text. Açmak için dokunun.',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          key: const ValueKey<String>('urgent_announcement_banner'),
          color: AppTone.danger.b,
          borderRadius: BorderRadius.circular(AppRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                  vertical: AppSpace.md,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.campaign_rounded, color: Colors.white),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      // Şerit gövdenin üstüne SABİTLENİR (içerik kaydırılırken kalır): çok uzun başlık ekranı
                      // yemesin diye en çok 3 satır; tam metin ekran okuyucu etiketinde ve dokununca açılan
                      // duyuruda bulunur.
                      child: Text(
                        text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: th.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
