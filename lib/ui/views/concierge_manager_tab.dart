import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/concierge_manage_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

/// Yönetim "Konsiyerj" sekmesi: sitenin konsiyerj talepleri (durum sayaçlı süzgeç, kategori süzgeci), ayrıntıda durum
/// ilerletme ve sakine görünür not. Yönetici / görevli yazar, kurul ([ReservationSite.canWrite] false) SALT OKUR.
///
/// Site değişince liste durumu atılır (eski sitenin yanıtı yeni sitenin ekranına yazılamaz); HATA ASLA "talep yok"
/// demez; modül kapalıysa (403 `MODULE_DISABLED`) açıklayıcı kart çıkar.
class ConciergeManagerTab extends StatefulWidget {
  const ConciergeManagerTab({
    super.key,
    required this.service,
    required this.site,
    this.onOpenModules,
  });

  final ReservationService service;
  final ReservationSite site;
  final VoidCallback? onOpenModules;

  @override
  State<ConciergeManagerTab> createState() => ConciergeManagerTabState();
}

class ConciergeManagerTabState extends State<ConciergeManagerTab>
    implements ReservationReloadable {
  String _status = 'open';
  String? _category;
  Map<ConciergeStatus, int> _counts = const <ConciergeStatus, int>{};
  bool _moduleOff = false;

  late final CursorLoader<ConciergeRecord> _loader = CursorLoader<ConciergeRecord>(
    fetch: (before) async {
      final page = await widget.service.listManagedRequests(
        widget.site.code,
        status: _status == 'all' ? null : _status,
        category: _category,
        limit: 30,
        beforeId: before,
      );
      if (before == null) {
        _counts = page.counts;
        _moduleOff = false;
      }
      return (items: page.items, next: page.nextBeforeId);
    },
    keyOf: (item) => item.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback:
        'Talepler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
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
  void didUpdateWidget(ConciergeManagerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        !identical(oldWidget.service, widget.service)) {
      _counts = const <ConciergeStatus, int>{};
      _moduleOff = false;
      _resetList();
    }
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() => _loader.reload();

  void _resetList() {
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _setFilter(VoidCallback change) {
    setState(change);
    _resetList();
  }

  Future<void> _open(ConciergeRecord record) async {
    final changed = await ConciergeManageDialog.show(
      context,
      service: widget.service,
      site: widget.site,
      record: record,
    );
    if (changed && mounted) unawaited(_loader.reload());
  }

  int? _openCount() {
    if (_counts.isEmpty) return null;
    return (_counts[ConciergeStatus.yeni] ?? 0) +
        (_counts[ConciergeStatus.hazirlaniyor] ?? 0);
  }

  String _chipLabel(String label, int? count) =>
      count == null ? label : '$label ($count)';

  bool get _filtered => _status != 'open' || _category != null;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    if (_moduleOff) {
      return ReservationModuleOffCard(
        message: 'Modül açılınca sakinlerin konsiyerj talepleri burada görünür.',
        onOpenModules: widget.onOpenModules,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.site.canWrite
              ? 'Sakinlerin konsiyerj taleplerini izleyin; durumunu ilerletin ve sakine görünür not bırakın.'
              : 'Sakinlerin konsiyerj taleplerini izleyin.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Durum', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  ChoiceChip(
                    key: const ValueKey<String>('cncm_status_open'),
                    label: Text(_chipLabel('Açık', _openCount())),
                    selected: _status == 'open',
                    onSelected: (_) => _setFilter(() => _status = 'open'),
                  ),
                  for (final status in ConciergeStatus.known)
                    ChoiceChip(
                      key: ValueKey<String>('cncm_status_${status.apiValue}'),
                      label: Text(_chipLabel(status.label, _counts[status])),
                      selected: _status == status.apiValue,
                      onSelected: (_) => _setFilter(() => _status = status.apiValue),
                    ),
                  ChoiceChip(
                    key: const ValueKey<String>('cncm_status_all'),
                    label: const Text('Tümü'),
                    selected: _status == 'all',
                    onSelected: (_) => _setFilter(() => _status = 'all'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<String>(
                key: ValueKey<String>('cncm_category_${_category ?? ''}'),
                isExpanded: true,
                initialValue: _category ?? '',
                dropdownColor: p.surface,
                style: th.bodyMedium?.copyWith(color: p.text),
                decoration: const InputDecoration(
                  labelText: 'Kategori',
                  prefixIcon: Icon(Icons.category_rounded),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Tüm kategoriler', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  for (final category in ConciergeCategory.values)
                    DropdownMenuItem<String>(
                      value: category.apiValue,
                      child: Text(category.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  final next = (value == null || value.isEmpty) ? null : value;
                  if (next == _category) return;
                  _setFilter(() => _category = next);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: 'Konsiyerj talepleri',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CursorListBody<ConciergeRecord>(
          loader: _loader,
          emptyIcon: Icons.room_service_rounded,
          emptyTitle: _filtered
              ? 'Bu süzgeç için talep bulunamadı.'
              : 'Açık konsiyerj talebi yok.',
          emptyMessage: _filtered ? null : 'Sakinler bir talep açtığında burada görünür.',
          itemBuilder: (context, record) => ConciergeCard(
            record: record,
            showRequester: true,
            onTap: () => unawaited(_open(record)),
          ),
        ),
      ],
    );
  }
}
