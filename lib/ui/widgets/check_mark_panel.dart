// Kontrol izi bileşenleri (P2-20; migration 110): gider ve dekont ayrıntısında "Kontrol edildi - <kim>, <tarih>" rozeti ve
// yönetici için işaretleme düğmesi. Muhasebeci ROLÜ yoktur; işareti siteyi yöneten kullanıcı koyar ve kaldırır (kurul yalnız görür).
// Durum gösterimi `StatusDot` (nokta + metin; docs/TASARIM_DILI.md §5): anlam renkte değil metindedir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/check_mark.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';

/// "Kontrol edildi - Ayşe Yönetici, 29.10.2026 14:30" (ad yoksa: "Kontrol edildi - 29.10.2026 14:30"); iz yoksa "Henüz kontrol edilmedi".
String checkMarkLabel(CheckMark? mark) {
  if (mark == null) return 'Henüz kontrol edilmedi';
  final when = formatIstanbulDateTime(mark.at);
  return mark.byName == null ? 'Kontrol edildi - $when' : 'Kontrol edildi - ${mark.byName}, $when';
}

/// Yalnız rozet: kontrol edilmişse yeşil nokta + "Kontrol edildi - kim, tarih", edilmemişse nötr nokta + "Henüz kontrol edilmedi".
class CheckMarkBadge extends StatelessWidget {
  const CheckMarkBadge({super.key, required this.mark});

  final CheckMark? mark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: checkMarkLabel(mark),
      child: ExcludeSemantics(
        child: StatusDot(
          key: const ValueKey<String>('check_mark_badge'),
          label: checkMarkLabel(mark),
          tone: mark == null ? AppTone.neutral : AppTone.success,
          maxLines: null,
        ),
      ),
    );
  }
}

/// Rozet + (yazma yetkisi varsa) işaretleme / kaldırma düğmesi. Sunucu çağrısı [onSet] / [onClear] ile verilir ve yeni izi (kaldırmada null)
/// döndürür; hata ekranı bozmaz, düğmenin altında bildirilir. [mark] dışarıdan (ayrıntı yeniden yüklenince) değişirse panel onu alır.
class CheckMarkPanel extends StatefulWidget {
  const CheckMarkPanel({
    super.key,
    required this.mark,
    required this.canWrite,
    required this.onSet,
    required this.onClear,
    this.hint,
    this.onChanged,
  });

  final CheckMark? mark;

  /// false: kurul (salt okunur); düğme çizilmez.
  final bool canWrite;

  final Future<CheckMark?> Function() onSet;
  final Future<CheckMark?> Function() onClear;

  /// Başlığın altındaki kısa açıklama (ör. "Onay ya da iptal kararından ayrıdır").
  final String? hint;

  /// İşaret konunca ya da kaldırılınca (yeni iz; kaldırmada null).
  final ValueChanged<CheckMark?>? onChanged;

  @override
  State<CheckMarkPanel> createState() => _CheckMarkPanelState();
}

class _CheckMarkPanelState extends State<CheckMarkPanel> {
  late CheckMark? _mark = widget.mark;
  bool _busy = false;
  String? _error;

  @override
  void didUpdateWidget(CheckMarkPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mark != widget.mark) _mark = widget.mark;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final clearing = _mark != null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = clearing ? await widget.onClear() : await widget.onSet();
      if (!mounted) return;
      setState(() {
        _mark = next;
        _busy = false;
      });
      widget.onChanged?.call(next);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = financeMessageOf(
          e,
          clearing
              ? 'Kontrol işareti kaldırılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'
              : 'Kontrol işareti konamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final marked = _mark != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, container: true, child: Text('Muhasebe kontrolü', style: th.titleSmall)),
        if (widget.hint != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(widget.hint!, style: th.bodySmall?.copyWith(color: p.textSecondary)),
          ),
        const SizedBox(height: AppSpace.xs),
        CheckMarkBadge(mark: _mark),
        if (widget.canWrite) ...[
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PrimaryActionButton(
              key: const ValueKey<String>('check_mark_toggle'),
              label: marked ? 'Kontrol İşaretini Kaldır' : 'Kontrol Edildi Olarak İşaretle',
              icon: marked ? Icons.remove_done_rounded : Icons.done_all_rounded,
              variant: marked ? AppButtonVariant.outline : AppButtonVariant.tonal,
              expand: false,
              loading: _busy,
              onPressed: _busy ? null : () => unawaited(_toggle()),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpace.sm),
          InlineNotice(key: const ValueKey<String>('check_mark_error'), message: _error!),
        ],
      ],
    );
  }
}
