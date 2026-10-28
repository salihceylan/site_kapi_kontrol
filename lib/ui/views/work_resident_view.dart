import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/work_item_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/work_resident_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

/// Sakin "Taleplerim" ekranı (İş Takibi, `work_tracking` modülü): kendi arıza / bakım / talep kayıtları, durum
/// rozeti, "yeni güncelleme" göstergesi, "Yeni Talep" formu ve ayrıntı (durum çizgisi, yorum, kendi `yeni`
/// talebini iptal).
///
/// - Birden çok sitede ([sites] >= 2) site süzgeci çıkar ve kartlarda site adı görünür.
/// - Yarışlar: süzgeç / site değişimi sırasında eski imleçle gelen sayfa listeye eklenmez ([CursorLoader]); dispose
///   sonrası yanıt yok sayılır; HATA ASLA "talep yok" demez (liste boşken hata + "Tekrar Dene"), boş durum yalnız
///   gerçekten boşken çizilir.
/// - Modül kapalıysa (403 `MODULE_DISABLED`) liste yerine "bu site için kapalı" kartı çıkar.
/// - [WorkResidentViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class WorkResidentView extends StatefulWidget {
  const WorkResidentView({
    super.key,
    required this.authService,
    this.service,
    this.sites = const <PeopleSite>[],
    this.photoPicker,
  });

  final AuthService authService;
  final WorkTrackingService? service;

  /// Sakinin talep açabileceği (modül açık) siteler.
  final List<PeopleSite> sites;

  /// Fotoğraf seçici (testlerde sahte); null ise gerçek `file_picker`.
  final WorkPhotoPicker? photoPicker;

  @override
  State<WorkResidentView> createState() => WorkResidentViewState();
}

class WorkResidentViewState extends State<WorkResidentView> {
  static const int _allSites = 0;

  String _status = 'open';
  int? _siteFilter;
  int _unreadUpdates = 0;
  bool _moduleOff = false;
  String _lastSignature = 'open|';

  late WorkTrackingService _service =
      widget.service ?? WorkTrackingService(authService: widget.authService);

  late final CursorLoader<WorkResidentItem> _loader =
      CursorLoader<WorkResidentItem>(
        fetch: (before) async {
          final page = await _service.listMine(
            siteCode: _siteFilter,
            status: _status,
            limit: 30,
            beforeId: before,
          );
          if (before == null) {
            _unreadUpdates = page.unreadUpdates;
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
            'Talepleriniz yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
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
  void didUpdateWidget(WorkResidentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.authService, widget.authService)) {
      _service =
          widget.service ?? WorkTrackingService(authService: widget.authService);
    }
    // Süzgeçteki site artık listede yoksa süzgeç kalkar.
    final filter = _siteFilter;
    if (filter != null && !widget.sites.any((s) => s.code == filter)) {
      _siteFilter = null;
      _applyFilters();
    }
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  /// Listeyi yeniden çeker (sayfa kabuğunun çekip yenilemesi ve yenile düğmesi).
  Future<void> reload() => _loader.reload();

  void _applyFilters() {
    final signature = '$_status|${_siteFilter ?? ''}';
    if (signature == _lastSignature &&
        (_loader.loading || (_loader.loadedOnce && _loader.error == null))) {
      return;
    }
    _lastSignature = signature;
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _selectStatus(String status) {
    if (status == _status) return;
    setState(() => _status = status);
    _applyFilters();
  }

  WorkPhotoPicker get _picker =>
      widget.photoPicker ?? const FilePickerWorkPhotoPicker();

  /// Talep açıldıktan sonraki bildirim: fotoğraf yüklenemediyse DÜRÜSTÇE söylenir (talep önceden kayıtlı çıksa bile).
  static String createdMessage(WorkCreateResult result) {
    final failed = result.photosFailed;
    final lead = result.replayed ? 'Bu talep zaten kayıtlıydı' : 'Talep oluşturuldu';
    if (failed > 0) {
      return result.photosCancelled
          ? '$lead, fotoğraf yükleme iptal edildi; $failed fotoğraf eklenmedi.'
          : '$lead, $failed fotoğraf yüklenemedi.';
    }
    if (result.replayed) return 'Bu talep zaten kayıtlıydı.';
    return 'Talebiniz alındı. Durumunu buradan takip edebilirsiniz.';
  }

  Future<void> _create() async {
    final result = await WorkItemFormDialog.show(
      context,
      service: _service,
      sites: widget.sites,
      initialSiteCode: _siteFilter,
      picker: _picker,
    );
    if (result == null || !mounted) return;
    AppSnack.show(
      context,
      createdMessage(result),
      kind: result.photosFailed > 0 ? AppSnackKind.warning : AppSnackKind.success,
    );
    // Yeni talep "Açık" listesindedir: kapanan süzgecinde görünmezdi.
    if (_status == 'closed') {
      _selectStatus('open');
    } else {
      unawaited(_loader.reload());
    }
  }

  Future<void> _open(WorkResidentItem item) async {
    final changed = await WorkResidentDetailDialog.show(
      context,
      service: _service,
      item: item,
      picker: _picker,
    );
    if (changed && mounted) unawaited(_loader.reload());
  }

  bool get _filtered => _status != 'open' || _siteFilter != null;

  String get _emptyTitle => switch (_status) {
    'closed' => 'Kapanmış talebiniz yok.',
    'all' => 'Henüz talebiniz yok.',
    _ => _siteFilter != null ? 'Bu sitede açık talebiniz yok.' : 'Açık talebiniz yok.',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final multiSite = widget.sites.length > 1;
    final canCreate = widget.sites.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeaderCard(
          title: 'Taleplerim',
          icon: Icons.assignment_rounded,
          action: canCreate
              ? ElevatedButton.icon(
                  key: const ValueKey<String>('work_new_request'),
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Yeni Talep'),
                )
              : null,
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Arıza, bakım, şikayet ya da önerinizi yönetime iletin ve durumunu buradan izleyin.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        if (multiSite) ...[
          AppCard(
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>('work_resident_site_${_siteFilter ?? 0}'),
              isExpanded: true,
              initialValue: _siteFilter ?? _allSites,
              dropdownColor: p.surface,
              style: th.bodyMedium?.copyWith(color: p.text),
              decoration: const InputDecoration(
                labelText: 'Site',
                prefixIcon: Icon(Icons.apartment_rounded),
              ),
              items: [
                const DropdownMenuItem<int>(
                  value: _allSites,
                  child: Text(
                    'Tüm siteler',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final s in widget.sites)
                  DropdownMenuItem<int>(
                    value: s.code,
                    child: Text(
                      s.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                final next = value == _allSites ? null : value;
                if (next == _siteFilter) return;
                setState(() => _siteFilter = next);
                _applyFilters();
              },
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
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
                  for (final entry in const <(String, String)>[
                    ('open', 'Açık'),
                    ('closed', 'Kapanan'),
                    ('all', 'Tümü'),
                  ])
                    ChoiceChip(
                      key: ValueKey<String>('work_status_${entry.$1}'),
                      label: Text(entry.$2),
                      selected: _status == entry.$1,
                      onSelected: (_) => _selectStatus(entry.$1),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (_unreadUpdates > 0 && !_moduleOff) ...[
          InlineNotice(
            key: const ValueKey<String>('work_unread_notice'),
            tone: AppTone.warning,
            icon: Icons.notifications_active_rounded,
            message: _unreadUpdates == 1
                ? '1 talebinizde yeni güncelleme var.'
                : '$_unreadUpdates talebinizde yeni güncelleme var.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        SectionHeader(
          title: 'Talepler',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (_moduleOff)
          const EmptyCard(
            key: ValueKey<String>('work_module_off'),
            icon: Icons.assignment_late_rounded,
            tone: AppTone.warning,
            title: 'İş takibi bu site için kapalı.',
            message:
                'Yönetim bu özelliği açtığında arıza, bakım ve taleplerinizi buradan iletebilirsiniz.',
          )
        else if (!canCreate)
          const EmptyCard(
            icon: Icons.assignment_rounded,
            title: 'Talep açabileceğiniz site yok.',
            message:
                'İş takibi, bir siteye daire sakini olarak bağlandığınızda ve yönetim özelliği açtığında burada görünür.',
          )
        else
          CursorListBody<WorkResidentItem>(
            loader: _loader,
            showLastUpdated: true,
            emptyIcon: Icons.assignment_turned_in_rounded,
            emptyTitle: _emptyTitle,
            emptyMessage: _filtered
                ? null
                : 'Bir arıza ya da isteğiniz olduğunda "Yeni Talep" ile yönetime iletebilirsiniz.',
            itemBuilder: (context, item) => WorkResidentCard(
              item: item,
              showSite: multiSite,
              onTap: () => unawaited(_open(item)),
            ),
          ),
      ],
    );
  }
}
