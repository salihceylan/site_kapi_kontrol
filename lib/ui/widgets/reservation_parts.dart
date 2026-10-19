// Rezervasyon ve Konsiyerj ekranlarının ortak parçaları (docs/PLATFORM_REZERVASYON.md): durum çipleri, alan /
// rezervasyon / talep kartları, "modül kapalı" kartı ve karakter sayacı.
//
// Kurallar (İş Takibi ile aynı): metinler sarar ya da elips olur (320 dp x 2,0'da taşma yok); durum yalnız renkle
// verilmez (etiket + ikon); kartın TEK birleşik ekran okuyucu etiketi vardır (içindeki düğmeler erişilebilir kalır);
// dokunma hedefleri en az 48 dp; ham renk yok. Not, gerekçe ve talep metinleri günlüğe yazılmaz. Zamanlar İstanbul
// saatiyle gösterilir; `date` / `start` / `end` sunucunun İstanbul yerel metnidir.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

AppTone reservationStatusTone(ReservationStatus status) => switch (status) {
  ReservationStatus.beklemede => AppTone.warning,
  ReservationStatus.onaylandi => AppTone.success,
  ReservationStatus.reddedildi => AppTone.danger,
  ReservationStatus.iptal => AppTone.neutral,
  ReservationStatus.tamamlandi => AppTone.info,
  ReservationStatus.unknown => AppTone.neutral,
};

IconData reservationStatusIcon(ReservationStatus status) => switch (status) {
  ReservationStatus.beklemede => Icons.hourglass_top_rounded,
  ReservationStatus.onaylandi => Icons.check_circle_outline_rounded,
  ReservationStatus.reddedildi => Icons.block_rounded,
  ReservationStatus.iptal => Icons.cancel_outlined,
  ReservationStatus.tamamlandi => Icons.task_alt_rounded,
  ReservationStatus.unknown => Icons.help_outline_rounded,
};

AppTone conciergeStatusTone(ConciergeStatus status) => switch (status) {
  ConciergeStatus.yeni => AppTone.info,
  ConciergeStatus.hazirlaniyor => AppTone.primary,
  ConciergeStatus.tamamlandi => AppTone.success,
  ConciergeStatus.iptal => AppTone.neutral,
  ConciergeStatus.unknown => AppTone.neutral,
};

IconData conciergeStatusIcon(ConciergeStatus status) => switch (status) {
  ConciergeStatus.yeni => Icons.fiber_new_rounded,
  ConciergeStatus.hazirlaniyor => Icons.engineering_rounded,
  ConciergeStatus.tamamlandi => Icons.check_circle_outline_rounded,
  ConciergeStatus.iptal => Icons.cancel_outlined,
  ConciergeStatus.unknown => Icons.help_outline_rounded,
};

IconData conciergeCategoryIcon(ConciergeCategory category) => switch (category) {
  ConciergeCategory.paketTeslim => Icons.inventory_2_rounded,
  ConciergeCategory.misafirHazirlik => Icons.people_alt_rounded,
  ConciergeCategory.temizlik => Icons.cleaning_services_rounded,
  ConciergeCategory.tasima => Icons.local_shipping_rounded,
  ConciergeCategory.diger => Icons.room_service_rounded,
};

/// "20.10.2026 · 18:00-19:00": sunucunun İstanbul yerel metni; eksikse zaman damgasından İstanbul saatiyle türetilir.
String reservationWhenText(ReservationRecord record) {
  final date = reservationDateText(record.date) ?? formatIstanbulDate(record.startsAt);
  final start = record.start.isNotEmpty ? record.start : formatIstanbulTime(record.startsAt);
  final end = record.end.isNotEmpty ? record.end : formatIstanbulTime(record.endsAt);
  return '$date · $start-$end';
}

/// Rezervasyon durum çipi: ikon + etiket.
class ReservationStatusChip extends StatelessWidget {
  const ReservationStatusChip(this.status, {super.key});

  final ReservationStatus status;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: status.label,
    tone: reservationStatusTone(status),
    icon: reservationStatusIcon(status),
  );
}

/// Konsiyerj durum çipi: ikon + etiket.
class ConciergeStatusChip extends StatelessWidget {
  const ConciergeStatusChip(this.status, {super.key});

  final ConciergeStatus status;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: status.label,
    tone: conciergeStatusTone(status),
    icon: conciergeStatusIcon(status),
  );
}

/// "Yeni güncelleme" çipi (sakin listesi: `unread`; İş Takibi'ndeki çiple aynı görünüm).
class ReservationUpdateChip extends StatelessWidget {
  const ReservationUpdateChip({super.key});

  @override
  Widget build(BuildContext context) => const StatusChip(
    label: 'Yeni güncelleme',
    tone: AppTone.warning,
    icon: Icons.notifications_active_rounded,
  );
}

/// Sekme etiketindeki okunmamış sayısı (uyarı tonu: "Yeni güncelleme" çipiyle aynı aile; soluk zemin + ton mürekkebi,
/// >= 4,5:1). 99'dan büyük sayılar "99+" yazılır; ekran okuyucuya "n yeni güncelleme" olarak okunur.
class ReservationUnreadBadge extends StatelessWidget {
  const ReservationUnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const tone = AppTone.warning;
    final label = count > 99 ? '99+' : '$count';
    return Semantics(
      label: '$count yeni güncelleme',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tone.tint(p),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm,
              vertical: AppSpace.xs / 2,
            ),
            child: Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tone.ink(p),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Süzgecin gizlediği okunmamış kayıt uyarısı. Sekme rozetindeki sayı süzgeçten bağımsızdır (reddedilen ya da yönetimce
/// iptal edilen rezervasyon "Geçmiş"te, tamamlanan talep "Kapanan"dadır) ve rozet ancak kayıt açılınca söner; bu yüzden
/// "Tümünü göster" süzgeci "Tümü"ne alır. İş Takibi'ndeki "yeni güncelleme" uyarısıyla aynı ton ve ikon; düğme tam
/// genişliktir, etiketi sarar / elips olur (320 dp x 2,0'da taşma yok).
class ReservationHiddenUnreadNotice extends StatelessWidget {
  const ReservationHiddenUnreadNotice({
    super.key,
    required this.message,
    required this.onShowAll,
    this.actionKey,
  });

  final String message;
  final VoidCallback onShowAll;

  /// "Tümünü göster" düğmesinin anahtarı.
  final Key? actionKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InlineNotice(
        tone: AppTone.warning,
        icon: Icons.notifications_active_rounded,
        message: message,
      ),
      const SizedBox(height: AppSpace.sm),
      PrimaryActionButton(
        key: actionKey,
        label: 'Tümünü göster',
        icon: Icons.filter_alt_off_rounded,
        variant: AppButtonVariant.tonal,
        onPressed: onShowAll,
      ),
    ],
  );
}

/// "n/max" sayacı (aşımda kırmızı + kalın; ekran okuyucu aşımı söyler).
Widget reservationCounter(BuildContext context, int length, int max) {
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

/// Modül kapalı (403 `MODULE_DISABLED`) açıklayıcı kartı; [onOpenModules] verilirse "Modüller" düğmesi çıkar.
class ReservationModuleOffCard extends StatelessWidget {
  const ReservationModuleOffCard({
    super.key,
    this.message =
        'Yönetim bu özelliği açtığında ortak alan rezervasyonu ve konsiyerj talepleri burada görünür.',
    this.onOpenModules,
  });

  final String message;
  final VoidCallback? onOpenModules;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return EmptyCard(
      key: const ValueKey<String>('reservation_module_off'),
      icon: Icons.event_busy_rounded,
      tone: AppTone.warning,
      title: 'Rezervasyon ve Konsiyerj bu site için kapalı.',
      message: message,
      child: onOpenModules == null
          ? null
          : Column(
              children: [
                Text(
                  'Modüller ekranından açabilir ya da talep edebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: th.bodyMedium,
                ),
                const SizedBox(height: AppSpace.md),
                PrimaryActionButton(
                  key: const ValueKey<String>('reservation_open_modules'),
                  label: 'Modüller',
                  icon: Icons.extension_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: onOpenModules,
                ),
              ],
            ),
    );
  }
}

/// Kurul (salt okur) notu.
class ReservationReadOnlyNote extends StatelessWidget {
  const ReservationReadOnlyNote({super.key});

  @override
  Widget build(BuildContext context) => const InlineNotice(
    key: ValueKey<String>('reservation_read_only_note'),
    tone: AppTone.info,
    icon: Icons.visibility_rounded,
    message:
        'Yönetim kurulu üyesi olarak rezervasyon ve talepleri yalnızca görüntüleyebilirsiniz. Sakinlerin telefon ve kullanıcı bilgileri görünmez.',
  );
}

/// Kart iskeleti: sol rozet, üstte çipler, başlık, alt başlık, ayrıntı satırları ve (varsa) altta eylem alanı.
/// [onTap] verilirse kartın tamamı dokunulur (ayrıntı açar); eylem alanındaki düğmeler kendi dokunuşlarını alır ve
/// ekran okuyucuda ayrı kalır. [semanticLabel] kartın TEK özetidir. [tone] tonlu kart (örn. okunmamış karar: uyarı).
class ReservationCardShell extends StatelessWidget {
  const ReservationCardShell({
    super.key,
    required this.icon,
    required this.iconTone,
    required this.title,
    required this.semanticLabel,
    this.chips = const <Widget>[],
    this.subtitle,
    this.details = const <Widget>[],
    this.footer,
    this.onTap,
    this.tone,
  });

  final IconData icon;
  final AppTone iconTone;
  final String title;
  final String semanticLabel;
  final List<Widget> chips;
  final String? subtitle;
  final List<Widget> details;
  final Widget? footer;
  final VoidCallback? onTap;
  final AppTone? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final subtitle = this.subtitle;
    final footer = this.footer;
    final info = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconTile(icon: icon, tone: iconTone, gap: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (chips.isNotEmpty) ...[
                Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: chips),
                const SizedBox(height: AppSpace.sm),
              ],
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: th.titleMedium,
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  subtitle,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: th.bodyMedium?.copyWith(color: p.textSecondary),
                ),
              ],
              for (final detail in details) ...[
                const SizedBox(height: AppSpace.sm),
                detail,
              ],
            ],
          ),
        ),
      ],
    );
    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      tone: tone,
      semanticLabel: semanticLabel,
      child: footer == null
          ? ExcludeSemantics(child: info)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(child: info),
                const SizedBox(height: AppSpace.md),
                footer,
              ],
            ),
    );
  }
}

Widget _bodyText(BuildContext context, String text, {bool secondary = false}) {
  final th = Theme.of(context).textTheme;
  return Text(
    text,
    style: secondary
        ? th.bodySmall?.copyWith(color: context.palette.textSecondary)
        : th.bodyMedium,
  );
}

/// Ortak alan kartı. Sakin listesinde altta "Rezervasyon Yap" düğmesi ([footer]); yönetim listesinde durum çipi
/// ([showStatus]) ve düzenle / pasifleştir düğmeleri.
class ReservationAreaCard extends StatelessWidget {
  const ReservationAreaCard({
    super.key,
    required this.area,
    this.showSite = false,
    this.showStatus = false,
    this.footer,
  });

  final ReservationArea area;
  final bool showSite;
  final bool showStatus;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final a = area;
    final site = a.siteName.trim();
    final semantic = StringBuffer('Alan: ${a.label}.');
    if (showStatus) semantic.write(a.isActive ? ' Aktif.' : ' Pasif.');
    semantic.write(
      ' Kapasite ${a.capacity}. Dilim ${reservationDurationText(a.slotMinutes)}. ${a.approvalMode.label}.',
    );
    if (showSite && site.isNotEmpty) semantic.write(' $site.');
    final hours = a.hoursLines;
    return ReservationCardShell(
      icon: Icons.meeting_room_rounded,
      iconTone: a.isActive ? AppTone.primary : AppTone.neutral,
      title: a.label,
      subtitle: a.description,
      semanticLabel: semantic.toString(),
      chips: [
        if (showStatus)
          StatusChip(
            label: a.isActive ? 'Aktif' : 'Pasif',
            tone: a.isActive ? AppTone.success : AppTone.neutral,
            icon: a.isActive ? Icons.check_circle_outline_rounded : Icons.pause_circle_outline_rounded,
          ),
        InfoChip(a.approvalMode.label),
      ],
      details: [
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            if (showSite && site.isNotEmpty) InfoChip(site),
            InfoChip('Kapasite: ${a.capacity}'),
            InfoChip('Dilim: ${reservationDurationText(a.slotMinutes)}'),
            InfoChip(
              a.minSlots == a.maxSlots
                  ? '${a.minSlots} dilim'
                  : '${a.minSlots}-${a.maxSlots} dilim',
            ),
            InfoChip('${a.maxDaysAhead} gün önceden'),
          ],
        ),
        if (hours.isEmpty)
          _bodyText(context, 'Açık gün tanımlı değil.', secondary: true)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final line in hours) _bodyText(context, line, secondary: true)],
          ),
      ],
      footer: footer,
    );
  }
}

/// Sakinin kendi rezervasyonu: durum, zaman, notlar ve iptal. İptal süresi dolduysa düğme PASİF ve nedeni yazar.
/// Görülmemiş yönetim kararı (`unread`) "Yeni güncelleme" çipi + uyarı tonuyla gösterilir; [onTap] ayrıntıyı açar.
class MyReservationCard extends StatelessWidget {
  const MyReservationCard({
    super.key,
    required this.record,
    required this.onCancel,
    this.showSite = false,
    this.busy = false,
    this.onTap,
  });

  final ReservationRecord record;
  final VoidCallback onCancel;
  final bool showSite;

  /// Bu kartın iptali sürüyor (düğme yükleniyor).
  final bool busy;

  /// Dokununca ayrıntı penceresi (okunmamış karar görüldü işaretlenir).
  final VoidCallback? onTap;

  /// İptal düğmesinin altındaki açıklama (iptal edilebilirse son iptal zamanı; edilemezse neden).
  String _cancelNote() {
    final r = record;
    final deadline = r.cancelDeadline;
    if (r.canCancel) {
      return deadline == null ? '' : 'Son iptal zamanı: ${formatIstanbulDateTime(deadline)}';
    }
    if (deadline == null) return 'Rezervasyon zamanı geçtiği için iptal edilemez.';
    return 'İptal süresi doldu. Son iptal zamanı ${formatIstanbulDateTime(deadline)} idi; değişiklik için yönetimle iletişime geçin.';
  }

  @override
  Widget build(BuildContext context) {
    final r = record;
    final site = r.siteName.trim();
    final apartment = r.apartment?.label.trim() ?? '';
    final cancelledBy = reservationCancelledByText(r.cancelledBy, selfView: true);
    final semantic = StringBuffer(
      'Rezervasyon: ${r.areaLabel}. ${reservationWhenText(r)}. Durum: ${r.status.label}.',
    );
    if (r.unread) semantic.write(' Yeni güncelleme var.');
    if (showSite && site.isNotEmpty) semantic.write(' $site.');
    if (r.decisionNote != null) semantic.write(' Yönetim notu var.');
    final cancelNote = r.status.isActive ? _cancelNote() : '';
    return ReservationCardShell(
      icon: Icons.event_available_rounded,
      iconTone: reservationStatusTone(r.status),
      title: r.areaLabel,
      subtitle: '${reservationWhenText(r)} · ${r.slotCount} dilim',
      semanticLabel: semantic.toString(),
      tone: r.unread ? AppTone.warning : null,
      onTap: onTap,
      chips: [
        ReservationStatusChip(r.status),
        if (r.unread) const ReservationUpdateChip(),
      ],
      details: [
        if ((showSite && site.isNotEmpty) || apartment.isNotEmpty)
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              if (showSite && site.isNotEmpty) InfoChip(site),
              if (apartment.isNotEmpty) InfoChip(apartment),
            ],
          ),
        if (r.note != null) _bodyText(context, 'Notunuz: ${r.note}'),
        if (r.decisionNote != null) _bodyText(context, 'Yönetim notu: ${r.decisionNote}'),
        if (cancelledBy != null && r.status == ReservationStatus.iptal)
          _bodyText(context, cancelledBy, secondary: true),
      ],
      footer: r.status.isActive
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (cancelNote.isNotEmpty) ...[
                  Text(
                    cancelNote,
                    key: ValueKey<String>('rez_cancel_note_${r.id}'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                ],
                PrimaryActionButton(
                  key: ValueKey<String>('rez_cancel_${r.id}'),
                  label: 'Rezervasyonu İptal Et',
                  icon: Icons.cancel_outlined,
                  tone: AppTone.danger,
                  variant: AppButtonVariant.outline,
                  loading: busy,
                  onPressed: (r.canCancel && !busy) ? onCancel : null,
                ),
              ],
            )
          : null,
    );
  }
}

/// Yönetim listesindeki rezervasyon (yönetici / görevli / kurul). [onDecide] verilmezse (kurul) hiçbir düğme
/// çizilmez; verilirse sunucunun bildirdiği `can_decide` / `can_cancel` bayraklarına göre Onayla, Reddet, İptal Et.
class ManagedReservationCard extends StatelessWidget {
  const ManagedReservationCard({super.key, required this.record, this.onDecide});

  final ReservationRecord record;

  /// `approve | reject | cancel`.
  final void Function(String action)? onDecide;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final requester = r.requester?.name.trim() ?? '';
    final phone = r.requester?.phone;
    final apartment = r.apartment?.label.trim() ?? '';
    final decider = r.decidedBy?.name.trim() ?? '';
    final cancelledBy = reservationCancelledByText(r.cancelledBy);
    final semantic = StringBuffer(
      'Rezervasyon: ${r.areaLabel}. ${reservationWhenText(r)}. Durum: ${r.status.label}.',
    );
    if (requester.isNotEmpty) semantic.write(' Yapan: $requester.');
    if (apartment.isNotEmpty) semantic.write(' $apartment.');
    final decide = onDecide;
    final canApprove = decide != null && r.canDecide;
    final canCancel = decide != null && r.canCancel;
    return ReservationCardShell(
      icon: Icons.event_available_rounded,
      iconTone: reservationStatusTone(r.status),
      title: r.areaLabel,
      subtitle: '${reservationWhenText(r)} · ${r.slotCount} dilim',
      semanticLabel: semantic.toString(),
      chips: [ReservationStatusChip(r.status)],
      details: [
        if (requester.isNotEmpty || apartment.isNotEmpty)
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              if (requester.isNotEmpty) InfoChip('Yapan: $requester'),
              if (apartment.isNotEmpty) InfoChip(apartment),
              if (phone != null) InfoChip('Tel: $phone'),
            ],
          ),
        if (r.note != null) _bodyText(context, 'Not: ${r.note}'),
        if (r.decisionNote != null)
          _bodyText(
            context,
            decider.isEmpty
                ? 'Karar notu: ${r.decisionNote}'
                : 'Karar notu ($decider): ${r.decisionNote}',
          ),
        if (cancelledBy != null && r.status == ReservationStatus.iptal)
          _bodyText(context, cancelledBy, secondary: true),
      ],
      footer: (canApprove || canCancel)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canApprove) ...[
                  PrimaryActionButton(
                    key: ValueKey<String>('rez_approve_${r.id}'),
                    label: 'Onayla',
                    icon: Icons.check_rounded,
                    tone: AppTone.success,
                    variant: AppButtonVariant.tonal,
                    onPressed: () => decide('approve'),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  PrimaryActionButton(
                    key: ValueKey<String>('rez_reject_${r.id}'),
                    label: 'Reddet',
                    icon: Icons.block_rounded,
                    tone: AppTone.danger,
                    variant: AppButtonVariant.outline,
                    onPressed: () => decide('reject'),
                  ),
                ],
                if (canCancel) ...[
                  if (canApprove) const SizedBox(height: AppSpace.sm),
                  PrimaryActionButton(
                    key: ValueKey<String>('rez_cancel_${r.id}'),
                    label: 'İptal Et',
                    icon: Icons.cancel_outlined,
                    tone: AppTone.danger,
                    variant: AppButtonVariant.outline,
                    onPressed: () => decide('cancel'),
                  ),
                ],
              ],
            )
          : null,
    );
  }
}

/// Konsiyerj talebi kartı (sakin ve yönetim). Sakinde [footer] iptal düğmesi ve [onTap] ayrıntı (görülmemiş yönetim
/// güncellemesi `unread` çip + uyarı tonuyla gösterilir, ayrıntıda görüldü işaretlenir); yönetimde [onTap] ayrıntıyı
/// açar ve [showRequester] talebi açanı yazar.
class ConciergeCard extends StatelessWidget {
  const ConciergeCard({
    super.key,
    required this.record,
    this.showSite = false,
    this.showRequester = false,
    this.footer,
    this.onTap,
  });

  final ConciergeRecord record;
  final bool showSite;
  final bool showRequester;
  final Widget? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final site = r.siteName.trim();
    final apartment = r.apartment?.label.trim() ?? '';
    final requester = r.requester?.name.trim() ?? '';
    final wanted = r.requestedFor == null ? null : formatIstanbulDateTime(r.requestedFor);
    final semantic = StringBuffer('Talep: ${r.category.label}. Durum: ${r.status.label}.');
    if (wanted != null) semantic.write(' İstenen zaman: $wanted.');
    if (showRequester && requester.isNotEmpty) semantic.write(' Açan: $requester.');
    if (r.unread) semantic.write(' Yeni güncelleme var.');
    if (showSite && site.isNotEmpty) semantic.write(' $site.');
    if (r.staffNote != null) semantic.write(' Yönetim notu var.');
    return ReservationCardShell(
      icon: conciergeCategoryIcon(r.category),
      iconTone: conciergeStatusTone(r.status),
      title: r.category.label,
      subtitle: wanted == null ? null : 'İstenen zaman: $wanted',
      semanticLabel: semantic.toString(),
      tone: r.unread ? AppTone.warning : null,
      chips: [
        ConciergeStatusChip(r.status),
        if (r.unread) const ReservationUpdateChip(),
      ],
      onTap: onTap,
      details: [
        if (r.note != null) _bodyText(context, r.note!),
        if (r.staffNote != null) _bodyText(context, 'Yönetim notu: ${r.staffNote}'),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            if (showSite && site.isNotEmpty) InfoChip(site),
            if (showRequester && requester.isNotEmpty) InfoChip('Açan: $requester'),
            if (apartment.isNotEmpty) InfoChip(apartment),
            if (r.createdAt != null) InfoChip('Talep: ${formatIstanbulDate(r.createdAt)}'),
          ],
        ),
      ],
      footer: footer,
    );
  }
}

/// Sekme durumlarının ortak yenileme sözleşmesi: sayfa kabuğunun aşağı çekip yenilemesi ve yenile düğmeleri etkin
/// sekmenin listesini yeniden çeker.
abstract interface class ReservationReloadable {
  Future<void> reload();
}
