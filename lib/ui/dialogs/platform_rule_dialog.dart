import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/platform_rule.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/platform_rules_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';

/// Tek kuralın değişikliği: yazılacak değişiklikler (çift kuralda iki anahtar), geçerlilik tarihi ('YYYY-MM-DD'; null = bugün) ve not.
@immutable
class PlatformRuleEdit {
  const PlatformRuleEdit({required this.changes, this.validFrom, this.note});

  final List<PlatformRuleChange> changes;
  final String? validFrom;
  final String? note;
}

/// "Kuralı değiştir" penceresi (yalnız süper kullanıcı; docs/PLATFORM_KURALLAR.md).
///
/// - Değer sınır içinde girilir (baz puan kuralında yüzde: "4,50"); sınır dışı değer kaydedilmeden önce reddedilir.
/// - Süresiz olabilen kuralda "Süresiz" anahtarı; site kapsamında site değeri varsa "Platform değerini kullan" (üst düzeye dön).
/// - Isı payı gibi çift kurallarda eşinin değeri toplamdan hesaplanıp birlikte gönderilir (toplam her zaman 100).
/// - Planlanabilen kuralda geçerlilik tarihi (bugün .. 5 yıl sonrası); planlanamayan kural bugünden geçerlidir.
/// - Sunucu reddi (alan metni) pencerede gösterilir ve pencere AÇIK kalır; başarıda güncel görünümle kapanır.
class PlatformRuleDialog extends StatefulWidget {
  const PlatformRuleDialog({
    super.key,
    required this.rule,
    required this.siteScope,
    required this.onDate,
    required this.submit,
    this.partner,
    this.siteName,
  });

  final PlatformRule rule;

  /// Çift kuralın eşi (ör. ölçüme göre payın eşi alana göre pay); yoksa null.
  final PlatformRule? partner;

  /// true: siteye özel değer yazılır.
  final bool siteScope;

  /// Görünümün bugünü ('YYYY-MM-DD', İstanbul).
  final String onDate;
  final String? siteName;

  /// Kaydetme: güncel görünümü döndürür ya da [ApiException] fırlatır.
  final Future<PlatformRulesView> Function(PlatformRuleEdit edit) submit;

  static const int maxNoteLength = 200;
  static const int scheduleYears = 5;

  static Future<PlatformRulesView?> show(
    BuildContext context, {
    required PlatformRule rule,
    required bool siteScope,
    required String onDate,
    required Future<PlatformRulesView> Function(PlatformRuleEdit edit) submit,
    PlatformRule? partner,
    String? siteName,
  }) {
    return showDialog<PlatformRulesView>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PlatformRuleDialog(
        rule: rule,
        partner: partner,
        siteScope: siteScope,
        onDate: onDate,
        siteName: siteName,
        submit: submit,
      ),
    );
  }

  @override
  State<PlatformRuleDialog> createState() => PlatformRuleDialogState();
}

class PlatformRuleDialogState extends State<PlatformRuleDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _value;
  late final TextEditingController _date;
  final TextEditingController _note = TextEditingController();
  late bool _indefinite;
  late bool _boolValue;
  bool _inherit = false;
  bool _saving = false;
  String? _error;

  PlatformRule get _rule => widget.rule;

  /// Bu kapsamdaki şu anki değer (site kapsamında etkin değer, platformda platform değeri).
  Object? get _current => widget.siteScope ? _rule.effective.value : _rule.platform.value;

  /// Görünümün bugünü (sunucunun İstanbul günü); okunamazsa cihazın bugünü.
  DateTime get _today {
    final date = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(widget.onDate) ? DateTime.tryParse(widget.onDate) : null;
    final base = date ?? DateTime.now();
    return DateTime(base.year, base.month, base.day);
  }

  @override
  void initState() {
    super.initState();
    _value = TextEditingController(text: ruleInputText(_rule, _current));
    _date = TextEditingController(text: formatDateField(_today));
    _indefinite = _rule.nullable && _current == null;
    _boolValue = _current == true;
  }

  @override
  void dispose() {
    _value.dispose();
    _date.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _valueDisabled => _inherit || _indefinite || _saving;

  /// Çift kuralda eşin hesaplanan değeri (giriş geçerliyse).
  int? get _partnerValue {
    final pair = _rule.pair;
    if (pair == null || widget.partner == null) return null;
    final parsed = parseRuleInput(_rule, _value.text);
    if (parsed == null) return null;
    return pair.sum - parsed;
  }

  String? _validateValue(String? text) {
    if (_valueDisabled || !_rule.isInteger) return null;
    final basic = validateRuleInput(_rule, text);
    if (basic != null) return basic;
    final partner = widget.partner;
    final other = _partnerValue;
    if (partner != null && other != null) {
      final min = partner.min ?? 0;
      final max = partner.max ?? other;
      if (other < min || other > max) return 'Eşi olan "${partner.label}" değeri ${formatRuleRange(partner)} kalmalıdır.';
    }
    return null;
  }

  String? _validateDate(String? text) {
    if (!_rule.schedulable) return null;
    final date = parseDateField(text);
    if (date == null) return validateDateField(text) ?? 'Geçerlilik tarihini GG.AA.YYYY biçiminde girin.';
    final today = _today;
    final latest = DateTime(today.year + PlatformRuleDialog.scheduleYears, today.month, today.day);
    if (date.isBefore(today)) return 'Geçerlilik tarihi bugünden önce olamaz.';
    if (date.isAfter(latest)) return 'Geçerlilik tarihi en fazla ${PlatformRuleDialog.scheduleYears} yıl ileride olabilir.';
    return null;
  }

  static String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  PlatformRuleEdit _edit() {
    final changes = <PlatformRuleChange>[];
    if (_inherit) {
      changes.add(PlatformRuleChange.inherit(_rule.key));
    } else if (!_rule.isInteger) {
      changes.add(PlatformRuleChange(key: _rule.key, value: _boolValue));
    } else if (_indefinite) {
      changes.add(PlatformRuleChange(key: _rule.key, value: null));
    } else {
      final value = parseRuleInput(_rule, _value.text)!;
      changes.add(PlatformRuleChange(key: _rule.key, value: value));
      final partner = widget.partner;
      final pair = _rule.pair;
      if (partner != null && pair != null) changes.add(PlatformRuleChange(key: partner.key, value: pair.sum - value));
    }
    final date = _rule.schedulable ? parseDateField(_date.text) : null;
    final validFrom = date == null ? null : _iso(date);
    return PlatformRuleEdit(
      changes: changes,
      validFrom: validFrom == widget.onDate ? null : validFrom,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
  }

  Future<void> _submit() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final view = await widget.submit(_edit());
      if (!mounted) return;
      Navigator.of(context).pop(view);
    } on ApiException catch (e) {
      if (!mounted) return;
      final fields = ruleFieldErrors(e);
      setState(() {
        _saving = false;
        _error = fields[_rule.key] ?? (fields.isEmpty ? e.message : fields.values.first);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Kural kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      });
    }
  }

  Widget _hint(BuildContext context, String text, {Key? key}) {
    final th = Theme.of(context).textTheme;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Text(text, style: th.bodySmall?.copyWith(color: context.palette.textSecondary)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final rule = _rule;
    final range = formatRuleRange(rule);
    final partner = widget.partner;
    final partnerValue = _partnerValue;
    final siteName = widget.siteName;
    final current = '${formatRuleValue(rule, _current)} (${ruleSourceLabel(widget.siteScope ? rule.effective.source : rule.platform.source)})';
    final dialog = AppDialog(
      title: rule.label,
      subtitle: widget.siteScope ? 'Site: ${siteName == null || siteName.isEmpty ? 'seçili site' : siteName}' : 'Platform geneli',
      icon: Icons.rule_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('rule_dialog_cancel'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        PrimaryActionButton(
          key: const ValueKey<String>('rule_dialog_save'),
          label: 'Kaydet',
          icon: Icons.save_outlined,
          loading: _saving,
          expand: false,
          onPressed: _saving ? null : _submit,
        ),
      ],
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              InlineNotice(key: const ValueKey<String>('rule_dialog_error'), message: _error!),
              const SizedBox(height: AppSpace.md),
            ],
            Text('Şu anki değer: $current', style: th.bodyMedium?.copyWith(color: p.text)),
            if (range.isNotEmpty) _hint(context, 'Sınır: $range.'),
            if (rule.group == 'finance')
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.md),
                child: InlineNotice(
                  tone: AppTone.warning,
                  message: 'Sitelerin gecikme tazminatı oranı bu sınırı aşamaz; daha yüksek oran girilmiş sitelerde hesap bu sınırla yapılır.',
                ),
              ),
            const SizedBox(height: AppSpace.md),
            if (widget.siteScope && rule.site != null)
              SwitchListTile(
                key: const ValueKey<String>('rule_dialog_inherit'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Platform değerini kullan'),
                subtitle: Text('Siteye özel değer kaldırılır; platform değeri (${formatRuleValue(rule, rule.platform.value)}) geçerli olur.'),
                value: _inherit,
                onChanged: _saving ? null : (value) => setState(() => _inherit = value),
              ),
            if (rule.nullable)
              SwitchListTile(
                key: const ValueKey<String>('rule_dialog_indefinite'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Süresiz'),
                subtitle: const Text('Açıkken kayıtlar süre sınırı olmadan saklanır.'),
                value: _indefinite,
                onChanged: _saving || _inherit ? null : (value) => setState(() => _indefinite = value),
              ),
            if (rule.isInteger)
              TextFormField(
                key: const ValueKey<String>('rule_dialog_value'),
                controller: _value,
                enabled: !_valueDisabled,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: switch (rule.unit) {
                    PlatformRuleUnit.basisPoints => 'Yeni değer (yüzde)',
                    PlatformRuleUnit.percent => 'Yeni değer (yüzde)',
                    PlatformRuleUnit.days => 'Yeni değer (gün)',
                    PlatformRuleUnit.none => 'Yeni değer',
                  },
                  prefixText: rule.unit == PlatformRuleUnit.basisPoints || rule.unit == PlatformRuleUnit.percent ? '% ' : null,
                  suffixText: rule.unit == PlatformRuleUnit.days ? 'gün' : null,
                  helperText: rule.unit == PlatformRuleUnit.basisPoints ? 'Örn. 4,50' : null,
                ),
                validator: _validateValue,
              )
            else
              SwitchListTile(
                key: const ValueKey<String>('rule_dialog_bool'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Açık'),
                value: _boolValue,
                onChanged: _saving || _inherit ? null : (value) => setState(() => _boolValue = value),
              ),
            if (partner != null && !_inherit)
              _hint(
                context,
                partnerValue == null ? '${partner.label}: toplam ${rule.pair!.sum} olacak şekilde birlikte değişir.' : '${partner.label}: %$partnerValue (toplam ${rule.pair!.sum}).',
                key: const ValueKey<String>('rule_dialog_partner'),
              ),
            const SizedBox(height: AppSpace.md),
            if (rule.schedulable)
              TextFormField(
                key: const ValueKey<String>('rule_dialog_date'),
                controller: _date,
                enabled: !_saving,
                keyboardType: TextInputType.datetime,
                inputFormatters: const <DateInputFormatter>[DateInputFormatter()],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Geçerlilik tarihi',
                  hintText: 'GG.AA.YYYY',
                  helperText: 'Bugün ya da ileri bir tarih (en çok 5 yıl).',
                ),
                validator: _validateDate,
              )
            else
              _hint(context, 'Değişiklik bugünden geçerli olur (ileri tarihli planlanamaz).'),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              key: const ValueKey<String>('rule_dialog_note'),
              controller: _note,
              enabled: !_saving,
              maxLength: PlatformRuleDialog.maxNoteLength,
              decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', hintText: 'Örn. Kanun değişikliği'),
            ),
            _hint(context, 'Değişiklik denetim kaydına yazılır.'),
          ],
        ),
      ),
    );
    // Kayıt sürerken geri tuşu pencereyi kapatmaz (projedeki pencere kuralı): kapansa yanıt kaybolur, sayfa eski değeri gösterirdi.
    return PopScope(canPop: !_saving, child: dialog);
  }
}
