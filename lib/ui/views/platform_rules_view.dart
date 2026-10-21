import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/platform_rule.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/platform_rules_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/platform_rule_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Kurallar" tam sayfası (karar G11; docs/PLATFORM_KURALLAR.md): gecikme tazminatı üst sınırı, işletme projesi süreleri, ısınma payı, tahmin ve
/// saklama süreleri gibi koddan değil tablodan okunan değerler.
///
/// - Süper kullanıcı ([canEdit] true): `GET /admin/rules` (platform geneli ya da [siteCode] ile site görünümü); her kuralda "Değiştir" (sınır
///   içinde; kilitli kural değiştirilemez; site görünümünde yalnız sitede değişebilen kurallar).
/// - Site yöneticisi ([canEdit] false): `GET /manager/sites/:siteCode/rules`, salt okunur.
/// - Yükleme hatası "kural yok" demez: hata + "Tekrar Dene"; yenilemede eldeki liste korunur.
class PlatformRulesScreen extends StatefulWidget {
  const PlatformRulesScreen({
    super.key,
    required this.authService,
    this.service,
    this.siteCode,
    this.siteName,
    this.canEdit = false,
  }) : assert(canEdit || siteCode != null, 'Salt okunur görünüm bir site ister');

  final AuthService authService;

  /// Testler için; verilmezse [authService] üzerinden kurulur.
  final PlatformRulesService? service;
  final int? siteCode;
  final String? siteName;
  final bool canEdit;

  static Future<void> open(
    BuildContext context, {
    required AuthService authService,
    required bool canEdit,
    int? siteCode,
    String? siteName,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlatformRulesScreen(authService: authService, canEdit: canEdit, siteCode: siteCode, siteName: siteName),
      ),
    );
  }

  @override
  State<PlatformRulesScreen> createState() => PlatformRulesScreenState();
}

class PlatformRulesScreenState extends State<PlatformRulesScreen> {
  late final PlatformRulesService _service = widget.service ?? PlatformRulesService(authService: widget.authService);
  PlatformRulesView? _view;
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
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final view = widget.canEdit ? await _service.listAdmin(siteCode: widget.siteCode) : await _service.listForSite(widget.siteCode!);
      if (!mounted || token != _token) return;
      setState(() {
        _view = view;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = e is ApiException && e.message.trim().isNotEmpty ? e.message : 'Kurallar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      });
    }
  }

  Future<void> _edit(PlatformRule rule) async {
    final view = _view;
    if (view == null || _loading) return;
    final pair = rule.pair;
    final updated = await PlatformRuleDialog.show(
      context,
      rule: rule,
      partner: pair == null ? null : view.byKey(pair.key),
      siteScope: view.isSiteScope,
      onDate: view.onDate,
      siteName: view.siteName ?? widget.siteName,
      submit: (edit) => _service.update(changes: edit.changes, siteCode: view.siteCode, validFrom: edit.validFrom, note: edit.note),
    );
    if (updated == null || !mounted) return;
    ++_token;
    setState(() {
      _view = updated;
      _loading = false;
      _error = null;
    });
    final message = updated.changed.isEmpty ? 'Değer zaten bu; değişiklik yapılmadı.' : 'Kural kaydedildi.';
    AppSnack.show(context, message, kind: updated.changed.isEmpty ? AppSnackKind.info : AppSnackKind.success);
    announcePolite(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final Widget content;
    if (view == null) {
      content = _loading
          ? const ListSkeleton(rows: 4)
          : InlineNotice(key: const ValueKey<String>('rules_load_error'), message: _error ?? 'Kurallar yüklenemedi.', onRetry: reload);
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InlineNotice(message: _error!, onRetry: _loading ? null : reload),
            const SizedBox(height: AppSpace.md),
          ],
          _ScopeCard(view: view, canEdit: widget.canEdit, fallbackSiteName: widget.siteName),
          for (final group in view.groups)
            if (view.itemsIn(group.code).isNotEmpty) ...[
              const SizedBox(height: AppSpace.xl),
              SectionHeader(title: group.label, icon: _groupIcon(group.code)),
              const SizedBox(height: AppSpace.md),
              for (final rule in view.itemsIn(group.code)) ...[
                _RuleCard(rule: rule, siteScope: view.isSiteScope, canEdit: widget.canEdit && view.canEdit, onEdit: () => _edit(rule)),
                const SizedBox(height: AppSpace.md),
              ],
            ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kurallar'),
        actions: [
          IconButton(
            key: const ValueKey<String>('rules_refresh'),
            tooltip: 'Yenile',
            onPressed: _loading ? null : reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpace.lg),
            children: [content],
          ),
        ),
      ),
    );
  }

  static IconData _groupIcon(String code) => switch (code) {
    'finance' => Icons.account_balance_wallet_outlined,
    'budget' => Icons.event_note_outlined,
    'heat' => Icons.thermostat_outlined,
    'forecast' => Icons.trending_up_rounded,
    'retention' => Icons.inventory_2_outlined,
    _ => Icons.rule_rounded,
  };
}

/// Sayfanın kapsam kartı: platform geneli / site ve kimin değiştirebildiği.
class _ScopeCard extends StatelessWidget {
  const _ScopeCard({required this.view, required this.canEdit, this.fallbackSiteName});

  final PlatformRulesView view;
  final bool canEdit;
  final String? fallbackSiteName;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final siteName = view.siteName ?? fallbackSiteName;
    final title = view.isSiteScope ? (siteName == null || siteName.isEmpty ? 'Site' : siteName) : 'Platform geneli';
    final String body;
    if (!canEdit) {
      body = 'Sitenizde geçerli kurallar. Değerleri yalnızca sistem yöneticisi değiştirebilir; değişiklik gerekiyorsa sistem yöneticisine başvurun.';
    } else if (view.isSiteScope) {
      body = 'Bu sitede geçerli değerler. Burada yalnızca sitede değişebilen kurallar değiştirilir; diğerleri platform genelinden değiştirilir.';
    } else {
      body = 'Tüm sitelerde geçerli değerler. Her değer kendi sınırı içinde değiştirilir ve değişiklik denetim kaydına yazılır. Yasal üst sınırlar '
          '(ör. aylık %5 gecikme tazminatı) aşılamaz.';
    }
    return AppCard(
      key: const ValueKey<String>('rules_scope'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: th.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: AppSpace.xs),
          Text(body, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
          if (view.onDate.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text('${formatRuleDate(view.onDate)} itibarıyla.', style: th.bodySmall?.copyWith(color: p.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// Tek kural kartı.
class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule, required this.siteScope, required this.canEdit, required this.onEdit});

  final PlatformRule rule;
  final bool siteScope;
  final bool canEdit;
  final VoidCallback onEdit;

  Widget _line(BuildContext context, String text, {IconData? icon, Key? key}) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final style = th.bodySmall?.copyWith(color: p.textSecondary);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: icon == null
          ? Text(text, style: style)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: p.textSecondary)),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(text, style: style)),
              ],
            ),
    );
  }

  String _scheduledText(PlatformRuleScheduled entry) {
    final what = entry.inherit ? (entry.isSite ? 'platform değeri' : 'varsayılan değer') : formatRuleValue(rule, entry.value);
    // Site görünümünde planlı platform değeri kapsamıyla yazılır: siteye özel değer varken bu siteyi değiştirmez.
    final scope = entry.isSite ? ' (bu site)' : (siteScope ? ' (platform geneli)' : '');
    return 'Planlı: ${formatRuleDate(entry.validFrom)} tarihinden itibaren $what$scope';
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final range = formatRuleRange(rule);
    final effective = rule.effective;
    final changedBy = siteScope && effective.source == PlatformRuleSource.site ? rule.site : rule.platform;
    final editable = rule.editableIn(siteScope: siteScope);
    return AppCard(
      key: ValueKey<String>('rule_${rule.key}'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rule.label, style: th.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                formatRuleValue(rule, effective.value),
                key: ValueKey<String>('rule_value_${rule.key}'),
                style: th.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: p.text),
              ),
              InfoChip(ruleSourceLabel(effective.source)),
            ],
          ),
          if (rule.description.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(rule.description, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
          ],
          if (range.isNotEmpty) _line(context, 'Sınır: $range'),
          _line(context, 'Varsayılan: ${formatRuleValue(rule, rule.defaultValue)}'),
          if (siteScope && effective.source == PlatformRuleSource.site) _line(context, 'Platform değeri: ${formatRuleValue(rule, rule.platform.value)}'),
          if (effective.validFrom != null) _line(context, '${formatRuleDate(effective.validFrom)} tarihinden beri geçerli'),
          for (final entry in rule.scheduled) _line(context, _scheduledText(entry), icon: Icons.schedule_rounded),
          if (changedBy?.updatedByName != null)
            _line(context, 'Son değiştiren: ${changedBy!.updatedByName}${changedBy.validFrom == null ? '' : ' (${formatRuleDate(changedBy.validFrom)})'}'),
          if (changedBy?.note != null) _line(context, 'Not: ${changedBy!.note}'),
          if (!rule.editable && rule.lockedReason != null) _line(context, rule.lockedReason!, icon: Icons.lock_outline_rounded),
          if (rule.legalNote.isNotEmpty) _line(context, 'Mevzuat notu: ${rule.legalNote}', icon: Icons.gavel_rounded),
          if (canEdit && editable) ...[
            const SizedBox(height: AppSpace.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PrimaryActionButton(
                key: ValueKey<String>('rule_edit_${rule.key}'),
                label: 'Değiştir',
                icon: Icons.edit_outlined,
                variant: AppButtonVariant.outline,
                expand: false,
                onPressed: onEdit,
              ),
            ),
          ] else if (canEdit && siteScope && rule.editable && !rule.siteOverridable)
            _line(context, 'Platform genelinden değiştirilir.', icon: Icons.public_rounded, key: ValueKey<String>('rule_platform_only_${rule.key}')),
        ],
      ),
    );
  }
}
