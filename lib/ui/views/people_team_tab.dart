import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

/// Kişiler ekranındaki "Kadro" sekmesi: yönetici, kurul ve görevliler, eski ek roller ve faydalı telefonlar.
///
/// Görev vermek kişi kartındandır ("Görev ver"); burada kadro okunur, görev satırına dokununca kişi kartı açılır.
/// Kurul üyesi (salt okur) e-posta ve yetki durumunu görmez (sunucu göndermez). Her değişiklikte [onDataChanged].
class PeopleTeamTab extends StatefulWidget {
  const PeopleTeamTab({super.key, required this.scope, required this.onDataChanged});

  final PeopleScope scope;
  final VoidCallback onDataChanged;

  @override
  State<PeopleTeamTab> createState() => PeopleTeamTabState();
}

class PeopleTeamTabState extends State<PeopleTeamTab> {
  TeamData? _data;
  bool _loading = true;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> reload() async {
    final token = ++_token;
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final data = await widget.scope.authService.getTeam(widget.scope.siteCode);
      if (!mounted || token != _token) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Yönetim kadrosu yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _guard(Future<void> Function() action, String success) async {
    try {
      await action();
      if (!mounted) return;
      AppSnack.show(context, success, kind: AppSnackKind.success);
      widget.onDataChanged();
      await reload();
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    } catch (e) {
      if (mounted) AppSnack.show(context, crmMessageOf(e, 'İşlem yapılamadı. Tekrar deneyin.'), kind: AppSnackKind.error);
    }
  }

  Future<void> _removeLegacy(LegacyStaffRole role) async {
    final ok = await confirmCrmAction(
      context,
      title: 'Rol kaldırılsın mı?',
      message: '${role.fullName} kişisinin eski ek rolü kaldırılsın mı? Hesabı ve daire kayıtları değişmez.',
      confirmLabel: 'Rolü Kaldır',
      icon: Icons.person_remove_rounded,
      tone: AppTone.danger,
    );
    if (!ok || !mounted) return;
    await _guard(
      () => widget.scope.authService.removeStaffRole(widget.scope.siteCode, role.userCode),
      'Rol kaldırıldı.',
    );
  }

  Future<void> _editContact([DirectoryContact? current]) async {
    final label = TextEditingController(text: current?.label ?? '');
    final phone = TextEditingController(text: current?.phone ?? '');
    final note = TextEditingController(text: current?.note ?? '');
    var category = current?.category ?? 'other';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(current == null ? 'Faydalı telefon ekle' : 'Telefonu düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: label, maxLength: 80, decoration: const InputDecoration(labelText: 'Ad (ör. Su arıza)')),
                TextField(controller: phone, maxLength: 32, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon')),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tür'),
                  items: [
                    for (final entry in kContactCategoryLabels.entries)
                      DropdownMenuItem<String>(value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged: (value) => setLocal(() => category = value ?? category),
                ),
                TextField(controller: note, maxLength: 200, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    final values = (label: label.text.trim(), phone: phone.text.trim(), note: note.text.trim());
    label.dispose();
    phone.dispose();
    note.dispose();
    if (saved != true || !mounted) return;
    if (values.label.isEmpty || values.phone.length < 3) {
      AppSnack.show(context, 'Ad ve telefon yazın.', kind: AppSnackKind.error);
      return;
    }
    await _guard(
      () => widget.scope.authService.saveDirectoryContact(
        widget.scope.siteCode,
        contactId: current?.id,
        label: values.label,
        phone: values.phone,
        note: values.note.isEmpty ? null : values.note,
        category: category,
      ),
      'Telefon kaydedildi.',
    );
  }

  Future<void> _deleteContact(DirectoryContact contact) async {
    final ok = await confirmCrmAction(
      context,
      title: 'Telefon silinsin mi?',
      message: '"${contact.label}" rehberden silinsin mi?',
      confirmLabel: 'Sil',
      icon: Icons.delete_rounded,
      tone: AppTone.danger,
    );
    if (!ok || !mounted) return;
    await _guard(
      () => widget.scope.authService.deleteDirectoryContact(widget.scope.siteCode, contact.id),
      'Telefon silindi.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: context.palette.textSecondary);
    if (_loading) return Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text('Kadro yükleniyor...', style: secondary));
    if (_error != null) return InlineNotice(message: _error!, onRetry: reload);
    final data = _data!;
    final canWrite = widget.scope.canWrite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Block(
          title: 'Site yöneticisi',
          icon: Icons.manage_accounts_rounded,
          children: [
            if (data.managers.isEmpty) Text('Yönetici görünmüyor.', style: secondary),
            for (final name in data.managers) Text(name, style: th.bodyLarge),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        for (final group in const <(String, List<String>)>[
          ('Yönetim kurulu ve denetçi', <String>['board_member', 'auditor']),
          ('Görevliler', <String>['doorman', 'technical', 'reception', 'other']),
        ]) ...[
          _Block(
            title: group.$1,
            icon: Icons.badge_rounded,
            children: [
              if (data.duties.where((d) => group.$2.contains(d.duty)).isEmpty)
                Text(
                  group.$2.contains('doorman')
                      ? 'Görev vermezseniz işler sizde kalır. Kişinin kartından "Görev ver" deyin.'
                      : 'Henüz kimse yok.',
                  style: secondary,
                ),
              for (final duty in data.duties.where((d) => group.$2.contains(d.duty)))
                ListTile(
                  key: ValueKey<String>('team_duty_${duty.personId}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(duty.fullName),
                  subtitle: Text(
                    [
                      duty.label,
                      if (duty.access != null) teamAccessText(duty.access),
                    ].join('\n'),
                  ),
                  isThreeLine: duty.access != null,
                  trailing: canWrite ? const Icon(Icons.chevron_right_rounded) : null,
                  onTap: canWrite
                      ? () async {
                          await PersonCardDialog.show(context, scope: widget.scope, personId: duty.personId);
                          if (mounted) unawaited(reload());
                        }
                      : null,
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (canWrite && data.legacyRoles.isNotEmpty) ...[
          _Block(
            title: 'Eski ek roller',
            icon: Icons.history_rounded,
            children: [
              Text('Kişi kaydına bağlı olmayan roller. Kişiye "Görev ver" ile kadroya alabilir ya da kaldırabilirsiniz.', style: secondary),
              for (final role in data.legacyRoles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(role.fullName),
                  subtitle: Text(role.role == 'BOARD_MEMBER' ? 'Yönetim kurulu / denetçi' : 'Görevli'),
                  trailing: IconButton(
                    tooltip: 'Rolü kaldır',
                    icon: const Icon(Icons.person_remove_rounded),
                    onPressed: () => unawaited(_removeLegacy(role)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        _Block(
          title: 'Faydalı telefonlar',
          icon: Icons.phone_in_talk_rounded,
          children: [
            if (!data.directoryEnabled)
              Text(
                'Rehber modülü kapalı: sakinler bu listeyi göremez. Açılması için Modüller ekranından talepte bulunun.',
                style: secondary,
              ),
            if (data.contacts.isEmpty) Text('Henüz telefon eklenmedi.', style: secondary),
            for (final contact in data.contacts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(contact.label),
                subtitle: Text('${contact.phone}${contact.note == null ? '' : '\n${contact.note}'}'),
                isThreeLine: contact.note != null,
                trailing: canWrite && data.directoryEnabled
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(tooltip: 'Düzenle', icon: const Icon(Icons.edit_rounded), onPressed: () => unawaited(_editContact(contact))),
                          IconButton(tooltip: 'Sil', icon: const Icon(Icons.delete_rounded), onPressed: () => unawaited(_deleteContact(contact))),
                        ],
                      )
                    : null,
              ),
            if (canWrite && data.directoryEnabled)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('team_add_contact'),
                  onPressed: () => unawaited(_editContact()),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Telefon Ekle'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          ...children,
        ],
      ),
    );
  }
}
