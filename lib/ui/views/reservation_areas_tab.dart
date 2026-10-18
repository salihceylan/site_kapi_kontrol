import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/reservation_area_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

/// Yönetim "Alanlar" sekmesi: sitenin ortak alanları (pasifler dahil). Alan EKLE / DÜZENLE / PASİFLEŞTİR yalnız
/// yönetici ve süper kullanıcıda ([ReservationSite.canDefineAreas]) çizilir; görevli ve kurul alanları okur. Alan
/// silinmez, pasife alınır (mevcut rezervasyonlar etkilenmez).
class ReservationAreasTab extends StatefulWidget {
  const ReservationAreasTab({
    super.key,
    required this.service,
    required this.site,
    this.onOpenModules,
  });

  final ReservationService service;
  final ReservationSite site;
  final VoidCallback? onOpenModules;

  @override
  State<ReservationAreasTab> createState() => ReservationAreasTabState();
}

class ReservationAreasTabState extends State<ReservationAreasTab>
    implements ReservationReloadable {
  bool _moduleOff = false;
  int _activeCount = 0;
  final Set<int> _toggling = <int>{};

  late final CursorLoader<ReservationArea> _loader = CursorLoader<ReservationArea>(
    fetch: (_) async {
      final list = await widget.service.listManagedAreas(widget.site.code);
      _activeCount = list.activeCount;
      _moduleOff = false;
      return (items: list.items, next: null);
    },
    keyOf: (area) => area.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback:
        'Alanlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    messageOf: (error, fallback) {
      if (error is ApiException && error.code == 'MODULE_DISABLED') {
        _moduleOff = true;
      }
      return crmMessageOf(error, fallback);
    },
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void didUpdateWidget(ReservationAreasTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        !identical(oldWidget.service, widget.service)) {
      _moduleOff = false;
      _activeCount = 0;
      _toggling.clear();
      _loader.reset();
      unawaited(_loader.reload());
    }
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() => _loader.reload();

  Future<void> _edit(ReservationArea? area) async {
    final saved = await ReservationAreaFormDialog.show(
      context,
      service: widget.service,
      siteCode: widget.site.code,
      area: area,
    );
    if (saved == null || !mounted) return;
    AppSnack.show(
      context,
      area == null ? 'Alan eklendi.' : 'Alan güncellendi.',
      kind: AppSnackKind.success,
    );
    unawaited(_loader.reload());
  }

  Future<void> _toggle(ReservationArea area) async {
    if (_toggling.contains(area.id)) return;
    if (area.isActive) {
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'Alan pasifleştirilsin mi?',
          icon: Icons.pause_circle_outline_rounded,
          tone: AppTone.warning,
          actions: [
            TextButton(
              key: const ValueKey<String>('area_deactivate_keep'),
              onPressed: () => popIfCurrent(dialogContext, false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              key: const ValueKey<String>('area_deactivate_confirm'),
              onPressed: () => popIfCurrent(dialogContext, true),
              child: const Text('Pasifleştir'),
            ),
          ],
          child: Text(
            '${area.label} sakinlere gösterilmez ve yeni rezervasyon alınamaz. Mevcut rezervasyonlar etkilenmez; alanı istediğiniz zaman yeniden etkinleştirebilirsiniz.',
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
        ),
      );
      if (go != true || !mounted) return;
    }
    setState(() => _toggling.add(area.id));
    try {
      await widget.service.updateArea(widget.site.code, area.id, <String, Object?>{
        'is_active': !area.isActive,
      });
      if (!mounted) return;
      setState(() => _toggling.remove(area.id));
      AppSnack.show(
        context,
        area.isActive ? 'Alan pasifleştirildi.' : 'Alan etkinleştirildi.',
        kind: AppSnackKind.success,
      );
      unawaited(_loader.reload());
    } catch (e) {
      if (!mounted) return;
      setState(() => _toggling.remove(area.id));
      AppSnack.show(
        context,
        crmMessageOf(e, 'Alan güncellenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'),
        kind: AppSnackKind.error,
      );
      if (e is ApiException && (e.statusCode == 404 || e.statusCode == 409)) {
        unawaited(_loader.reload());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final site = widget.site;
    if (_moduleOff) {
      return ReservationModuleOffCard(
        message: 'Modül açılınca ortak alanları buradan tanımlayabilirsiniz.',
        onOpenModules: widget.onOpenModules,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          site.canDefineAreas
              ? 'Sakinlerin ayırtabileceği ortak alanları tanımlayın: açık gün ve saatler, dilim süresi, kapasite ve limitler.'
              : 'Sitedeki ortak alanlar ve rezervasyon kuralları.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.md),
        if (site.canDefineAreas) ...[
          PrimaryActionButton(
            key: const ValueKey<String>('rezm_area_add'),
            label: 'Alan Ekle',
            icon: Icons.add_rounded,
            onPressed: () => unawaited(_edit(null)),
          ),
          const SizedBox(height: AppSpace.md),
        ] else if (site.access == ReservationSiteAccess.staff) ...[
          const InlineNotice(
            key: ValueKey<String>('rezm_areas_staff_note'),
            tone: AppTone.info,
            message: 'Alanları yalnızca yönetici tanımlayabilir ve düzenleyebilir.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        SectionHeader(
          title: 'Alanlar',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        if (_loader.loadedOnce && _loader.items.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            '${_loader.items.length} alan, $_activeCount aktif',
            key: const ValueKey<String>('rezm_areas_summary'),
            style: th.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpace.md),
        CursorListBody<ReservationArea>(
          loader: _loader,
          emptyIcon: Icons.meeting_room_rounded,
          emptyTitle: 'Henüz ortak alan tanımlanmamış.',
          emptyMessage: site.canDefineAreas
              ? '"Alan Ekle" ile spor salonu, toplantı odası gibi bir alan tanımlayın.'
              : 'Yönetici bir alan tanımladığında burada görünür.',
          itemBuilder: (context, area) => ReservationAreaCard(
            area: area,
            showStatus: true,
            footer: site.canDefineAreas
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryActionButton(
                        key: ValueKey<String>('rezm_area_edit_${area.id}'),
                        label: 'Düzenle',
                        icon: Icons.edit_rounded,
                        variant: AppButtonVariant.tonal,
                        onPressed: () => unawaited(_edit(area)),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      PrimaryActionButton(
                        key: ValueKey<String>('rezm_area_toggle_${area.id}'),
                        label: area.isActive ? 'Pasifleştir' : 'Etkinleştir',
                        icon: area.isActive
                            ? Icons.pause_circle_outline_rounded
                            : Icons.play_circle_outline_rounded,
                        tone: area.isActive ? AppTone.danger : AppTone.success,
                        variant: AppButtonVariant.outline,
                        loading: _toggling.contains(area.id),
                        onPressed: _toggling.contains(area.id)
                            ? null
                            : () => unawaited(_toggle(area)),
                      ),
                    ],
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
