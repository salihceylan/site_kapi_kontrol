import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart' show BulkExportFilters;
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_entry_buttons.dart' show BulkEmptyImportAction;
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/person_card.dart';

/// "Kişiler" sekmesi (Platform Faz 2a): arama + ilişki / durum süzgeçleri, sayfalı kişi listesi,
/// "Kişi Ekle" (yalnız yazma yetkisi olanda) ve kişi kartı.
///
/// Hızlı art arda aramada eski yanıt yenisini ezmez ([PagedLoader] jetonu). Arama duraksayınca (350 ms)
/// ya da klavyeden gönderilince çalışır. Her başarılı işlemden sonra liste otomatik yenilenir ve
/// [onDataChanged] çağrılır (diğer sekmeler bayatlar).
class PeoplePersonsTab extends StatefulWidget {
  const PeoplePersonsTab({
    super.key,
    required this.scope,
    required this.onDataChanged,
    this.onImportRequested,
  });

  final PeopleScope scope;
  final VoidCallback onDataChanged;

  /// Boş listede «Excel'den yükle» eylemini gösterir (yalnız yazma yetkisi olanda); null ise gösterilmez.
  final VoidCallback? onImportRequested;

  @override
  State<PeoplePersonsTab> createState() => PeoplePersonsTabState();
}

class PeoplePersonsTabState extends State<PeoplePersonsTab> {
  static const String _all = '';

  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  ResidencyRelation? _relation;
  String _status = 'active';

  late final PagedLoader<PersonSummary> _loader = PagedLoader<PersonSummary>(
    fetch: (offset, limit) async {
      final page = await widget.scope.authService.listPeople(
        widget.scope.siteCode,
        query: _query,
        relation: _relation,
        status: _status,
        limit: limit,
        offset: offset,
      );
      return (items: page.items, total: page.total);
    },
    keyOf: (p) => p.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Kişiler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Listeyi yeniden çeker (sayfa kabuğunun çekip yenilemesi ve yenile düğmesi).
  Future<void> reload() => _loader.reload();

  /// Dışa aktarmanın kullanacağı süzgeçler (listede UYGULANMIŞ arama / ilişki / durum).
  BulkExportFilters get exportFilters =>
      BulkExportFilters(query: _query, status: _status, relation: _relation?.apiValue);

  // Son çalıştırılan sorgunun imzası: okuma hız sınırı düşük olduğundan AYNI sorgu tekrar çağrılmaz
  // (Enter + gecikme sayacı, aynı süzgeci yeniden seçme).
  String _lastSignature = '|null|active';

  void _applyFilters() {
    _timer?.cancel();
    final next = _search.text.trim();
    final signature = '$next|${_relation?.apiValue}|$_status';
    if (signature == _lastSignature &&
        (_loader.loading || (_loader.loadedOnce && _loader.error == null))) {
      return;
    }
    _lastSignature = signature;
    _query = next;
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _onSearchChanged(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _applyFilters);
    setState(() {});
  }

  void _afterChange() {
    widget.onDataChanged();
    unawaited(_loader.reload());
  }

  Future<void> _add() async {
    // "Kişiyi Aç" ile açılan mevcut kişinin kartında yapılan değişiklik de listeyi tazeler.
    final created = await PersonFormDialog.show(
      context,
      scope: widget.scope,
      onChanged: _afterChange,
    );
    if (created == null || !mounted) return;
    // Boş daireye dahili hesap açıldıysa giriş bilgisi e-postasının sonucu (`credentials_sent`): alan
    // yoksa (null) ek mesaj gösterilmez.
    switch (created.credentialsSent) {
      case true:
        AppSnack.show(
          context,
          'Kişi eklendi. Giriş bilgileri e-postayla gönderildi.',
          kind: AppSnackKind.success,
        );
      case false:
        AppSnack.show(
          context,
          // PIN sunucuda saklanmaz: e-posta gitmediyse PIN yalnız Daireler ekranından sıfırlanarak verilebilir.
          "Kişi eklendi ve hesap açıldı; ancak giriş bilgisi e-postası gönderilemedi. PIN saklanmadığı için Daireler ekranından PIN'i sıfırlayın.",
          kind: AppSnackKind.warning,
        );
      case null when created.credentialsEmail != null:
        // Hesap açıldı, e-posta gönderimi yanıt süresinde bitmedi (sunucu beklemeden yanıtladı).
        AppSnack.show(
          context,
          "Kişi eklendi ve hesap açıldı; giriş bilgisi e-postası gönderiliyor. Ulaşmazsa Daireler ekranından PIN'i sıfırlayın.",
          kind: AppSnackKind.info,
        );
      case null:
        // Hesap açılmadı: e-posta bu sitedeki kayıtlı bir hesaba aitse kişi o hesaba bağlanır, değilse yalnız kayıt.
        AppSnack.show(
          context,
          created.hasAccount
              ? 'Kişi eklendi ve mevcut hesabına bağlandı.'
              : 'Kişi eklendi. Yalnız kayıt olarak tutuldu; giriş hesabı açılmadı.',
          kind: AppSnackKind.success,
        );
    }
    _afterChange();
  }

  Future<void> _open(PersonSummary person) {
    return PersonCardDialog.show(
      context,
      scope: widget.scope,
      personId: person.id,
      initialName: person.fullName,
      onChanged: _afterChange,
    );
  }

  bool get _filtered => _query.isNotEmpty || _relation != null || _status != 'active';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.scope.canWrite) ...[
          PrimaryActionButton(
            label: 'Kişi Ekle',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: _add,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey<String>('people_search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _applyFilters(),
                decoration: InputDecoration(
                  labelText: 'Kişi ara',
                  hintText: 'Ad, telefon, e-posta veya daire',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Aramayı temizle',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _applyFilters();
                            setState(() {});
                          },
                        ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<String>(
                key: ValueKey<String>('people_relation_${_relation?.apiValue ?? ''}'),
                isExpanded: true,
                initialValue: _relation?.apiValue ?? _all,
                dropdownColor: p.surface,
                style: th.bodyMedium?.copyWith(color: p.text),
                decoration: const InputDecoration(
                  labelText: 'İlişki',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: _all,
                    child: Text('Tümü', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  for (final relation in ResidencyRelation.values)
                    DropdownMenuItem<String>(
                      value: relation.apiValue,
                      child: Text(
                        relation.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  final next = value == _all ? null : ResidencyRelation.tryParse(value);
                  if (next == _relation) return;
                  _relation = next;
                  _applyFilters();
                  setState(() {});
                },
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<String>(
                key: ValueKey<String>('people_status_$_status'),
                isExpanded: true,
                initialValue: _status,
                dropdownColor: p.surface,
                style: th.bodyMedium?.copyWith(color: p.text),
                decoration: const InputDecoration(
                  labelText: 'Durum',
                  prefixIcon: Icon(Icons.filter_list_rounded),
                ),
                items: const [
                  DropdownMenuItem<String>(
                    value: 'active',
                    child: Text('Aktif kişiler', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem<String>(
                    value: 'inactive',
                    child: Text('Eski sakinler', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem<String>(
                    value: 'all',
                    child: Text('Tümü', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
                onChanged: (value) {
                  if (value == null || value == _status) return;
                  _status = value;
                  _applyFilters();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: 'Kişiler',
          count: _loader.loadedOnce ? _loader.total : null,
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CrmListBody<PersonSummary>(
          loader: _loader,
          emptyIcon: Icons.groups_2_rounded,
          emptyTitle: 'Henüz kişi kaydı yok.',
          emptyMessage: widget.scope.canWrite
              ? 'Kişi Ekle ile ilk kaydı oluşturabilirsiniz.'
              : null,
          filteredTitle: 'Bu arama ve süzgeç için kişi bulunamadı.',
          filtered: _filtered,
          emptyAction: widget.scope.canWrite && widget.onImportRequested != null
              ? BulkEmptyImportAction(onImport: widget.onImportRequested!)
              : null,
          itemBuilder: (context, person) =>
              PersonCard(person: person, onTap: () => _open(person)),
        ),
      ],
    );
  }
}
