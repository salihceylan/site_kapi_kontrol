// İş Takibi ekranlarının ortak parçaları (docs/PLATFORM_IS_TAKIBI.md): durum / öncelik çipleri, sakin ve yönetim
// kartları, olay çizgisi ve yorum kutusu.
//
// Kurallar (Belgeler ile aynı): metinler sarar ya da elips olur (320 dp x 2,0'da taşma yok); durum yalnız renkle
// verilmez (etiket + ikon); kartın TEK birleşik ekran okuyucu etiketi vardır; dokunma hedefleri en az 48 dp; ham
// renk yok. Talep metinleri (başlık, açıklama, yorum) günlüğe yazılmaz.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatCrmDate;
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_attachment_parts.dart'
    show WorkPhotoCountChip;

IconData workCategoryIcon(WorkCategory category) => switch (category) {
  WorkCategory.ariza => Icons.build_rounded,
  WorkCategory.bakim => Icons.handyman_rounded,
  WorkCategory.sikayetOneri => Icons.forum_rounded,
  WorkCategory.diger => Icons.assignment_rounded,
};

AppTone workStatusTone(WorkStatus status) => switch (status) {
  WorkStatus.yeni => AppTone.info,
  WorkStatus.islemde => AppTone.primary,
  WorkStatus.beklemede => AppTone.warning,
  WorkStatus.cozuldu => AppTone.success,
  WorkStatus.kapandi => AppTone.neutral,
  WorkStatus.iptal => AppTone.danger,
  WorkStatus.unknown => AppTone.neutral,
};

IconData workStatusIcon(WorkStatus status) => switch (status) {
  WorkStatus.yeni => Icons.fiber_new_rounded,
  WorkStatus.islemde => Icons.engineering_rounded,
  WorkStatus.beklemede => Icons.hourglass_top_rounded,
  WorkStatus.cozuldu => Icons.check_circle_outline_rounded,
  WorkStatus.kapandi => Icons.lock_outline_rounded,
  WorkStatus.iptal => Icons.cancel_outlined,
  WorkStatus.unknown => Icons.help_outline_rounded,
};

AppTone workPriorityTone(WorkPriority priority) => switch (priority) {
  WorkPriority.acil => AppTone.danger,
  WorkPriority.normal => AppTone.info,
  WorkPriority.dusuk => AppTone.neutral,
};

String _dateTime(DateTime? instant) => formatIstanbulDateTime(instant);

/// Durum çipi: ikon + etiket.
class WorkStatusChip extends StatelessWidget {
  const WorkStatusChip(this.status, {super.key});

  final WorkStatus status;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: status.label,
    tone: workStatusTone(status),
    icon: workStatusIcon(status),
  );
}

/// Öncelik çipi (yalnız yönetim görünümü).
class WorkPriorityChip extends StatelessWidget {
  const WorkPriorityChip(this.priority, {super.key});

  final WorkPriority priority;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: 'Öncelik: ${priority.label}',
    tone: workPriorityTone(priority),
    icon: priority == WorkPriority.acil
        ? Icons.priority_high_rounded
        : Icons.flag_outlined,
  );
}

/// "Yeni güncelleme" çipi (sakin listesi: `unread`).
class WorkUpdateChip extends StatelessWidget {
  const WorkUpdateChip({super.key});

  @override
  Widget build(BuildContext context) => const StatusChip(
    label: 'Yeni güncelleme',
    tone: AppTone.warning,
    icon: Icons.notifications_active_rounded,
  );
}

/// "Acil" çipi (sakinin acil işareti).
class WorkUrgentChip extends StatelessWidget {
  const WorkUrgentChip({super.key, this.label = 'Acil'});

  final String label;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: label,
    tone: AppTone.danger,
    icon: Icons.priority_high_rounded,
  );
}

/// Sakin listesi kartı. Dokununca ayrıntı açılır ([onTap]).
class WorkResidentCard extends StatelessWidget {
  const WorkResidentCard({
    super.key,
    required this.item,
    required this.onTap,
    this.showSite = false,
  });

  final WorkResidentItem item;
  final VoidCallback onTap;
  final bool showSite;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final i = item;
    final title = i.title.isEmpty ? 'Başlıksız talep' : i.title;
    final site = i.siteName.trim();
    final semantic = StringBuffer('Talep: $title. Durum: ${i.status.label}.');
    if (i.unread) semantic.write(' Yeni güncelleme var.');
    if (i.urgent) semantic.write(' Acil olarak işaretlendi.');
    semantic.write(' ${i.category.label}. Konum: ${i.locationText}.');
    if (i.attachmentCount > 0) semantic.write(' ${i.attachmentCount} fotoğraf.');
    if (showSite && site.isNotEmpty) semantic.write(' $site.');
    if (i.createdAt != null) {
      semantic.write(' Açılış: ${_dateTime(i.createdAt)}.');
    }
    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: semantic.toString(),
      tone: i.unread ? AppTone.warning : null,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              icon: workCategoryIcon(i.category),
              tone: workStatusTone(i.status),
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
                      WorkStatusChip(i.status),
                      if (i.unread) const WorkUpdateChip(),
                      if (i.urgent) const WorkUrgentChip(),
                      if (i.attachmentCount > 0)
                        WorkPhotoCountChip(i.attachmentCount),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: th.titleMedium,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    '${i.category.label} · ${i.locationText}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: th.bodyMedium?.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      if (showSite && site.isNotEmpty) InfoChip(site),
                      if (i.createdAt != null)
                        InfoChip('Açılış: ${formatIstanbulDate(i.createdAt)}'),
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

/// Yönetim listesi kartı (yönetici / görevli / kurul).
class WorkManagedCard extends StatelessWidget {
  const WorkManagedCard({super.key, required this.item, required this.onTap});

  final WorkManagedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final i = item;
    final title = i.title.isEmpty ? 'Başlıksız talep' : i.title;
    final requester = i.requester.name.trim();
    final assignee = i.assignedTo?.name.trim();
    final assigneeText = i.assignedTo == null
        ? 'Atanmamış'
        : 'Atanan: ${assignee == null || assignee.isEmpty ? 'İsimsiz kişi' : assignee}';
    final due = i.dueDate == null ? null : formatCrmDate(i.dueDate);
    final semantic = StringBuffer(
      'Talep: $title. Durum: ${i.status.label}. Öncelik: ${i.priority.label}.',
    );
    if (i.residentUrgent) semantic.write(' Sakin acil olarak işaretledi.');
    semantic.write(' ${i.category.label}. Konum: ${i.locationText}.');
    if (i.attachmentCount > 0) semantic.write(' ${i.attachmentCount} fotoğraf.');
    if (requester.isNotEmpty) semantic.write(' Açan: $requester.');
    semantic.write(' $assigneeText.');
    if (due != null) semantic.write(' Hedef tarih: $due.');
    if (i.updatedAt != null) {
      semantic.write(' Güncelleme: ${_dateTime(i.updatedAt)}.');
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
              icon: workCategoryIcon(i.category),
              tone: workStatusTone(i.status),
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
                      WorkStatusChip(i.status),
                      if (i.priority != WorkPriority.normal)
                        WorkPriorityChip(i.priority),
                      if (i.residentUrgent)
                        const WorkUrgentChip(label: 'Sakin: acil'),
                      if (i.attachmentCount > 0)
                        WorkPhotoCountChip(i.attachmentCount),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: th.titleMedium,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    '${i.category.label} · ${i.locationText}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: th.bodyMedium?.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      if (requester.isNotEmpty) InfoChip('Açan: $requester'),
                      InfoChip(assigneeText),
                      if (due != null) InfoChip('Hedef: $due'),
                      if (i.updatedAt != null)
                        InfoChip(
                          'Güncelleme: ${formatIstanbulDate(i.updatedAt)}',
                        ),
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

/// Olayın tek satırlık başlığı ("Durum: Yeni → İşlemde").
String workEventTitle(WorkEvent event) {
  String status(String? value) =>
      value == null ? '-' : WorkStatus.fromApi(value).label;
  switch (event.type) {
    case WorkEventType.created:
      return 'Talep açıldı';
    case WorkEventType.statusChanged:
      return event.from == null
          ? 'Durum: ${status(event.to)}'
          : 'Durum: ${status(event.from)} → ${status(event.to)}';
    case WorkEventType.assigned:
      final from = event.fromLabel ?? 'Atanmamış';
      final to = event.toLabel ?? 'Atanmamış';
      return 'Atama: $from → $to';
    case WorkEventType.priorityChanged:
      String priority(String? v) =>
          v == null ? '-' : WorkPriority.fromApi(v).label;
      return 'Öncelik: ${priority(event.from)} → ${priority(event.to)}';
    case WorkEventType.dueDateChanged:
      final from = workDateText(event.from) ?? 'yok';
      final to = workDateText(event.to) ?? 'kaldırıldı';
      return 'Hedef tarih: $from → $to';
    case WorkEventType.comment:
      return event.internal ? 'İç not' : 'Yorum';
    case WorkEventType.attachmentAdded:
      return 'Fotoğraf eklendi';
    case WorkEventType.attachmentRemoved:
      return 'Fotoğraf kaldırıldı';
    case WorkEventType.unknown:
      return 'Güncelleme';
  }
}

IconData _eventIcon(WorkEvent event) => switch (event.type) {
  WorkEventType.created => Icons.add_circle_outline_rounded,
  WorkEventType.statusChanged => Icons.swap_horiz_rounded,
  WorkEventType.assigned => Icons.person_add_alt_1_rounded,
  WorkEventType.priorityChanged => Icons.flag_outlined,
  WorkEventType.dueDateChanged => Icons.event_rounded,
  WorkEventType.comment =>
    event.internal ? Icons.lock_outline_rounded : Icons.chat_bubble_outline,
  WorkEventType.attachmentAdded => Icons.add_photo_alternate_outlined,
  WorkEventType.attachmentRemoved => Icons.hide_image_outlined,
  WorkEventType.unknown => Icons.circle_outlined,
};

/// Olayı yapan: sakin kendi talebinde "Siz", yönetim görünümünde ad; ad yoksa rol.
String workEventActor(WorkEvent event, {required bool selfIsResident}) {
  if (event.byResident) {
    if (selfIsResident) return 'Siz';
    final name = event.actorName?.trim() ?? '';
    return name.isEmpty ? 'Sakin' : name;
  }
  final name = event.actorName?.trim() ?? '';
  if (name.isNotEmpty) return name;
  return switch (event.actorKind) {
    'staff' => 'Görevli',
    'manager' => 'Yönetici',
    _ => 'Yönetim',
  };
}

/// Durum çizgisi: olaylar eskiden yeniye, solda dikey çizgi ve düğüm. İç notlar "İç" etiketiyle ayrışır.
class WorkEventTimeline extends StatelessWidget {
  const WorkEventTimeline({
    super.key,
    required this.events,
    this.selfIsResident = false,
  });

  final List<WorkEvent> events;
  final bool selfIsResident;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    if (events.isEmpty) {
      return Text(
        'Henüz kayıt yok.',
        style: th.bodyMedium?.copyWith(color: context.palette.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final event in events)
          _EventTile(event: event, selfIsResident: selfIsResident),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.selfIsResident});

  final WorkEvent event;
  final bool selfIsResident;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final actor = workEventActor(event, selfIsResident: selfIsResident);
    final title = workEventTitle(event);
    final body = event.body?.trim() ?? '';
    final when = _dateTime(event.createdAt);
    final tone = event.internal ? AppTone.warning : AppTone.primary;
    final semantic = StringBuffer(
      '${event.internal ? 'İç not, yalnız yönetim görür. ' : ''}$title. $actor.',
    );
    if (body.isNotEmpty) semantic.write(' $body.');
    if (event.createdAt != null) semantic.write(' $when.');
    return Semantics(
      container: true,
      label: semantic.toString(),
      child: ExcludeSemantics(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.only(
                left: AppSpace.lg,
                bottom: AppSpace.lg,
              ),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: p.border, width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(_eventIcon(event), size: 18, color: tone.ink(p)),
                      Text(title, style: th.titleSmall),
                      if (event.internal) const InfoChip('İç'),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(body, style: th.bodyMedium),
                  ],
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    event.createdAt == null ? actor : '$actor · $when',
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tone.hue,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.surface, width: 2),
                ),
                child: const SizedBox(width: 14, height: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "n/max" sayacı (aşımda kırmızı + kalın; ekran okuyucu aşımı söyler).
Widget workCounter(BuildContext context, int length, int max) {
  final p = context.palette;
  final over = length > max;
  return Semantics(
    liveRegion: over,
    label: over
        ? '$length karakter; en çok $max olabilir, sınır aşıldı'
        : '$length / $max karakter',
    child: ExcludeSemantics(
      child: Text(
        '$length/$max',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: over ? AppTone.danger.ink(p) : p.textSecondary,
          fontWeight: over ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    ),
  );
}

/// Yorum yazma kutusu: 1-1000 karakter, gönderim sürerken / hız sınırı kilidinde düğme kapalı. Başarıda
/// ([onSubmit] true döner) alan temizlenir; hatada metin KORUNUR (yeniden denemede aynı idempotency anahtarı
/// kullanılır). [header] kutunun üstüne konan seçenek (örn. iç not / herkese açık).
class WorkCommentBox extends StatefulWidget {
  const WorkCommentBox({
    super.key,
    required this.onSubmit,
    this.busy = false,
    this.locked = false,
    this.keyPrefix = 'work_comment',
    this.label = 'Yorumunuz',
    this.sendLabel = 'Yorum Gönder',
    this.header,
  });

  final Future<bool> Function(String text) onSubmit;
  final bool busy;
  final bool locked;
  final String keyPrefix;
  final String label;
  final String sendLabel;
  final Widget? header;

  @override
  State<WorkCommentBox> createState() => _WorkCommentBoxState();
}

class _WorkCommentBoxState extends State<WorkCommentBox> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (widget.busy || widget.locked) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    FocusScope.of(context).unfocus();
    final ok = await widget.onSubmit(_text.text.trim());
    if (ok && mounted) {
      _text.clear();
      _formKey.currentState?.reset();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) ...[
            widget.header!,
            const SizedBox(height: AppSpace.md),
          ],
          TextFormField(
            key: ValueKey<String>('${widget.keyPrefix}_field'),
            controller: _text,
            enabled: !widget.busy,
            minLines: 2,
            maxLines: 5,
            maxLength: kWorkCommentMax,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => workCounter(
                  context,
                  _text.text.runes.length,
                  kWorkCommentMax,
                ),
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: widget.label,
              alignLabelWithHint: true,
            ),
            validator: (value) {
              final length = (value ?? '').trim().runes.length;
              if (length < 1) return 'Yorum boş olamaz.';
              if (length > kWorkCommentMax) {
                return 'Yorum en çok $kWorkCommentMax karakter olabilir.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: ValueKey<String>('${widget.keyPrefix}_send'),
            label: widget.sendLabel,
            icon: Icons.send_rounded,
            variant: AppButtonVariant.tonal,
            loading: widget.busy,
            onPressed: (widget.busy || widget.locked)
                ? null
                : () => unawaited(_send()),
          ),
        ],
      ),
    );
  }
}
