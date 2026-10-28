import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart' show BulkExportFilters;
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_account_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_entry_buttons.dart' show BulkEmptyImportAction;
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/person_card.dart';

/// "Kişiler" sekmesi (Platform Faz 2a): arama + ilişki / durum süzgeçleri, sayfalı kişi listesi,
/// "Kişi Ekle", kişi bazlı işlem seçenekleri (düzenle, şifre sıfırlama, davet, ilişik kesme)
/// ve seçerek toplu işlem (çoklu seçim) yapabilme.
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

  // Çoklu seçim durumu
  bool _selectionMode = false;
  final Set<int> _selectedIds = <int>{};
  bool _bulkRunning = false;

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

  /// Listeyi yeniden çeker.
  Future<void> reload() => _loader.reload();

  /// Dışa aktarmanın kullanacağı süzgeçler.
  BulkExportFilters get exportFilters =>
      BulkExportFilters(query: _query, status: _status, relation: _relation?.apiValue);

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
    final created = await PersonFormDialog.show(
      context,
      scope: widget.scope,
      onChanged: _afterChange,
    );
    if (created == null || !mounted) return;
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
          "Kişi eklendi ve hesap açıldı; ancak giriş bilgisi e-postası gönderilemedi. PIN saklanmadığı için Daireler ekranından PIN'i sıfırlayın.",
          kind: AppSnackKind.warning,
        );
      case null when created.credentialsEmail != null:
        AppSnack.show(
          context,
          "Kişi eklendi ve hesap açıldı; giriş bilgisi e-postası gönderiliyor. Ulaşmazsa Daireler ekranından PIN'i sıfırlayın.",
          kind: AppSnackKind.info,
        );
      case null:
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

  Future<void> _editPerson(PersonSummary person) async {
    try {
      final detail = await widget.scope.authService.getPerson(
        widget.scope.siteCode,
        person.id,
      );
      if (!mounted) return;
      final result = await PersonFormDialog.show(
        context,
        scope: widget.scope,
        person: detail,
        onChanged: _afterChange,
      );
      if (result != null && mounted) {
        _afterChange();
      }
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        crmMessageOf(e, 'Kişi bilgileri yüklenemedi.'),
        kind: AppSnackKind.error,
      );
    }
  }

  Future<void> _sendPasswordReset(PersonSummary person) async {
    final confirmed = await confirmCrmAction(
      context,
      title: 'Şifre Sıfırlama Bağlantısı',
      message:
          '${person.fullName} kullanıcısının kayıtlı e-posta adresine güvenli şifre sıfırlama bağlantısı gönderilsin mi?\n\n(Şifreyi yalnızca kullanıcının kendisi belirleyebilir.)',
      confirmLabel: 'Bağlantı Gönder',
      icon: Icons.lock_reset_rounded,
      tone: AppTone.primary,
    );
    if (!confirmed || !mounted) return;

    try {
      final res = await widget.scope.authService.sendPersonPasswordReset(
        widget.scope.siteCode,
        person.id,
      );
      if (!mounted) return;
      AppSnack.show(
        context,
        res['message']?.toString() ?? 'Şifre sıfırlama bağlantısı e-posta adresine iletildi.',
        kind: AppSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        crmMessageOf(e, 'Şifre sıfırlama bağlantısı gönderilemedi.'),
        kind: AppSnackKind.error,
      );
    }
  }

  Future<void> _openAccountDialog(PersonSummary person) async {
    final result = await PersonAccountDialog.show(
      context,
      siteCode: widget.scope.siteCode,
      personId: person.id,
      personName: person.fullName,
      initialEmail: person.email,
      hasAccount: person.hasAccount,
      authService: widget.scope.authService,
    );
    if (result != null) {
      _afterChange();
    }
  }

  Future<void> _directResetPin(PersonSummary person) async {
    final confirmed = await confirmCrmAction(
      context,
      title: 'Geçici Şifre / PIN Sıfırlansın mı?',
      message:
          '${person.fullName} kişisinin geçici şifresi sıfırlansın mı?\n\nYeni bir geçici şifre (PIN) üretilecek ve sakine iletmeniz için ekranda gösterilecektir.',
      confirmLabel: 'Şifreyi Sıfırla',
      icon: Icons.lock_reset_rounded,
      tone: AppTone.warning,
    );
    if (!confirmed || !mounted) return;

    try {
      final res = await widget.scope.authService.resetPersonPinDirect(
        widget.scope.siteCode,
        person.id,
      );
      if (!mounted) return;
      _afterChange();
      await AccountCredentialsIssuedDialog.show(
        context,
        personName: person.fullName,
        loginName: res['login_name']?.toString() ?? person.fullName,
        password: res['pin_code']?.toString() ?? '1234',
        isNew: false,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        crmMessageOf(e, 'Geçici şifre sıfırlanamadı.'),
        kind: AppSnackKind.error,
      );
    }
  }

  Future<void> _sendInvite(PersonSummary person) async {
    final confirmed = await confirmCrmAction(
      context,
      title: 'Uygulamaya Davet Et',
      message:
          '${person.fullName} kişisine (${person.email ?? ''}) uygulamaya katılım ve şifre belirleme bağlantısı gönderilsin mi?',
      confirmLabel: 'Davet Gönder',
      icon: Icons.send_rounded,
      tone: AppTone.primary,
    );
    if (!confirmed || !mounted) return;

    try {
      await widget.scope.authService.sendPersonInvitation(
        widget.scope.siteCode,
        person.id,
      );
      if (!mounted) return;
      AppSnack.show(
        context,
        'Davet bağlantısı e-posta adresine başarıyla gönderildi.',
        kind: AppSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        crmMessageOf(e, 'Davet gönderilemedi.'),
        kind: AppSnackKind.error,
      );
    }
  }

  Future<void> _toggleActive(PersonSummary person) async {
    final isDeactivating = person.isActive;
    final confirmed = await confirmCrmAction(
      context,
      title: isDeactivating ? 'Siteden İlişiği Kes' : 'Yeniden Etkinleştir',
      message: isDeactivating
          ? '${person.fullName} kişisinin siteyle ilişiği kesilsin mi?\n\nDaire bağlantıları sonlandırılacak, kapı erişimleri iptal edilecek ve kişi pasife alınacaktır (geçmiş kayıtlar korunur).'
          : '${person.fullName} kişisi yeniden aktif sakine dönüştürülsün mü?',
      confirmLabel: isDeactivating ? 'İlişiği Kes' : 'Etkinleştir',
      icon: isDeactivating ? Icons.person_off_rounded : Icons.person_add_alt_1_rounded,
      tone: isDeactivating ? AppTone.danger : AppTone.primary,
    );
    if (!confirmed || !mounted) return;

    try {
      await widget.scope.authService.updatePerson(
        widget.scope.siteCode,
        person.id,
        {'is_active': !isDeactivating},
      );
      if (!mounted) return;
      AppSnack.show(
        context,
        isDeactivating ? 'Kişinin ilişiği kesildi ve pasife alındı.' : 'Kişi yeniden etkinleştirildi.',
        kind: AppSnackKind.success,
      );
      _afterChange();
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        crmMessageOf(e, 'İşlem gerçekleştirilemedi.'),
        kind: AppSnackKind.error,
      );
    }
  }

  void _toggleSelectAll() {
    setState(() {
      final loadedIds = _loader.items.map((p) => p.id).toSet();
      if (_selectedIds.containsAll(loadedIds)) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(loadedIds);
      }
    });
  }

  Future<void> _runBulkAction({
    required String action,
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
    required AppTone tone,
  }) async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await confirmCrmAction(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      icon: icon,
      tone: tone,
    );
    if (!confirmed || !mounted) return;

    setState(() => _bulkRunning = true);
    try {
      final res = await widget.scope.authService.executePeopleBulkAction(
        widget.scope.siteCode,
        action: action,
        personIds: _selectedIds.toList(),
      );
      if (!mounted) return;
      final succeeded = res['succeeded'] ?? 0;
      final failed = res['failed'] ?? 0;
      AppSnack.show(
        context,
        failed == 0
            ? '$succeeded kişi için toplu işlem başarıyla tamamlandı.'
            : '$succeeded işlem başarılı, $failed işlem başarısız oldu.',
        kind: failed == 0 ? AppSnackKind.success : AppSnackKind.warning,
      );
      setState(() {
        _selectedIds.clear();
        _selectionMode = false;
      });
      _afterChange();
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        crmMessageOf(e, 'Toplu işlem gerçekleştirilemedi.'),
        kind: AppSnackKind.error,
      );
    } finally {
      if (mounted) setState(() => _bulkRunning = false);
    }
  }

  bool get _filtered => _query.isNotEmpty || _relation != null || _status != 'active';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final allLoadedSelected =
        _loader.items.isNotEmpty && _selectedIds.containsAll(_loader.items.map((e) => e.id));

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

        // Bölüm Başlığı & Çoklu Seçim Tetikleyicisi
        SectionHeader(
          title: 'Kişiler',
          count: _loader.loadedOnce ? _loader.total : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.scope.canWrite && _loader.items.isNotEmpty)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectionMode = !_selectionMode;
                      if (!_selectionMode) _selectedIds.clear();
                    });
                  },
                  tooltip: _selectionMode ? 'Seçimi Kapat' : 'Çoklu Seçim',
                  icon: Icon(_selectionMode ? Icons.check_box_rounded : Icons.checklist_rounded),
                  color: _selectionMode ? AppTone.primary.a : null,
                ),
              IconButton(
                onPressed: _loader.loading ? null : reload,
                tooltip: 'Yenile',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),

        // Çoklu Seçim İşlem Paneli
        if (_selectionMode) ...[
          const SizedBox(height: AppSpace.sm),
          AppCard(
            tone: AppTone.primary,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: allLoadedSelected,
                        onChanged: (_) => _toggleSelectAll(),
                        activeColor: AppTone.primary.a,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Expanded(
                        child: Text(
                          _selectedIds.isEmpty
                              ? 'İşlem yapılacak kişileri seçin'
                              : '${_selectedIds.length} kişi seçildi',
                          style: th.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: _loader.items.isEmpty ? null : _toggleSelectAll,
                        child: Text(allLoadedSelected ? 'Seçimi Bırak' : 'Tümünü Seç'),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _selectionMode = false;
                            _selectedIds.clear();
                          });
                        },
                        tooltip: 'Kapat',
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  if (_bulkRunning) ...[
                    const SizedBox(height: AppSpace.sm),
                    const LinearProgressIndicator(),
                  ],
                  if (_selectedIds.isNotEmpty && !_bulkRunning) ...[
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _runBulkAction(
                            action: 'password_reset_or_invite',
                            title: 'Toplu Şifre / Davet Gönder',
                            message:
                                'Seçilen ${_selectedIds.length} kişiye bağlantı gönderilsin mi?\n\n(Hesabı olanlara şifre sıfırlama, hesabı olmayanlara uygulamaya davet linki gönderilir.)',
                            confirmLabel: 'Gönder',
                            icon: Icons.forward_to_inbox_rounded,
                            tone: AppTone.primary,
                          ),
                          icon: const Icon(Icons.forward_to_inbox_rounded, size: 16),
                          label: const Text('Şifre / Davet Gönder'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTone.primary.a,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _runBulkAction(
                            action: 'end_residency',
                            title: 'Toplu Siteden İlişik Kes',
                            message:
                                'Seçilen ${_selectedIds.length} kişinin siteden ilişiği kesilsin mi?\n\nDaire bağları sonlandırılacak, kapı erişimleri iptal edilecek ve pasife alınacaktır (geçmiş kayıtlar korunur).',
                            confirmLabel: 'İlişik Kes',
                            icon: Icons.person_remove_rounded,
                            tone: AppTone.danger,
                          ),
                          icon: const Icon(Icons.person_remove_rounded, size: 16),
                          label: const Text('İlişiği Kes (Pasife Al)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTone.danger.a,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _runBulkAction(
                            action: 'activate',
                            title: 'Toplu Yeniden Etkinleştir',
                            message:
                                'Seçilen ${_selectedIds.length} kişi yeniden aktif sakine dönüştürülsün mü?',
                            confirmLabel: 'Etkinleştir',
                            icon: Icons.check_circle_outline_rounded,
                            tone: AppTone.primary,
                          ),
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                          label: const Text('Yeniden Etkinleştir'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: AppSpace.md),
        CrmListBody<PersonSummary>(
          loader: _loader,
          showLastUpdated: true,
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
          itemBuilder: (context, person) => PersonCard(
            person: person,
            onTap: () => _open(person),
            isSelectionMode: _selectionMode,
            isSelected: _selectedIds.contains(person.id),
            onSelectChanged: (selected) {
              setState(() {
                if (selected == true) {
                  _selectedIds.add(person.id);
                } else {
                  _selectedIds.remove(person.id);
                }
              });
            },
            onEdit: widget.scope.canWrite ? () => _editPerson(person) : null,
            onPasswordReset: widget.scope.canWrite && person.hasAccount
                ? () => _sendPasswordReset(person)
                : null,
            onInvite: widget.scope.canWrite &&
                    !person.hasAccount &&
                    person.email != null &&
                    person.email!.isNotEmpty
                ? () => _sendInvite(person)
                : null,
            onToggleActive: widget.scope.canWrite ? () => _toggleActive(person) : null,
            onProvisionAccount: widget.scope.canWrite ? () => _openAccountDialog(person) : null,
            onDirectResetPin: widget.scope.canWrite && person.hasAccount ? () => _directResetPin(person) : null,
          ),
        ),
      ],
    );
  }
}
