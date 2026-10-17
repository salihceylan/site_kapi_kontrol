// Belgeler ekranlarının ortak parçaları (docs/PLATFORM_BELGELER.md A13): kategori / durum çipleri, yönetici ve
// sakin kartları, kota çubuğu, sürüm satırı.
//
// Kurallar (önceki incelemelerden): metinler sarar ya da elips olur (320 dp x 2,0'da taşma yok); durum yalnız
// renkle verilmez (etiket + ikon); kartın TEK birleşik ekran okuyucu etiketi vardır ("PDF, 2,4 MB" dahil);
// dokunma hedefleri en az 48 dp; ham renk yok.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Dosya türü simgesi.
IconData documentKindIcon(DocumentFileKind kind) => switch (kind) {
  DocumentFileKind.pdf => Icons.picture_as_pdf_rounded,
  DocumentFileKind.image => Icons.image_rounded,
  DocumentFileKind.word => Icons.description_rounded,
  DocumentFileKind.excel => Icons.table_chart_rounded,
  DocumentFileKind.other => Icons.insert_drive_file_rounded,
};

/// Dosya türü tonu (anlamsal ayrım; renk tek başına anlam taşımaz, etiket de yazılır).
AppTone documentKindTone(DocumentFileKind kind) => switch (kind) {
  DocumentFileKind.pdf => AppTone.danger,
  DocumentFileKind.image => AppTone.violet,
  DocumentFileKind.word => AppTone.info,
  DocumentFileKind.excel => AppTone.success,
  DocumentFileKind.other => AppTone.neutral,
};

/// Kitle simgesi.
IconData documentAudienceIcon(DocumentAudience audience) => switch (audience) {
  DocumentAudience.residents => Icons.groups_rounded,
  DocumentAudience.board => Icons.gavel_rounded,
  DocumentAudience.managers => Icons.admin_panel_settings_rounded,
  DocumentAudience.unknown => Icons.help_outline_rounded,
};

/// Kategori çipi (nötr; kategori adı yazılır).
class DocumentCategoryChip extends StatelessWidget {
  const DocumentCategoryChip(this.category, {super.key});

  final DocumentCategory category;

  @override
  Widget build(BuildContext context) =>
      InfoChip(category.shortLabel, tone: AppTone.info);
}

/// "Güncellendi" çipi (sakin listesi: sürüm no > 1).
class DocumentUpdatedChip extends StatelessWidget {
  const DocumentUpdatedChip({super.key});

  @override
  Widget build(BuildContext context) => const StatusChip(
    label: 'Güncellendi',
    tone: AppTone.warning,
    icon: Icons.update_rounded,
  );
}

/// Silinmiş belge çipi: "Silindi · 12 gün sonra kalıcı silinir".
class DocumentDeletedChip extends StatelessWidget {
  const DocumentDeletedChip({super.key, this.daysUntilPurge});

  final int? daysUntilPurge;

  /// Kalan gün metni (ekran okuyucu ve çip).
  static String remainingText(int? days) {
    if (days == null) return 'Silindi';
    if (days <= 0) return 'Silindi · bugün kalıcı silinir';
    return 'Silindi · $days gün sonra kalıcı silinir';
  }

  @override
  Widget build(BuildContext context) => StatusChip(
    label: remainingText(daysUntilPurge),
    tone: AppTone.danger,
    icon: Icons.delete_outline_rounded,
  );
}

String _dateOf(DateTime? instant) => formatIstanbulDate(instant);

/// Yönetici listesi kartı: kategori + kitle çipleri, başlık, dosya satırı, sürüm / indirme sayısı. Dokununca
/// ayrıntı penceresi açılır ([onTap]). Metinler sarar; çipler `Wrap` içindedir.
class DocumentAdminCard extends StatelessWidget {
  const DocumentAdminCard({
    super.key,
    required this.document,
    required this.onTap,
    this.showUploader = true,
  });

  final DocumentSummary document;
  final VoidCallback onTap;

  /// Kurul yanıtlarında yükleyen adı yoktur; yine de gösterme kararı çağıranındır.
  final bool showUploader;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final d = document;
    final title = d.title.trim().isEmpty ? 'Başlıksız belge' : d.title.trim();
    final version = d.currentVersion;
    final kind = version?.kind ?? DocumentFileKind.other;
    final fileLine = version == null
        ? null
        : '${version.fileName.isEmpty ? 'Dosya' : version.fileName} · '
              '${documentFileLabel(version.mimeType, version.sizeBytes, version.fileName)}';
    final uploader = showUploader ? d.uploadedByName : null;
    final semantic = StringBuffer('Belge: $title. ${d.category.label}.');
    if (d.isDeleted) {
      semantic.write(
        ' ${DocumentDeletedChip.remainingText(d.daysUntilPurge)}.',
      );
    }
    semantic.write(' Kitle: ${d.audienceSummary}.');
    if (version != null) {
      semantic.write(
        ' ${version.fileName}, ${documentFileLabel(version.mimeType, version.sizeBytes, version.fileName)}.',
      );
    }
    if (d.versionCount > 1) {
      semantic.write(
        ' Sürüm ${d.currentVersion?.versionNo ?? d.versionCount}.',
      );
    }
    if (!d.isDeleted) semantic.write(' ${d.downloadCount} indirme.');
    if (d.updatedAt != null) {
      semantic.write(' Güncelleme: ${_dateOf(d.updatedAt)}.');
    }

    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: semantic.toString(),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              icon: documentKindIcon(kind),
              tone: documentKindTone(kind),
              gap: AppSpace.md,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      DocumentCategoryChip(d.category),
                      if (d.isDeleted)
                        DocumentDeletedChip(daysUntilPurge: d.daysUntilPurge),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: th.titleMedium,
                  ),
                  if (fileLine != null) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      fileLine,
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
                      InfoChip('Kitle: ${d.audienceSummary}'),
                      if (version != null && d.versionCount > 1)
                        InfoChip('v${version.versionNo}'),
                      if (!d.isDeleted) InfoChip('${d.downloadCount} indirme'),
                      if (d.updatedAt != null)
                        InfoChip('Güncelleme: ${_dateOf(d.updatedAt)}'),
                      if (uploader != null && uploader.isNotEmpty)
                        InfoChip('Yükleyen: $uploader'),
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

/// Sakin kartı: kategori + "Güncellendi", başlık, açıklama, dosya satırı, site (birden çok sitede) ve
/// "Aç / Kaydet" düğmesi. Kartın kendisi dokunulamaz; tek eylem düğmedir (çift hedef yok).
class DocumentResidentCard extends StatelessWidget {
  const DocumentResidentCard({
    super.key,
    required this.document,
    required this.onOpen,
    this.showSite = false,
    this.busy = false,
  });

  final ResidentDocument document;

  /// "Aç / Kaydet" düğmesi; [busy] iken devre dışıdır.
  final VoidCallback onOpen;

  /// Birden çok sitesi olan sakinde site adı da gösterilir.
  final bool showSite;

  /// Bu belge şu an indiriliyor (çift dokunma korunur).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final d = document;
    final title = d.title.trim().isEmpty ? 'Başlıksız belge' : d.title.trim();
    final description = d.description.trim();
    final fileLabel = documentFileLabel(d.mimeType, d.sizeBytes, d.fileName);
    final site = d.siteName.trim();
    final semantic = StringBuffer('Belge: $title. ${d.category.label}.');
    if (showSite && site.isNotEmpty) semantic.write(' $site.');
    if (d.isUpdated) semantic.write(' Güncellendi.');
    semantic.write(' $fileLabel.');
    if (d.updatedAt != null) {
      semantic.write(' Güncelleme: ${_dateOf(d.updatedAt)}.');
    }

    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: semantic.toString(),
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconTile(
                    icon: documentKindIcon(d.kind),
                    tone: documentKindTone(d.kind),
                    gap: AppSpace.md,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpace.sm,
                          runSpacing: AppSpace.xs,
                          children: [
                            DocumentCategoryChip(d.category),
                            if (d.isUpdated) const DocumentUpdatedChip(),
                          ],
                        ),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: th.titleMedium,
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: th.bodyMedium?.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpace.sm),
                        Wrap(
                          spacing: AppSpace.sm,
                          runSpacing: AppSpace.xs,
                          children: [
                            InfoChip(fileLabel),
                            if (showSite && site.isNotEmpty) InfoChip(site),
                            if (d.updatedAt != null)
                              InfoChip(_dateOf(d.updatedAt)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          PrimaryActionButton(
            key: ValueKey<String>('document_open_${d.id}'),
            label: 'Aç / Kaydet',
            icon: Icons.open_in_new_rounded,
            variant: AppButtonVariant.tonal,
            loading: busy,
            onPressed: busy ? null : onOpen,
          ),
        ],
      ),
    );
  }
}

/// Site belge alanı kullanımı: "42 MB / 200 MB" + çubuk. Doluluk %90'ı geçince uyarı tonu; ekran okuyucu
/// yüzdeyi söyler. Kota bilinmiyorsa (sunucu `usage` vermedi) hiçbir şey çizilmez.
class DocumentUsageBar extends StatelessWidget {
  const DocumentUsageBar({super.key, required this.usage});

  final DocumentUsage usage;

  @override
  Widget build(BuildContext context) {
    if (!usage.hasQuota) return const SizedBox.shrink();
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final full = usage.fraction >= 0.9;
    final tone = full ? AppTone.warning : AppTone.primary;
    final percent = (usage.fraction * 100).round();
    return Semantics(
      container: true,
      label:
          'Belge alanı: ${usage.label} kullanıldı, yüzde $percent'
          '${full ? '. Alan dolmak üzere' : ''}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Belge alanı',
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Flexible(
                  child: Text(
                    usage.label,
                    key: const ValueKey<String>('document_usage_label'),
                    textAlign: TextAlign.end,
                    style: th.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: full ? tone.ink(p) : p.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                key: const ValueKey<String>('document_usage_bar'),
                value: usage.fraction,
                minHeight: 8,
                backgroundColor: p.surfaceMuted,
                color: tone.hue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Belge sürümü satırı (ayrıntı penceresi): "v3 (güncel) · 2,4 MB · 16.10.2026 13:00", dosya adı ve not.
/// Eylem düğmeleri metnin ALTINDA durur (dar pencerede metni ezmesin).
class DocumentVersionTile extends StatelessWidget {
  const DocumentVersionTile({
    super.key,
    required this.version,
    required this.onDownload,
    this.onDelete,
    this.busy = false,
  });

  final DocumentVersion version;
  final VoidCallback? onDownload;

  /// Yalnız yazma yetkisi olanda ve silinebilir sürümde verilir.
  final VoidCallback? onDelete;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final v = version;
    final head = v.isCurrent ? 'v${v.versionNo} (güncel)' : 'v${v.versionNo}';
    final fileLabel = documentFileLabel(v.mimeType, v.sizeBytes, v.fileName);
    final when = v.completedAt == null
        ? ''
        : ' · ${formatIstanbulDateTime(v.completedAt)}';
    final semantic =
        '$head. ${v.fileName}, $fileLabel$when.'
        '${(v.note ?? '').isEmpty ? '' : ' Not: ${v.note}.'}'
        '${(v.uploadedByName ?? '').isEmpty ? '' : ' Yükleyen: ${v.uploadedByName}.'}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              label: semantic,
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(head, style: th.titleSmall),
                    if (v.fileName.isNotEmpty)
                      Text(v.fileName, style: th.bodyMedium),
                    Text(
                      '$fileLabel$when',
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                    if ((v.note ?? '').isNotEmpty)
                      Text(
                        'Not: ${v.note}',
                        style: th.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                    if ((v.uploadedByName ?? '').isNotEmpty)
                      Text(
                        'Yükleyen: ${v.uploadedByName}',
                        style: th.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                TextButton.icon(
                  key: ValueKey<String>(
                    'document_version_download_${v.versionNo}',
                  ),
                  onPressed: busy ? null : onDownload,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('v${v.versionNo} İndir'),
                  style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                ),
                if (onDelete != null)
                  TextButton.icon(
                    key: ValueKey<String>(
                      'document_version_delete_${v.versionNo}',
                    ),
                    onPressed: busy ? null : onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text('v${v.versionNo} Sil'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 48),
                      foregroundColor: AppTone.danger.ink(p),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
