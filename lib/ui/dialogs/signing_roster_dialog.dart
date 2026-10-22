import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_management.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;

/// Karar Defteri: toplantı katılım / imza listesi. Her daire için imza hakkı sahibi: aktif vekil varsa vekil
/// ("Daire 5 - vekil: Ali Y. (malik: Veli K.)"), yoksa malik. Bu liste toplantı tarihine göre (bugün) hesaplanır.
/// Vekalet kaydı iç kayıttır; resmi genel kurulda yazılı vekaletname gerekebilir.
class SigningRosterDialog extends StatefulWidget {
  const SigningRosterDialog({super.key, required this.authService, required this.siteCode, this.service});

  final AuthService authService;
  final int siteCode;
  final ApartmentManagementService? service;

  static Future<void> show(BuildContext context, {required AuthService authService, required int siteCode, ApartmentManagementService? service}) {
    return showDialog<void>(
      context: context,
      builder: (_) => SigningRosterDialog(authService: authService, siteCode: siteCode, service: service),
    );
  }

  @override
  State<SigningRosterDialog> createState() => _SigningRosterDialogState();
}

class _SigningRosterDialogState extends State<SigningRosterDialog> {
  late final ApartmentManagementService _service = widget.service ?? ApartmentManagementService(authService: widget.authService);
  SigningRoster? _roster;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final roster = await _service.signingRoster(widget.siteCode);
      if (mounted) setState(() => _roster = roster);
    } catch (e) {
      if (mounted) setState(() => _error = crmMessageOf(e, 'İmza hakkı listesi yüklenemedi.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final roster = _roster;
    return AppDialog(
      title: 'İmza hakkı sahipleri',
      subtitle: roster == null ? null : 'Tarih: ${roster.date}',
      icon: Icons.draw_rounded,
      actions: [TextButton(onPressed: () => popIfCurrent(context), child: const Text('Kapat'))],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) InlineNotice(message: _error!, onRetry: _load),
          if (roster == null && _error == null) const LinearProgressIndicator(),
          if (roster != null && roster.items.isEmpty) Text('Daire kaydı yok.', style: th.bodyMedium),
          if (roster != null)
            for (final item in roster.items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.labelText, style: th.bodyMedium),
                    if ((item.boardProxyName ?? '').isNotEmpty)
                      Text('Kurul üyeliği vekili: ${item.boardProxyName}', style: th.bodySmall?.copyWith(color: context.palette.textSecondary)),
                  ],
                ),
              ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Vekalet yoksa imza hakkı maliktedir; aynı daire için tek kişi imzalar. Vekalet kaydı iç kayıttır; resmi genel kurulda yazılı vekaletname gerekebilir.',
            style: th.bodySmall?.copyWith(color: context.palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
