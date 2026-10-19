// Sakin konsiyerj talebi ayrıntısı (docs/PLATFORM_REZERVASYON.md): kategori, istenen zaman, notunuz, durum ve
// yönetimin sakine görünür notu. Açılışta ayrıntı yeniden çekilir (GET yazmaz) ve yanıt `unread` ise `seen` çağrılır:
// rozet söner (İş Takibi sakin ayrıntısıyla aynı akış; görüldü hatası sessizdir, rozet kalır ve sonraki açılışta
// yeniden denenir).
//
// Pencere salt okurdur: iptal listedeki karttan yapılır. Görüldü işaretlendi ya da kayıt kalkmışsa `true` ile kapanır
// (liste yenilenir). Talep metinleri günlüğe yazılmaz.
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

class ConciergeResidentDetailDialog extends StatefulWidget {
  const ConciergeResidentDetailDialog({
    super.key,
    required this.service,
    required this.record,
  });

  final ReservationService service;
  final ConciergeRecord record;

  /// Pencere kapanınca listenin yenilenmesi gerekiyorsa (görüldü işaretlendi, kayıt kalkmış) true döner.
  static Future<bool> show(
    BuildContext context, {
    required ReservationService service,
    required ConciergeRecord record,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          ConciergeResidentDetailDialog(service: service, record: record),
    );
    return changed ?? false;
  }

  @override
  State<ConciergeResidentDetailDialog> createState() =>
      _ConciergeResidentDetailDialogState();
}

class _ConciergeResidentDetailDialogState
    extends State<ConciergeResidentDetailDialog> {
  late final ConciergeResidentDetailController _c =
      ConciergeResidentDetailController(
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
          title: 'Talep Ayrıntısı',
          subtitle: _c.record.siteName.isEmpty ? null : _c.record.siteName,
          icon: conciergeCategoryIcon(_c.record.category),
          actions: [
            TextButton(
              key: const ValueKey<String>('cnc_detail_close'),
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
    final th = Theme.of(context).textTheme;
    if (_c.moduleClosed) {
      return const InlineNotice(
        key: ValueKey<String>('cnc_detail_module_off'),
        tone: AppTone.warning,
        message: 'Rezervasyon ve Konsiyerj bu site için kapalı.',
      );
    }
    if (_c.gone) {
      return const InlineNotice(
        key: ValueKey<String>('cnc_detail_gone'),
        message:
            'Talep bulunamadı ya da erişiminiz yok. Listeyi yenileyip tekrar deneyin.',
      );
    }
    final r = _c.record;
    final apartment = r.apartment?.label.trim() ?? '';
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
            ConciergeStatusChip(r.status),
            if (r.unread) const ReservationUpdateChip(),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Semantics(
          header: true,
          child: Text(r.category.label, style: th.titleMedium),
        ),
        if (r.note != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(r.note!, style: th.bodyMedium),
        ],
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.xl,
          runSpacing: AppSpace.sm,
          children: [
            if (r.requestedFor != null)
              CrmInfoLine(
                label: 'İstenen zaman',
                value: formatIstanbulDateTime(r.requestedFor),
              ),
            if (apartment.isNotEmpty)
              CrmInfoLine(label: 'Daire', value: apartment),
            CrmInfoLine(
              label: 'Talep zamanı',
              value: formatIstanbulDateTime(r.createdAt),
            ),
            CrmInfoLine(
              label: 'Son güncelleme',
              value: formatIstanbulDateTime(r.updatedAt),
            ),
            if (r.closedAt != null)
              CrmInfoLine(
                label: 'Kapanış',
                value: formatIstanbulDateTime(r.closedAt),
              ),
          ],
        ),
        if (r.staffNote != null) ...[
          const SizedBox(height: AppSpace.md),
          CrmInfoLine(label: 'Yönetim notu', value: r.staffNote!),
        ],
      ],
    );
  }
}
