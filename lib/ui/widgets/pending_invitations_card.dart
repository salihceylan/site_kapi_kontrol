import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Panelde "Bekleyen davet" kartı: çağıranın doğrulanmış e-postasına gelen site davetleri (`GET /app/invitations`).
/// "Kabul et" kişi kaydını hesaba bağlar, "Reddet" daveti kapatır. Davet yoksa ya da yüklenemezse hiçbir şey çizmez
/// (ek bilgidir; panel bozulmaz).
class PendingInvitationsCard extends StatefulWidget {
  const PendingInvitationsCard({super.key, required this.authService, this.onAccepted});

  final AuthService authService;
  final VoidCallback? onAccepted;

  @override
  State<PendingInvitationsCard> createState() => _PendingInvitationsCardState();
}

class _PendingInvitationsCardState extends State<PendingInvitationsCard> {
  List<PendingInvitation> _items = const <PendingInvitation>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await widget.authService.listMyInvitations();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items = const <PendingInvitation>[]);
    }
  }

  Future<void> _answer(PendingInvitation item, {required bool accept}) async {
    setState(() => _busy = true);
    try {
      await widget.authService.answerInvitation(item.id, accept: accept);
      if (!mounted) return;
      AppSnack.show(
        context,
        accept ? '${item.siteName} davetini kabul ettiniz.' : 'Davet reddedildi.',
        kind: AppSnackKind.success,
      );
      if (accept) widget.onAccepted?.call();
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    } catch (_) {
      if (mounted) AppSnack.show(context, 'İşlem yapılamadı. Tekrar deneyin.', kind: AppSnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.lg),
            child: AppCard(
              key: ValueKey<String>('pending_invitation_${item.id}'),
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${item.siteName} sizi davet etti', style: th.titleMedium),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    item.duty == null
                        ? 'Kabul ederseniz kişi kaydınız hesabınıza bağlanır.'
                        : 'Kabul ederseniz kişi kaydınız hesabınıza bağlanır ve "${teamDutyLabel(item.duty!)}" göreviniz için uygulama yetkiniz açılır.',
                    style: th.bodyMedium?.copyWith(color: context.palette.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : () => unawaited(_answer(item, accept: true)),
                        child: const Text('Kabul et'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => unawaited(_answer(item, accept: false)),
                        child: const Text('Reddet'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
