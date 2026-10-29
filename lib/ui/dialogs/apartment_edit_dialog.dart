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

/// Daire alanlarının (kat, brüt / net m², arsa payı, kategori, borç sorumlusu) giriş durumu, doğrulaması ve
/// "yalnız değişenler" farkı. [ApartmentEditDialog] ile "Kişi Ekle / Düzenle" penceresindeki "Daire bilgileri"
/// bölümü AYNI kuralları kullansın diye tek yerdedir (sunucuyla aynı sınırlar: kat -20..500, alan > 0 ve en çok
/// 999999,99, arsa payı payda > 0 ve pay <= payda).
///
/// [load] ile bir dairenin mevcut değerleri alanlara yazılır ve karşılaştırma tabanı olur; [changedFields] yalnız
/// tabandan farklı alanları `PATCH .../apartments/:id` gövdesi olarak döner (hiçbiri değişmediyse boş).
class ApartmentFieldsDraft {
  final TextEditingController floor = TextEditingController();
  final TextEditingController numerator = TextEditingController();
  final TextEditingController denominator = TextEditingController();
  final TextEditingController category = TextEditingController();
  final TextEditingController parking = TextEditingController();
  ResponsibleParty party = ResponsibleParty.both;
  ApartmentDetail? _initial;

  /// Karşılaştırma tabanı (yüklenmediyse null).
  ApartmentDetail? get initial => _initial;

  /// [apartment]'ın mevcut değerlerini alanlara yazar ve taban yapar.
  void load(ApartmentDetail apartment) {
    _initial = apartment;
    floor.text = apartment.floor?.toString() ?? '';
    numerator.text = apartment.landShare?.numerator.toString() ?? '';
    denominator.text = apartment.landShare?.denominator.toString() ?? '';
    category.text = apartment.category ?? '';
    parking.text = apartment.parkingSlots.toString();
    party = apartment.responsibleParty;
  }

  /// Tabanı ve alanları boşaltır (başka daire seçildi / seçim kalktı).
  void clear() {
    _initial = null;
    floor.clear();
    numerator.clear();
    denominator.clear();
    category.clear();
    parking.clear();
    party = ResponsibleParty.both;
  }

  void dispose() {
    floor.dispose();
    numerator.dispose();
    denominator.dispose();
    category.dispose();
    parking.dispose();
  }

  static int? _parseInt(String text) => int.tryParse(text.trim());

  static String? validateFloor(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final parsed = _parseInt(text);
    if (parsed == null || parsed < -20 || parsed > 500) {
      return 'Kat -20 ile 500 arasında bir tam sayı olmalı.';
    }
    return null;
  }

  /// Park yeri sayısı (plaka tanıma misafir kuralı): boş = 0; 0-50 arası tam sayı (sunucuyla aynı sınır).
  static String? validateParking(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final parsed = _parseInt(text);
    if (parsed == null || parsed < 0 || parsed > 50) {
      return 'Park yeri sayısı 0 ile 50 arasında bir tam sayı olmalı.';
    }
    return null;
  }

  static String? validateArea(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final parsed = parseAreaInput(text);
    if (parsed == null ||
        !parsed.isFinite ||
        parsed <= 0 ||
        parsed > 999999.99) {
      return 'Alan 0\'dan büyük bir sayı olmalı (örn. 120,5).';
    }
    return null;
  }

  static String? validateNumerator(String? value) {
    final text = (value ?? '').trim();
    if (text.isNotEmpty && _parseInt(text) == null) {
      return 'Pay tam sayı olmalı.';
    }
    return null;
  }

  static String? validateDenominator(String? value) {
    final text = (value ?? '').trim();
    if (text.isNotEmpty && _parseInt(text) == null) {
      return 'Payda tam sayı olmalı.';
    }
    return null;
  }

  /// Arsa payı: ikisi de boş ya da ikisi de dolu ve geçerli kesir.
  String? validateLandShare() {
    final n = numerator.text.trim();
    final d = denominator.text.trim();
    if (n.isEmpty && d.isEmpty) return null;
    if (n.isEmpty || d.isEmpty) {
      return 'Arsa payı için pay ve payda birlikte girilmeli.';
    }
    final parsedNumerator = _parseInt(n);
    final parsedDenominator = _parseInt(d);
    if (!LandShare.isValid(parsedNumerator, parsedDenominator) ||
        parsedDenominator! > 1000000000) {
      return 'Arsa payı geçersiz: payda 0\'dan büyük, pay payı aşmamalı.';
    }
    return null;
  }

  /// Alanların TÜMÜ (form alanı çizilmemiş olsa da): ilk hata iletisi, yoksa null.
  String? validateAll() =>
      validateFloor(floor.text) ??
      validateParking(parking.text) ??
      validateNumerator(numerator.text) ??
      validateDenominator(denominator.text) ??
      validateLandShare();

  /// Tabana göre değişen alanlar (sunucu anahtarlarıyla); taban yoksa ya da değişiklik yoksa boş.
  Map<String, Object?> changedFields() {
    final initial = _initial;
    final fields = <String, Object?>{};
    if (initial == null) return fields;
    final floorValue = floor.text.trim().isEmpty ? null : _parseInt(floor.text);
    if (floorValue != initial.floor) fields['floor'] = floorValue;
    final parkingValue = parking.text.trim().isEmpty ? 0 : (_parseInt(parking.text) ?? 0);
    if (parkingValue != initial.parkingSlots) fields['parking_slots'] = parkingValue;



    final hasShare = numerator.text.trim().isNotEmpty;
    final numeratorValue = hasShare ? _parseInt(numerator.text) : null;
    final denominatorValue = hasShare ? _parseInt(denominator.text) : null;
    if (numeratorValue != initial.landShare?.numerator ||
        denominatorValue != initial.landShare?.denominator) {
      fields['land_share_numerator'] = numeratorValue;
      fields['land_share_denominator'] = denominatorValue;
    }

    final categoryValue = category.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (categoryValue != (initial.category ?? '')) {
      fields['category'] = categoryValue.isEmpty ? null : categoryValue;
    }
    if (party != initial.responsibleParty) {
      fields['responsible_party'] = party.apiValue;
    }
    return fields;
  }
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
  late final ApartmentFieldsDraft _draft = ApartmentFieldsDraft()
    ..load(_initial);
  bool _submitting = false;
  String? _error;

  /// Arsa payı / kategori bölümü: değer girilmiş dairede açık, aksi halde katlı başlar.
  late bool _showAdvanced =
      _initial.landShare != null ||
      (_initial.category ?? '').trim().isNotEmpty;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!validateForm(_formKey)) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final shareError = _draft.validateLandShare();
    if (shareError != null) {
      setState(() => _error = shareError);
      return;
    }
    FocusScope.of(context).unfocus();
    final fields = _draft.changedFields();
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
                controller: _draft.floor,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Kat',
                  prefixIcon: Icon(Icons.layers_rounded),
                ),
                validator: ApartmentFieldsDraft.validateFloor,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('apartment_parking'),
                controller: _draft.parking,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Park yeri sayısı',
                  helperText: '0 = misafir araç otomatik kabul edilmez',
                  prefixIcon: Icon(Icons.local_parking_rounded),
                ),
                validator: ApartmentFieldsDraft.validateParking,
              ),
              const SizedBox(height: AppSpace.md),
              _partyField(),
              const SizedBox(height: AppSpace.sm),
              // Sadelik: arsa payı ve kategori çoğu sitede gerekmez (aidat eşit dağıtılır). Silinmez -
              // "arsa payına göre dağıtım" kullanan siteler için finans dağıtımında (finance_distribution.js)
              // kullanılır - ama varsayılan olarak katlı durur. Değer girilmiş dairede açık gelir.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey<String>('apartment_advanced_toggle'),
                  onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                  icon: Icon(
                    _showAdvanced
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  label: Text(
                    _showAdvanced
                        ? 'Gelişmiş bilgileri gizle'
                        : 'Gelişmiş bilgiler (arsa payı, kategori - isteğe bağlı)',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_showAdvanced) ...[
              const SizedBox(height: AppSpace.sm),
              TextFormField(
                key: const ValueKey<String>('apartment_numerator'),
                controller: _draft.numerator,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Arsa payı - pay',
                  helperText: 'Örn. 35/1000 için 35',
                  prefixIcon: Icon(Icons.pie_chart_rounded),
                ),
                validator: ApartmentFieldsDraft.validateNumerator,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('apartment_denominator'),
                controller: _draft.denominator,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Arsa payı - payda',
                  helperText: 'Örn. 35/1000 için 1000',
                  prefixIcon: Icon(Icons.pie_chart_outline_rounded),
                ),
                validator: ApartmentFieldsDraft.validateDenominator,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('apartment_category'),
                controller: _draft.category,
                enabled: !_submitting,
                maxLength: ApartmentEditDialog.maxCategoryLength,
                decoration: const InputDecoration(
                  labelText: 'Kategori',
                  hintText: 'Örn. 3+1, Dükkan',
                  prefixIcon: Icon(Icons.category_rounded),
                  counterText: '',
                ),
              ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _partyField() {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return DropdownButtonFormField<ResponsibleParty>(
      key: const ValueKey<String>('apartment_party'),
      isExpanded: true,
      initialValue: _draft.party,
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
              if (value != null) setState(() => _draft.party = value);
            },
    );
  }
}
