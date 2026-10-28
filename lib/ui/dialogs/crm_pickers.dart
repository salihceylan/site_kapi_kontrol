import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

/// Arama kutulu, sayfalı seçici pencere (daire / kişi seçimi). Seçilen kayıtla kapanır; vazgeçilirse
/// null döner. Arama duraksayınca (350 ms) ya da klavyeden gönderilince çalışır; art arda aramada eski
/// yanıt yenisini ezmez ([PagedLoader] jetonu).
class CrmPickerDialog<T> extends StatefulWidget {
  const CrmPickerDialog({
    super.key,
    required this.title,
    required this.icon,
    required this.searchLabel,
    required this.fetch,
    required this.keyOf,
    required this.titleOf,
    this.subtitleOf,
    this.emptyTitle = 'Kayıt bulunamadı.',
  });

  final String title;
  final IconData icon;
  final String searchLabel;

  /// Arama metni, başlangıç sırası ve sayfa boyutuyla sayfa getirir.
  final Future<PagedResult<T>> Function(String query, int offset, int limit) fetch;
  final Object Function(T item) keyOf;
  final String Function(T item) titleOf;
  final String? Function(T item)? subtitleOf;
  final String emptyTitle;

  static Future<T?> show<T>(BuildContext context, CrmPickerDialog<T> dialog) {
    return showDialog<T>(context: context, builder: (_) => dialog);
  }

  @override
  State<CrmPickerDialog<T>> createState() => _CrmPickerDialogState<T>();
}

class _CrmPickerDialogState<T> extends State<CrmPickerDialog<T>> {
  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  late final PagedLoader<T> _loader = PagedLoader<T>(
    fetch: (offset, limit) => widget.fetch(_query, offset, limit),
    keyOf: widget.keyOf,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    pageSize: 30,
    errorFallback: 'Liste yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
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

  void _runSearch() {
    _timer?.cancel();
    final next = _search.text.trim();
    if (next == _query && _loader.loadedOnce && _loader.error == null) return;
    _query = next;
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _onChanged(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _runSearch);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return AppDialog(
      title: widget.title,
      icon: widget.icon,
      actions: [
        TextButton(
          onPressed: () => popIfCurrent(context),
          child: const Text('Vazgeç'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (_) => _runSearch(),
            decoration: InputDecoration(
              labelText: widget.searchLabel,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Aramayı temizle',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        _runSearch();
                        setState(() {});
                      },
                    ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          CrmListBody<T>(
            loader: _loader,
            emptyIcon: Icons.search_off_rounded,
            emptyTitle: widget.emptyTitle,
            filtered: _query.isNotEmpty,
            skeletonRows: 2,
            itemBuilder: (context, item) {
              final subtitle = widget.subtitleOf?.call(item);
              return AppCard(
                padding: const EdgeInsets.all(AppSpace.md),
                // Çift dokunuş ikinci `pop` ile üstteki formu da kapatmasın: yol artık güncel değilse yok sayılır.
                onTap: () => popIfCurrent(context, item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.titleOf(item), style: th.titleSmall),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: th.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Daire seçici: sitenin dairelerini arar. Seçilen [ApartmentSummary] ile kapanır.
Future<ApartmentSummary?> showApartmentPicker(
  BuildContext context,
  PeopleScope scope, {
  String title = 'Daire Seç',
}) {
  return CrmPickerDialog.show<ApartmentSummary>(
    context,
    CrmPickerDialog<ApartmentSummary>(
      title: title,
      icon: Icons.apartment_rounded,
      searchLabel: 'Daire ara',
      emptyTitle: 'Daire bulunamadı.',
      fetch: (query, offset, limit) async {
        final page = await scope.authService.listApartments(
          scope.siteCode,
          query: query,
          limit: limit,
          offset: offset,
        );
        return (items: page.items, total: page.total);
      },
      keyOf: (a) => a.id,
      titleOf: (a) => a.fullLabel,
      subtitleOf: (a) {
        final parts = <String>[
          if (a.owner != null) 'Malik: ${crmPersonName(a.owner!.fullName)}${a.ownerCount > 1 ? ' (+${a.ownerCount - 1} malik)' : ''}',
          if (a.tenant != null) 'Kiracı: ${crmPersonName(a.tenant!.fullName)}',
        ];
        return parts.isEmpty ? null : parts.join(' • ');
      },
    ),
  );
}

/// Kişi seçici: sitenin aktif kişilerini arar. Seçilen [PersonSummary] ile kapanır.
Future<PersonSummary?> showPersonPicker(
  BuildContext context,
  PeopleScope scope, {
  String title = 'Kişi Seç',
}) {
  return CrmPickerDialog.show<PersonSummary>(
    context,
    CrmPickerDialog<PersonSummary>(
      title: title,
      icon: Icons.person_search_rounded,
      searchLabel: 'Kişi ara',
      emptyTitle: 'Kişi bulunamadı.',
      fetch: (query, offset, limit) async {
        final page = await scope.authService.listPeople(
          scope.siteCode,
          query: query,
          status: 'active',
          limit: limit,
          offset: offset,
        );
        return (items: page.items, total: page.total);
      },
      keyOf: (p) => p.id,
      titleOf: (p) => crmPersonName(p.fullName),
      subtitleOf: (p) {
        final parts = <String>[
          for (final a in p.apartments) a.fullLabel,
          if ((p.phone ?? '').isNotEmpty) p.phone!,
        ];
        return parts.isEmpty ? null : parts.join(' • ');
      },
    ),
  );
}

/// Seçici alanı: form içinde giriş kutusu gibi görünür, dokununca seçici pencere açılır. [value] null
/// iken [placeholder] soluk yazılır. Metin sarar (kırpılmaz).
class CrmPickerField extends StatelessWidget {
  const CrmPickerField({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.value,
    this.placeholder = 'Seçmek için dokunun',
    this.errorText,
    this.onClear,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final String? value;
  final String placeholder;
  final String? errorText;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final hasValue = value != null && value!.isNotEmpty;
    // Anlamsal ağaç AÇIK bırakılır (excludeSemantics YOK): etiket, seçili değer / yer tutucu, hata metni
    // (InputDecorator errorText) ve "Seçimi temizle" düğmesi ekran okuyucuya ulaşır; temizle düğmesi kendi
    // dokunma eylemiyle ayrı bir düğümdür.
    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InputDecorator(
          // Etiket hep yukarıda durur: boşken yer tutucu metin etiketle üst üste binmesin.
          isEmpty: false,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            errorText: errorText,
            suffixIcon: hasValue && onClear != null && enabled
                ? IconButton(
                    tooltip: 'Seçimi temizle',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onClear,
                  )
                : const Icon(Icons.arrow_drop_down_rounded),
          ),
          child: Text(
            hasValue ? value! : placeholder,
            style: th.bodyLarge?.copyWith(
              color: hasValue ? p.text : p.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
