// Dairem pencereleri: kişi ekleme (yeni kişi ya da sistemden arayıp seçme), vekalet verme, gizli güvenlik talebi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_management.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;

/// Kiracı ya da aile üyesi ekleme penceresi. İki yol: "Yeni kişi" (ad, telefon, e-posta) ya da "Sistemden ara"
/// (en az 3 karakter; e-posta / telefon TAM yazılır; sonuçlar maskelidir ve daire / site bilgisi içermez).
/// Sonuç [AddPersonInput]: kayıtlı kişi seçildiyse davet gider ve kişi KABUL EDİNCE bağlanır.
class AddPersonDialog extends StatefulWidget {
  const AddPersonDialog({
    super.key,
    required this.service,
    required this.title,
    required this.tenantMode,
    required this.canSearch,
  });

  final ApartmentManagementService service;
  final String title;

  /// true: kiracı (yönetimi devret anahtarı); false: aile üyesi ("18 yaşından küçük" seçeneği).
  final bool tenantMode;
  final bool canSearch;

  static Future<AddPersonInput?> show(
    BuildContext context, {
    required ApartmentManagementService service,
    required String title,
    required bool tenantMode,
    required bool canSearch,
  }) {
    return showDialog<AddPersonInput>(
      context: context,
      builder: (_) => AddPersonDialog(service: service, title: title, tenantMode: tenantMode, canSearch: canSearch),
    );
  }

  @override
  State<AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<AddPersonDialog> {
  bool _search = false;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _query = TextEditingController();
  PersonSearchResult? _result;
  String? _selected;
  bool _searching = false;
  String? _error;
  bool _delegate = true;
  bool _minor = false;
  int _token = 0;

  @override
  void dispose() {
    ++_token;
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _query.text.trim();
    if (q.runes.length < 3) {
      setState(() => _error = 'En az 3 karakter yazın.');
      return;
    }
    final token = ++_token;
    setState(() {
      _searching = true;
      _error = null;
      _selected = null;
    });
    try {
      final result = await widget.service.searchPeople(q);
      if (!mounted || token != _token) return;
      setState(() {
        _result = result;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _searching = false;
        _result = null;
        _error = crmMessageOf(e, 'Arama yapılamadı. Tekrar deneyin.');
      });
    }
  }

  void _submit() {
    if (_search) {
      final handle = _selected;
      if (handle == null) {
        setState(() => _error = 'Listeden bir kişi seçin.');
        return;
      }
      popIfCurrent(context, AddPersonInput(candidate: handle, delegateManagement: _delegate, isMinor: _minor));
      return;
    }
    final name = _name.text.trim();
    if (name.runes.length < 2) {
      setState(() => _error = 'Ad soyad en az 2 karakter olmalı.');
      return;
    }
    popIfCurrent(
      context,
      AddPersonInput(
        fullName: name,
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        delegateManagement: _delegate,
        isMinor: _minor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final secondary = th.bodySmall?.copyWith(color: context.palette.textSecondary);
    return AppDialog(
      title: widget.title,
      icon: Icons.person_add_alt_1_rounded,
      actions: [
        TextButton(onPressed: () => popIfCurrent(context), child: const Text('Vazgeç')),
        ElevatedButton(onPressed: _submit, child: Text(_search ? 'Davet gönder' : 'Ekle')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.canSearch) ...[
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                ChoiceChip(
                  label: const Text('Yeni kişi'),
                  selected: !_search,
                  onSelected: (_) => setState(() {
                    _search = false;
                    _error = null;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Sistemden ara'),
                  selected: _search,
                  onSelected: (_) => setState(() {
                    _search = true;
                    _error = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
          ],
          if (!_search) ...[
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Ad soyad'),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefon (isteğe bağlı)', hintText: '+90 5__ ___ __ __'),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-posta (isteğe bağlı)'),
            ),
            const SizedBox(height: AppSpace.xs),
            Text('E-posta verirseniz kişiye uygulamaya katılması için davet gider.', style: secondary),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => unawaited(_runSearch()),
                    decoration: const InputDecoration(labelText: 'E-posta, telefon ya da ad soyad'),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                IconButton.filledTonal(
                  tooltip: 'Ara',
                  onPressed: _searching ? null : () => unawaited(_runSearch()),
                  icon: const Icon(Icons.search_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'E-posta ya da telefonu tam yazın. Ad soyad ile yalnızca "Beni aramalarda göster"i açmış kişiler bulunur. Sonuçlar gizlilik için maskelidir.',
              style: secondary,
            ),
            if (_searching) const Padding(padding: EdgeInsets.all(AppSpace.md), child: LinearProgressIndicator()),
            if (_result != null && !_searching) ...[
              const SizedBox(height: AppSpace.sm),
              if (_result!.tooMany)
                const InlineNotice(message: 'Çok fazla sonuç var. Aramayı daraltın (örn. e-postanın tamamını yazın).', tone: AppTone.warning)
              else if (_result!.items.isEmpty)
                const InlineNotice(
                  message: 'Bu bilgilerle eşleşen kişi bulunamadı. E-posta ya da telefon numarasının tamamını yazın.',
                  tone: AppTone.info,
                )
              else
                RadioGroup<String>(
                  groupValue: _selected,
                  onChanged: (v) => setState(() {
                    _selected = v;
                    _error = null;
                  }),
                  child: Column(
                    children: [
                      for (final c in _result!.items)
                        RadioListTile<String>(
                          value: c.handle,
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.displayName),
                          subtitle: Text(c.displayEmail),
                        ),
                    ],
                  ),
                ),
            ],
          ],
          const SizedBox(height: AppSpace.sm),
          if (widget.tenantMode)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _delegate,
              onChanged: (v) => setState(() => _delegate = v),
              title: const Text('Yönetimi kiracıya devret'),
              subtitle: const Text('Açıksa daire yönetimi kiracıya geçer ve kiracı çıkana kadar sürer.'),
            )
          else
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _minor,
              onChanged: (v) => setState(() => _minor = v ?? false),
              title: const Text('18 yaşından küçük'),
              subtitle: const Text('İşaretlenmezse yetişkin sayılır. Yetişkin üyeyi tek başınıza çıkaramazsınız.'),
            ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            InlineNotice(message: _error!),
          ],
        ],
      ),
    );
  }
}

/// Malik: kiracıya vekalet verme (kapsam + tarih aralığı, en çok 1 yıl).
class ProxyDialogResult {
  const ProxyDialogResult({required this.scope, this.validFrom, this.validUntil});

  final String scope;
  final String? validFrom;
  final String? validUntil;
}

class ProxyDialog extends StatefulWidget {
  const ProxyDialog({super.key, required this.tenantName});

  final String tenantName;

  static Future<ProxyDialogResult?> show(BuildContext context, {required String tenantName}) =>
      showDialog<ProxyDialogResult>(context: context, builder: (_) => ProxyDialog(tenantName: tenantName));

  @override
  State<ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<ProxyDialog> {
  String _scope = 'toplanti_imza';
  DateTime? _until;

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _until ?? now.add(const Duration(days: 364)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Vekaletin bitiş tarihi',
    );
    if (picked != null && mounted) setState(() => _until = picked);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final secondary = th.bodySmall?.copyWith(color: context.palette.textSecondary);
    return AppDialog(
      title: 'Vekalet ver',
      icon: Icons.assignment_ind_rounded,
      actions: [
        TextButton(onPressed: () => popIfCurrent(context), child: const Text('Vazgeç')),
        ElevatedButton(
          onPressed: () => popIfCurrent(context, ProxyDialogResult(scope: _scope, validUntil: _until == null ? null : _fmt(_until!))),
          child: const Text('Vekalet ver'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ben (malik) ${widget.tenantName} kişisine vekalet verdim.', style: th.bodyMedium),
          const SizedBox(height: AppSpace.md),
          RadioGroup<String>(
            groupValue: _scope,
            onChanged: (v) => setState(() => _scope = v ?? _scope),
            child: const Column(
              children: [
                RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'toplanti_imza', title: Text('Toplantı kararlarına imza atma')),
                RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'kurul_uyeligi', title: Text('Yönetim kuruluna katılma')),
              ],
            ),
          ),
          PrimaryActionButton(
            label: _until == null ? 'Bitiş: 1 yıl (varsayılan)' : 'Bitiş: ${_fmt(_until!)}',
            icon: Icons.event_rounded,
            variant: AppButtonVariant.outline,
            onPressed: _pickUntil,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Vekalet en çok 1 yıl geçerlidir ve istediğiniz zaman iptal edilebilir. Vekalet yoksa toplantıda imza hakkı maliktedir. '
            'Bu kayıt uygulama içi bir kayıttır; resmi genel kurulda yazılı vekaletname gerekebilir.',
            style: secondary,
          ),
        ],
      ),
    );
  }
}

/// Gizli güvenlik talebi: kısa serbest metin + isteğe bağlı iletişim tercihi. Yalnızca site yöneticisi görür.
class SafetyRequestInput {
  const SafetyRequestInput({required this.message, this.contactPref});

  final String message;
  final String? contactPref;
}

class SafetyRequestDialog extends StatefulWidget {
  const SafetyRequestDialog({super.key});

  static Future<SafetyRequestInput?> show(BuildContext context) =>
      showDialog<SafetyRequestInput>(context: context, builder: (_) => const SafetyRequestDialog());

  @override
  State<SafetyRequestDialog> createState() => _SafetyRequestDialogState();
}

class _SafetyRequestDialogState extends State<SafetyRequestDialog> {
  final _message = TextEditingController();
  String? _pref;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppDialog(
      title: 'Site yönetimine gizli talep',
      icon: Icons.shield_outlined,
      actions: [
        TextButton(onPressed: () => popIfCurrent(context), child: const Text('Vazgeç')),
        ElevatedButton(
          onPressed: () {
            final text = _message.text.trim();
            if (text.isEmpty) {
              setState(() => _error = 'Kısaca durumu yazın.');
              return;
            }
            popIfCurrent(context, SafetyRequestInput(message: text, contactPref: _pref));
          },
          child: const Text('Gönder'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Talebinizi yalnızca site yöneticisi görür. Daire yöneticisi, malik ve diğer üyeler görmez ve haberdar edilmez.',
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _message,
            maxLines: 5,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Durumunuzu kısaca yazın'),
          ),
          const SizedBox(height: AppSpace.sm),
          DropdownButtonFormField<String?>(
            initialValue: _pref,
            decoration: const InputDecoration(labelText: 'Size nasıl ulaşılsın? (isteğe bağlı)'),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Belirtmek istemiyorum')),
              DropdownMenuItem<String?>(value: 'phone', child: Text('Telefonla')),
              DropdownMenuItem<String?>(value: 'email', child: Text('E-postayla')),
              DropdownMenuItem<String?>(value: 'app', child: Text('Uygulama içinden')),
            ],
            onChanged: (v) => setState(() => _pref = v),
          ),
          if (_error != null) ...[const SizedBox(height: AppSpace.sm), InlineNotice(message: _error!)],
        ],
      ),
    );
  }
}
