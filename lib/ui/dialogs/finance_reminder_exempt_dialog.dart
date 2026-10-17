import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/reminder_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart' show FinanceDiscardGuard;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Daire ekstresinden "Hatırlatmadan muaf tut" (Faz 4b spec §7). Daire muaf listesinde değilse isteğe bağlı bir nedenle
/// listeye eklenir; listedeyse mevcut neden gösterilir ve "Muafiyeti Kaldır" sunulur. Yalnız yönetici (kurul göremez).
/// Durum sunucudan okunur (liste yüklenemezse neden yazılır ve yeniden denenir; tahmin yürütülmez).
///
/// Başarıda kısa bir sonuç iletisi döner (üst ekran bildirim gösterir); vazgeçilirse `null`.
class FinanceReminderExemptDialog extends StatefulWidget {
  const FinanceReminderExemptDialog({super.key, required this.scope, required this.apartmentId, required this.apartmentLabel});

  final PeopleScope scope;
  final int apartmentId;
  final String apartmentLabel;

  static const int maxReasonLength = 100;

  static Future<String?> show(
    BuildContext context, {
    required PeopleScope scope,
    required int apartmentId,
    required String apartmentLabel,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceReminderExemptDialog(scope: scope, apartmentId: apartmentId, apartmentLabel: apartmentLabel),
    );
  }

  @override
  State<FinanceReminderExemptDialog> createState() => _FinanceReminderExemptDialogState();
}

class _FinanceReminderExemptDialogState extends State<FinanceReminderExemptDialog> with FinanceDiscardGuard {
  final TextEditingController _reason = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  ReminderExclusion? _current;
  String? _loadError;
  String? _error;
  String? _reasonError;
  int _token = 0;

  @override
  bool get closeLocked => _busy;

  @override
  bool get hasUnsavedChanges => _current == null && _reason.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final items = await widget.scope.f4Call((api, t, s) => api.listReminderExclusions(token: t, siteCode: s));
      if (!mounted || token != _token) return;
      ReminderExclusion? found;
      for (final item in items) {
        if (item.apartmentId == widget.apartmentId) found = item;
      }
      setState(() {
        _current = found;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _loadError = financeMessageOf(e, 'Muafiyet durumu yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _add() async {
    if (_busy || _loading || _loadError != null) return;
    final reason = _reason.text.trim();
    if (trimmedCodePoints(reason) > FinanceReminderExemptDialog.maxReasonLength) {
      setState(() => _reasonError = 'Neden en çok ${FinanceReminderExemptDialog.maxReasonLength} karakter olabilir.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _reasonError = null;
    });
    try {
      await widget.scope.f4Call(
        (api, t, s) => api.addReminderExclusion(token: t, siteCode: s, apartmentId: widget.apartmentId, reason: reason),
      );
      if (!mounted) return;
      clearDirty();
      popIfCurrent(context, '${widget.apartmentLabel} borç hatırlatmalarından muaf tutuldu.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = financeWriteMessage(
          e,
          'Daire muaf listesine eklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          hint: kFinanceUncertainStateHint,
        );
      });
      unawaited(_load());
    }
  }

  Future<void> _remove() async {
    if (_busy || _loading || _loadError != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.scope.f4Call(
        (api, t, s) => api.removeReminderExclusion(token: t, siteCode: s, apartmentId: widget.apartmentId),
      );
      if (!mounted) return;
      popIfCurrent(context, '${widget.apartmentLabel} yeniden borç hatırlatmalarına dahil edildi.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = financeWriteMessage(
          e,
          'Muafiyet kaldırılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          hint: kFinanceUncertainStateHint,
        );
      });
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final current = _current;
    final ready = !_loading && _loadError == null;
    final Widget body;
    if (_loading) {
      body = const ListSkeleton(rows: 1);
    } else if (_loadError != null) {
      body = InlineNotice(
        key: const ValueKey<String>('finance_reminder_exempt_load_error'),
        message: _loadError!,
        onRetry: _load,
      );
    } else if (current != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineNotice(
            key: const ValueKey<String>('finance_reminder_exempt_current'),
            tone: AppTone.info,
            message: 'Bu daire borç hatırlatmalarından muaf.${current.reason == null ? '' : ' Neden: ${current.reason}'}',
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Muafiyeti kaldırırsanız daire, uygunluk koşulları sağlandığında sonraki hatırlatma çalıştırmalarına yeniden girer.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Muaf tutulan daireye borç hatırlatma e-postası gönderilmez. İstediğiniz zaman muafiyeti kaldırabilirsiniz.',
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const ValueKey<String>('finance_reminder_exempt_reason'),
            controller: _reason,
            enabled: !_busy,
            maxLength: FinanceReminderExemptDialog.maxReasonLength,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                characterCounter(context, trimmedCodePoints(_reason.text), FinanceReminderExemptDialog.maxReasonLength),
            onChanged: (_) => setState(() => _reasonError = null),
            decoration: InputDecoration(
              labelText: 'Neden (isteğe bağlı)',
              prefixIcon: const Icon(Icons.notes_rounded),
              errorText: _reasonError,
            ),
          ),
        ],
      );
    }
    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) => handleBlockedPop(didPop),
      child: AppDialog(
        title: 'Hatırlatmadan Muaf Tut',
        subtitle: widget.apartmentLabel,
        icon: Icons.do_not_disturb_on_rounded,
        actions: [
          TextButton(
            key: const ValueKey<String>('finance_reminder_exempt_close'),
            onPressed: _busy ? null : requestClose,
            child: const Text('Vazgeç'),
          ),
          if (ready && current != null)
            ElevatedButton(
              key: const ValueKey<String>('finance_reminder_exempt_remove'),
              onPressed: _busy ? null : _remove,
              child: Text(_busy ? 'Kaldırılıyor...' : 'Muafiyeti Kaldır'),
            )
          else if (ready)
            ElevatedButton(
              key: const ValueKey<String>('finance_reminder_exempt_submit'),
              onPressed: _busy ? null : _add,
              child: Text(_busy ? 'Kaydediliyor...' : 'Muaf Tut'),
            ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) FinanceSubmitError(message: _error!),
            body,
          ],
        ),
      ),
    );
  }
}
