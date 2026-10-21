// Sakin "Borcum" kartında dekont durumu (Dalga 2 / 2B): bekleyen dekont varsa "İnceleniyor: 1.250,00 ₺" (amber nokta), yönetim karar verdiyse tek seferlik not
// (onay ya da iptal nedeni). Kendi bildirimi yoksa ya da yüklenemezse HİÇBİR ŞEY çizmez (kartı bozmaz).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/payment_notice.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/payment_notice_api.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';

class PaymentNoticeStatusLine extends StatefulWidget {
  const PaymentNoticeStatusLine({super.key, required this.authService, required this.apartmentId});

  final AuthService authService;
  final int apartmentId;

  @override
  State<PaymentNoticeStatusLine> createState() => _PaymentNoticeStatusLineState();
}

class _PaymentNoticeStatusLineState extends State<PaymentNoticeStatusLine> {
  MyNotices? _data;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    paymentNoticeRevision.addListener(_onRevision);
    unawaited(_load());
  }

  @override
  void dispose() {
    paymentNoticeRevision.removeListener(_onRevision);
    ++_token;
    super.dispose();
  }

  void _onRevision() => unawaited(_load());

  Future<void> _load() async {
    final token = ++_token;
    try {
      final data = await PaymentNoticeService.of(widget.authService).run((api, t) => api.listMine(token: t, apartmentId: widget.apartmentId));
      if (mounted && token == _token) setState(() => _data = data);
    } catch (_) {
      // dekont durumu isteğe bağlıdır; kart olduğu gibi kalır
    }
  }

  Future<void> _dismiss() async {
    try {
      await PaymentNoticeService.of(widget.authService).run((api, t) => api.markSeen(token: t));
    } catch (_) {
      // görülmedi işareti sonraki açılışta yeniden denenir
    }
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final decisions = [for (final n in data.items) if (n.unseenDecision) n];
    if (data.pendingTotalMinor <= 0 && decisions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.pendingTotalMinor > 0)
            StatusDot(
              key: const ValueKey<String>('notice_pending_line'),
              label: 'İnceleniyor: ${formatMinor(data.pendingTotalMinor)}',
              tone: AppTone.warning,
              maxLines: null,
            ),
          for (final n in decisions)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      n.status == NoticeStatus.approved
                          ? '${formatMinor(n.amountMinor)} tutarındaki dekontunuz onaylandı.'
                          : '${formatMinor(n.amountMinor)} tutarındaki dekontunuz kabul edilmedi: ${n.rejectReasonText ?? 'Yönetim bildirimi kabul etmedi.'}${n.rejectNote == null ? '' : ' ${n.rejectNote}'}',
                      key: ValueKey<String>('notice_decision_${n.id}'),
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ),
                  TextButton(key: ValueKey<String>('notice_decision_ok_${n.id}'), onPressed: _dismiss, child: const Text('Tamam')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
