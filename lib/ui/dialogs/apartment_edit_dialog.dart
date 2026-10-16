import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

/// Alan (m²) girişini sayıya çevirir; geçersizse null.
///
/// - Üstel gösterim ("1e3"), işaret, harf ve boşluk REDDEDİLİR.
/// - Yalnız bir ayırıcı ("." ya da ",") varsa ondalıktır ("120,5", "99.25").
/// - İki ayırıcı türü birden varsa SON ayırıcı ondalık, öncekiler binliktir ("1.234,5" ve "1,234.5" -> 1234.5);
///   aynı ayırıcı birden çok kez geçiyorsa hepsi binliktir ("1.234.567") ve binlik grupları 3 hane olmalıdır.
double? parseAreaInput(String? text) {
  final value = (text ?? '').trim();
  if (value.isEmpty) return null;
  if (!RegExp(r'^[0-9]+(?:[.,][0-9]+)*$').hasMatch(value)) return null;
  final separators = RegExp(r'[.,]').allMatches(value).toList();
  if (separators.isEmpty) return double.tryParse(value);
  if (separators.length == 1) {
    return double.tryParse(value.replaceAll(',', '.'));
  }

  bool thousandGroupsOk(List<String> groups) =>
      groups.first.length <= 3 && groups.skip(1).every((g) => g.length == 3);

  final kinds = separators.map((m) => m.group(0)).toSet();
  if (kinds.length == 1) {
    final groups = value.split(kinds.single!);
    return thousandGroupsOk(groups) ? double.tryParse(groups.join()) : null;
  }
  final decimalSeparator = value.substring(
    separators.last.start,
    separators.last.end,
  );
  final thousandSeparator = decimalSeparator == '.' ? ',' : '.';
  final index = value.lastIndexOf(decimalSeparator);
  final integerPart = value.substring(0, index);
  final fraction = value.substring(index + 1);
  if (integerPart.contains(decimalSeparator)) return null;
  final groups = integerPart.split(thousandSeparator);
  if (!thousandGroupsOk(groups)) return null;
  return double.tryParse('${groups.join()}.$fraction');
}

/// Daire bilgilerini düzenleme penceresi (Platform Faz 2a): kat, brüt / net m², arsa payı (pay /
/// payda), kategori ve "Borç ve bildirimler kime gitsin" (Malik / Kiracı / İkisi).
///
/// Blok ve daire etiketi bu pencereyle DEĞİŞMEZ. Yalnız değişen alanlar gönderilir; hiçbiri
/// değişmediyse sunucuya gitmeden kapanır. Arsa payında pay ve payda birlikte dolu ya da birlikte boş
/// olmalı, payda > 0 ve pay <= payda (sunucuyla aynı kural). Sunucu reddi pencerenin içinde Türkçe
/// gösterilir ve pencere açık kalır. Başarıda güncel [ApartmentDetail] ile kapanır.
class ApartmentEditDialog extends StatefulWidget {
  const ApartmentEditDialog({
    super.key,
    required this.scope,
    required this.apartment,
  });

  final PeopleScope scope;
  final ApartmentDetail apartment;

  static const int maxCategoryLength = 40;

  static Future<ApartmentDetail?> show(
    BuildContext context, {
    required PeopleScope scope,
    required ApartmentDetail apartment,
  }) {
    return showDialog<ApartmentDetail>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ApartmentEditDialog(scope: scope, apartment: apartment),
    );
  }

  @override
  State<ApartmentEditDialog> createState() => _ApartmentEditDialogState();
}

class _ApartmentEditDialogState extends State<ApartmentEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final ApartmentDetail _initial = widget.apartment;
  late final TextEditingController _floor = TextEditingController(
    text: _initial.floor?.toString() ?? '',
  );
  late final TextEditingController _gross = TextEditingController(
    text: _initial.grossAreaM2 == null
        ? ''
        : formatNumber(_initial.grossAreaM2!),
  );
  late final TextEditingController _net = TextEditingController(
    text: _initial.netAreaM2 == null ? '' : formatNumber(_initial.netAreaM2!),
  );
  late final TextEditingController _numerator = TextEditingController(
    text: _initial.landShare?.numerator.toString() ?? '',
  );
  late final TextEditingController _denominator = TextEditingController(
    text: _initial.landShare?.denominator.toString() ?? '',
  );
  late final TextEditingController _category = TextEditingController(
    text: _initial.category ?? '',
  );
  late ResponsibleParty _party = _initial.responsibleParty;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _floor.dispose();
    _gross.dispose();
    _net.dispose();
    _numerator.dispose();
    _denominator.dispose();
    _category.dispose();
    super.dispose();
  }

  static int? _parseInt(String text) => int.tryParse(text.trim());

  static double? _parseArea(String text) => parseAreaInput(text);

  String? _validateFloor(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final parsed = _parseInt(text);
    if (parsed == null || parsed < -20 || parsed > 500) {
      return 'Kat -20 ile 500 arasında bir tam sayı olmalı.';
    }
    return null;
  }

  String? _validateArea(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final parsed = _parseArea(text);
    if (parsed == null ||
        !parsed.isFinite ||
        parsed <= 0 ||
        parsed > 999999.99) {
      return 'Alan 0\'dan büyük bir sayı olmalı (örn. 120,5).';
    }
    return null;
  }

  /// Arsa payı: ikisi de boş ya da ikisi de dolu ve geçerli kesir.
  String? _validateLandShare() {
    final n = _numerator.text.trim();
    final d = _denominator.text.trim();
    if (n.isEmpty && d.isEmpty) return null;
    if (n.isEmpty || d.isEmpty) {
      return 'Arsa payı için pay ve payda birlikte girilmeli.';
    }
    final numerator = _parseInt(n);
    final denominator = _parseInt(d);
    if (!LandShare.isValid(numerator, denominator) ||
        denominator! > 1000000000) {
      return 'Arsa payı geçersiz: payda 0\'dan büyük, pay payı aşmamalı.';
    }
    return null;
  }

  Map<String, Object?> _changedFields() {
    final fields = <String, Object?>{};
    final floor = _floor.text.trim().isEmpty ? null : _parseInt(_floor.text);
    if (floor != _initial.floor) fields['floor'] = floor;

    double? roundArea(double? v) => v == null ? null : (v * 100).round() / 100;
    final gross = _gross.text.trim().isEmpty
        ? null
        : roundArea(_parseArea(_gross.text));
    if (gross != roundArea(_initial.grossAreaM2)) {
      fields['gross_area_m2'] = gross;
    }
    final net = _net.text.trim().isEmpty
        ? null
        : roundArea(_parseArea(_net.text));
    if (net != roundArea(_initial.netAreaM2)) fields['net_area_m2'] = net;

    final hasShare = _numerator.text.trim().isNotEmpty;
    final numerator = hasShare ? _parseInt(_numerator.text) : null;
    final denominator = hasShare ? _parseInt(_denominator.text) : null;
    if (numerator != _initial.landShare?.numerator ||
        denominator != _initial.landShare?.denominator) {
      fields['land_share_numerator'] = numerator;
      fields['land_share_denominator'] = denominator;
    }

    final category = _category.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (category != (_initial.category ?? '')) {
      fields['category'] = category.isEmpty ? null : category;
    }
    if (_party != _initial.responsibleParty) {
      fields['responsible_party'] = _party.apiValue;
    }
    return fields;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!validateForm(_formKey)) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final shareError = _validateLandShare();
    if (shareError != null) {
      setState(() => _error = shareError);
      return;
    }
    FocusScope.of(context).unfocus();
    final fields = _changedFields();
    if (fields.isEmpty) {
      popIfCurrent(context, _initial);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.scope.authService.updateApartment(
        widget.scope.siteCode,
        _initial.id,
        fields,
      );
      if (!mounted) return;
      popIfCurrent(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = crmMessageOf(
          e,
          'Daire kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return PopScope(
      canPop: !_submitting,
      child: AppDialog(
        title: 'Daireyi Düzenle',
        subtitle: _initial.fullLabel,
        icon: Icons.edit_rounded,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => popIfCurrent(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Kaydediliyor...' : 'Kaydet'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) CrmFormError(message: _error!),
              TextFormField(
                key: const ValueKey<String>('apartment_floor'),
                controller: _floor,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Kat',
                  prefixIcon: Icon(Icons.layers_rounded),
                ),
                validator: _validateFloor,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('apartment_gross'),
                controller: _gross,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Brüt alan (m²)',
                  prefixIcon: Icon(Icons.square_foot_rounded),
                ),
                validator: _validateArea,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('apartment_net'),
                controller: _net,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Net alan (m²)',
                  prefixIcon: Icon(Icons.square_foot_rounded),
                ),
                validator: _validateArea,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('apartment_numerator'),
                controller: _numerator,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Arsa payı - pay',
                  helperText: 'Örn. 35/1000 için 35',
                  prefixIcon: Icon(Icons.pie_chart_rounded),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isNotEmpty && _parseInt(text) == null) {
                    return 'Pay tam sayı olmalı.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('apartment_denominator'),
                controller: _denominator,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Arsa payı - payda',
                  helperText: 'Örn. 35/1000 için 1000',
                  prefixIcon: Icon(Icons.pie_chart_outline_rounded),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isNotEmpty && _parseInt(text) == null) {
                    return 'Payda tam sayı olmalı.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('apartment_category'),
                controller: _category,
                enabled: !_submitting,
                maxLength: ApartmentEditDialog.maxCategoryLength,
                decoration: const InputDecoration(
                  labelText: 'Kategori',
                  hintText: 'Örn. 3+1, Dükkan',
                  prefixIcon: Icon(Icons.category_rounded),
                  counterText: '',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<ResponsibleParty>(
                key: const ValueKey<String>('apartment_party'),
                isExpanded: true,
                initialValue: _party,
                dropdownColor: p.surface,
                style: th.bodyLarge?.copyWith(color: p.text),
                decoration: const InputDecoration(
                  labelText: 'Borç ve bildirimler kime gitsin',
                  prefixIcon: Icon(Icons.notifications_active_rounded),
                ),
                items: [
                  for (final party in ResponsibleParty.values)
                    DropdownMenuItem<ResponsibleParty>(
                      value: party,
                      child: Text(
                        party.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value != null) setState(() => _party = value);
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
