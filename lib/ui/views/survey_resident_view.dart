import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/survey_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/survey_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/survey_parts.dart';

/// Sakin "Anketler" ekranı (`survey` modülü): hedef kitlesinde olduğu açık anketler (seçenek seç + "Oy ver" onaylı;
/// oy verince sonuç çubukları) ve kapanan anketler bölümü (sonuçlarıyla).
///
/// - Birden çok sitede ([sites] >= 2) site süzgeci çıkar ve kartlarda site adı görünür.
/// - HATA ASLA "anket yok" demez; modül kapalıysa (403 `MODULE_DISABLED`) açıklayıcı kart çıkar.
/// - [SurveyResidentViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class SurveyResidentView extends StatefulWidget {
  const SurveyResidentView({super.key, required this.authService, this.service, this.sites = const <PeopleSite>[]});

  final AuthService authService;
  final SurveyService? service;
  final List<PeopleSite> sites;

  @override
  State<SurveyResidentView> createState() => SurveyResidentViewState();
}

class SurveyResidentViewState extends State<SurveyResidentView> {
  static const int _allSites = 0;

  int? _siteFilter;
  bool _moduleOff = false;

  late SurveyService _service = widget.service ?? SurveyService(authService: widget.authService);

  late final CursorLoader<SurveyResidentItem> _loader = CursorLoader<SurveyResidentItem>(
    fetch: (before) async {
      final page = await _service.listMine(siteCode: _siteFilter, limit: 30, beforeId: before);
      if (before == null) _moduleOff = false;
      return (items: page.items, next: page.nextBeforeId);
    },
    keyOf: (item) => item.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Anketler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    messageOf: (error, fallback) {
      if (error is ApiException && error.code == 'MODULE_DISABLED') _moduleOff = true;
      return crmMessageOf(error, fallback);
    },
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void didUpdateWidget(SurveyResidentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) || !identical(oldWidget.authService, widget.authService)) {
      _service = widget.service ?? SurveyService(authService: widget.authService);
    }
    final filter = _siteFilter;
    if (filter != null && !widget.sites.any((s) => s.code == filter)) {
      _siteFilter = null;
      _loader.reset();
      unawaited(_loader.reload());
    }
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  /// Listeyi yeniden çeker (sayfa kabuğunun çekip yenilemesi ve yenile düğmesi).
  Future<void> reload() => _loader.reload();

  Future<bool> _vote(SurveyResidentItem item, int index) async {
    final option = index >= 0 && index < item.options.length ? item.options[index] : 'Seçenek ${index + 1}';
    final ok = await confirmCrmAction(
      context,
      title: 'Oyunuzu onaylayın',
      message: '"$option" seçeneğine oy veriyorsunuz. Oy sonradan değiştirilemez.',
      confirmLabel: 'Oy ver',
      icon: Icons.how_to_vote_rounded,
      tone: AppTone.primary,
    );
    if (!ok || !mounted) return false;
    try {
      final updated = await _service.vote(item.id, index);
      if (!mounted) return true;
      _loader.updateItem(item.id, (old) => updated.id == old.id ? updated : old.copyWith(myVote: index));
      setState(() {});
      AppSnack.show(context, 'Oyunuz alındı.', kind: AppSnackKind.success);
      return true;
    } catch (e) {
      if (!mounted) return false;
      final message = crmMessageOf(e, 'Oy gönderilemedi. Lütfen tekrar deneyin.');
      AppSnack.show(context, message, kind: AppSnackKind.error);
      if (e is ApiException && (e.code == 'ALREADY_VOTED' || e.code == 'SURVEY_CLOSED' || e.code == 'APARTMENT_ALREADY_VOTED')) {
        unawaited(_loader.reload());
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final multiSite = widget.sites.length > 1;
    final items = _loader.items;
    final open = items.where((s) => s.isOpen).toList(growable: false);
    final closed = items.where((s) => !s.isOpen).toList(growable: false);
    final error = _loader.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Anketler', icon: Icons.poll_rounded),
        const SizedBox(height: AppSpace.sm),
        Text('Yönetimin açtığı anketlerde oy kullanın ve sonuçları görün.', style: th.bodyMedium),
        const SizedBox(height: AppSpace.lg),
        if (multiSite) ...[
          AppCard(
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>('survey_resident_site_${_siteFilter ?? 0}'),
              isExpanded: true,
              initialValue: _siteFilter ?? _allSites,
              dropdownColor: p.surface,
              style: th.bodyMedium?.copyWith(color: p.text),
              decoration: const InputDecoration(labelText: 'Site', prefixIcon: Icon(Icons.apartment_rounded)),
              items: [
                const DropdownMenuItem<int>(value: _allSites, child: Text('Tüm siteler', maxLines: 1, overflow: TextOverflow.ellipsis)),
                for (final s in widget.sites)
                  DropdownMenuItem<int>(value: s.code, child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) {
                if (value == null) return;
                final next = value == _allSites ? null : value;
                if (next == _siteFilter) return;
                setState(() => _siteFilter = next);
                _loader.reset();
                unawaited(_loader.reload());
              },
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        SectionHeader(
          title: 'Açık anketler',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (_moduleOff)
          const SurveyModuleOffCard()
        else if (widget.sites.isEmpty)
          const EmptyCard(
            icon: Icons.poll_outlined,
            title: 'Anket görebileceğiniz site yok.',
            message: 'Anketler, bir siteye daire sakini olarak bağlandığınızda ve yönetim özelliği açtığında burada görünür.',
          )
        else if (_loader.loading && !_loader.loadedOnce)
          const ListSkeleton(rows: 2)
        else if (error != null && items.isEmpty)
          EmptyCard(
            key: const ValueKey<String>('survey_error'),
            icon: Icons.cloud_off_rounded,
            tone: AppTone.danger,
            title: error,
            child: TextButton.icon(
              onPressed: _loader.loading ? null : reload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar Dene'),
            ),
          )
        else ...[
          if (open.isEmpty)
            const EmptyCard(
              key: ValueKey<String>('survey_open_empty'),
              icon: Icons.how_to_vote_outlined,
              title: 'Açık anket yok.',
              message: 'Yönetim yeni bir anket açtığında burada görünür.',
            )
          else
            for (final item in open) ...[
              SurveyVoteCard(
                key: ValueKey<String>('survey_card_${item.id}'),
                item: item,
                showSite: multiSite,
                onVote: (index) => _vote(item, index),
              ),
              const SizedBox(height: AppSpace.md),
            ],
          const SizedBox(height: AppSpace.sm),
          const SectionHeader(title: 'Kapanan anketler'),
          const SizedBox(height: AppSpace.md),
          if (closed.isEmpty)
            const EmptyCard(
              key: ValueKey<String>('survey_closed_empty'),
              icon: Icons.lock_outline_rounded,
              title: 'Kapanmış anket yok.',
            )
          else
            for (final item in closed) ...[
              SurveyVoteCard(
                key: ValueKey<String>('survey_card_${item.id}'),
                item: item,
                showSite: multiSite,
                onVote: (index) => _vote(item, index),
              ),
              const SizedBox(height: AppSpace.md),
            ],
          if (_loader.hasMore)
            TextButton.icon(
              key: const ValueKey<String>('survey_more'),
              onPressed: _loader.loadingMore ? null : () => unawaited(_loader.loadMore()),
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('Daha fazla'),
            ),
        ],
      ],
    );
  }
}
