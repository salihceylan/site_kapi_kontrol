// Sakin rezervasyon ayrıntısı (docs/PLATFORM_REZERVASYON.md): alan, zaman, durum, notunuz ve yönetimin kararı / notu.
// Açılışta ayrıntı yeniden çekilir (GET yazmaz) ve yanıt `unread` ise `seen` çağrılır: rozet söner (İş Takibi sakin
// ayrıntısıyla aynı akış; görüldü hatası sessizdir, rozet kalır ve sonraki açılışta yeniden denenir).
//
// Pencere salt okurdur: iptal listedeki karttan yapılır. Görüldü işaretlendi ya da kayıt kalkmışsa `true` ile kapanır
// (liste yenilenir). Not ve gerekçe metinleri günlüğe yazılmaz.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/views/reservation_controllers.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

class ReservationResidentDetailDialog extends StatefulWidget {
  const ReservationResidentDetailDialog({
    super.key,
    required this.service,
    required this.record,
  });

  final ReservationService service;
  final ReservationRecord record;

  /// Pencere kapanınca listenin yenilenmesi gerekiyorsa (görüldü işaretlendi, kayıt kalkmış) true döner.
  static Future<bool> show(
    BuildContext context, {
    required ReservationService service,
    required ReservationRecord record,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          ReservationResidentDetailDialog(service: service, record: record),
    );
    return changed ?? false;
  }

  @override
  State<ReservationResidentDetailDialog> createState() =>
      _ReservationResidentDetailDialogState();
}

class _ReservationResidentDetailDialogState
    extends State<ReservationResidentDetailDialog> {
  late final ReservationResidentDetailController _c =
      ReservationResidentDetailController(
        service: widget.service,
        initial: widget.record,
      );

  @override
  void initState() {
    super.initState();
    unawaited(_c.load());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _close() => popIfCurrent<bool>(context, _c.changed);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => AppDialog(
          title: 'Rezervasyon Ayrıntısı',
          subtitle: _c.record.siteName.isEmpty ? null : _c.record.siteName,
          icon: Icons.event_available_rounded,
          actions: [
            TextButton(
              key: const ValueKey<String>('rez_detail_close'),
              onPressed: _close,
              child: const Text('Kapat'),
            ),
          ],
          child: _content(context),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    if (_c.moduleClosed) {
      return const InlineNotice(
        key: ValueKey<String>('rez_detail_module_off'),
        tone: AppTone.warning,
        message: 'Rezervasyon ve Konsiyerj bu site için kapalı.',
      );
    }
    if (_c.gone) {
      return const InlineNotice(
        key: ValueKey<String>('rez_detail_gone'),
        message:
            'Rezervasyon bulunamadı ya da erişiminiz yok. Listeyi yenileyip tekrar deneyin.',
      );
    }
    final r = _c.record;
    final apartment = r.apartment?.label.trim() ?? '';
    final deadline = r.cancelDeadline;
    final cancelledBy = reservationCancelledByText(r.cancelledBy, selfView: true);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_c.loadError != null) ...[
          InlineNotice(message: _c.loadError!, onRetry: _c.load),
          const SizedBox(height: AppSpace.md),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            ReservationStatusChip(r.status),
            if (r.unread) const ReservationUpdateChip(),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Semantics(
          header: true,
          child: Text(r.areaLabel, style: th.titleMedium),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          '${reservationWhenText(r)} · ${r.slotCount} dilim',
          style: th.bodyMedium?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.xl,
          runSpacing: AppSpace.sm,
          children: [
            if (apartment.isNotEmpty)
              CrmInfoLine(label: 'Daire', value: apartment),
            CrmInfoLine(
              label: 'Oluşturma',
              value: formatIstanbulDateTime(r.createdAt),
            ),
            if (r.status.isActive && deadline != null)
              CrmInfoLine(
                label: 'Son iptal zamanı',
                value: formatIstanbulDateTime(deadline),
              ),
          ],
        ),
        if (r.note != null) ...[
          const SizedBox(height: AppSpace.md),
          CrmInfoLine(label: 'Notunuz', value: r.note!),
        ],
        if (r.decisionNote != null) ...[
          const SizedBox(height: AppSpace.md),
          CrmInfoLine(label: 'Yönetim notu', value: r.decisionNote!),
        ],
        if (cancelledBy != null && r.status == ReservationStatus.iptal) ...[
          const SizedBox(height: AppSpace.md),
          Text(
            cancelledBy,
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ],
    );
  }
}
