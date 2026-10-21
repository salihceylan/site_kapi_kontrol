import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/annual_report.dart';
import 'package:site_kapi_kontrol/services/annual_report_api.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/pdf_annual_report_service.dart';
import 'package:site_kapi_kontrol/services/pdf_decision_service.dart' show DecisionPdfOutcome;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart' show PeopleSite;

/// "Faaliyet Raporu" (`annual_report` modülü, yönetici). Yıl seçilir; sistem kayıtlardan dokuz bölümü doldurur, yönetici her
/// bölümü düzenler ("Taslağı kaydet" ile saklanır), "PDF" raporu verir. Düzenlenmeyen bölüm her açılışta güncel kayıtlardan gelir.
/// Ekipman envanteri "Yakında…" (ayrı bir ekipman kaydı henüz yok).
class AnnualReportView extends StatefulWidget {
  const AnnualReportView({super.key, required this.authService, this.service, this.sites = const <PeopleSite>[]});

  final AuthService authService;
  final AnnualReportService? service;
  final List<PeopleSite> sites;

  @override
  State<AnnualReportView> createState() => AnnualReportViewState();
}

class AnnualReportViewState extends State<AnnualReportView> {
  late AnnualReportService _service = widget.service ?? AnnualReportService(authService: widget.authService);
  late PeopleSite? _site = widget.sites.isEmpty ? null : widget.sites.first;
  late int _year = DateTime.now().year - 1;
  AnnualReport? _report;
  final Map<String, TextEditingController> _controllers = <String, TextEditingController>{};
  final TextEditingController _growth = TextEditingController(text: '0');
  bool _loading = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void didUpdateWidget(AnnualReportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.authService, widget.authService) || !identical(oldWidget.service, widget.service)) {
      _service = widget.service ?? AnnualReportService(authService: widget.authService);
    }
    final current = _site;
    if (current == null || !widget.sites.any((s) => s.code == current.code)) {
      _site = widget.sites.isEmpty ? null : widget.sites.first;
      unawaited(reload());
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _growth.dispose();
    super.dispose();
  }

  String _messageOf(Object e, String fallback) => e is ApiException && e.message.trim().isNotEmpty ? e.message : fallback;

  /// Yüzde yazısı ("12,5") -> baz puan; geçersizse null.
  static int? parseGrowthPercent(String text) {
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    if (v == null || v < -50 || v > 500) return null;
    return (v * 100).round();
  }

  String _systemText(String key) => annualReportLines(key, _report?.sections[key]).join('\n');

  Future<void> reload({bool keepGrowth = false}) async {
    final site = _site;
    if (site == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final growth = keepGrowth ? parseGrowthPercent(_growth.text) : null;
      final report = await _service.load(site.code, _year, growthBp: growth);
      if (!mounted) return;
      _fill(report);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _messageOf(e, 'Faaliyet raporu yüklenemedi.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(AnnualReport report) {
    _report = report;
    _growth.text = (report.growthBp / 100).toString().replaceAll('.', ',').replaceAll(RegExp(r',0$'), '');
    for (final key in kAnnualReportSections) {
      final text = report.edits[key] ?? annualReportLines(key, report.sections[key]).join('\n');
      final c = _controllers.putIfAbsent(key, TextEditingController.new);
      c.text = text;
    }
    setState(() {});
  }

  /// Sistem taslağından farklı olan bölümler (yalnız bunlar saklanır).
  Map<String, String> _currentEdits() => <String, String>{
    for (final key in kAnnualReportSections)
      if ((_controllers[key]?.text.trim() ?? '').isNotEmpty && _controllers[key]!.text.trim() != _systemText(key).trim()) key: _controllers[key]!.text.trim(),
  };

  Future<void> _save() async {
    final site = _site;
    final growth = parseGrowthPercent(_growth.text);
    if (site == null) return;
    if (growth == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gelecek yıl artış oranı -50 ile 500 arasında bir sayı olmalı.')));
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.save(site.code, _year, _currentEdits(), growth);
      messenger.showSnackBar(const SnackBar(content: Text('Taslak kaydedildi.')));
      if (mounted) await reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_messageOf(e, 'Taslak kaydedilemedi.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pdf() async {
    final site = _site;
    final report = _report;
    if (site == null || report == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final edits = _currentEdits();
      final merged = AnnualReport(year: report.year, sections: report.sections, edits: edits, growthBp: report.growthBp, saved: report.saved);
      final outcome = await PdfAnnualReportService.download(siteName: site.name, report: merged);
      if (outcome == DecisionPdfOutcome.delivered) messenger.showSnackBar(const SnackBar(content: Text('PDF hazırlandı.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('PDF hazırlanamadı.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_site == null) return const Center(child: Text('Faaliyet raporu için uygun site yok.'));
    final years = <int>[for (var y = DateTime.now().year; y >= DateTime.now().year - 6; y--) y];
    return ListView(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), 
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Faaliyet Raporu', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Sistem kayıtlardan taslağı hazırlar. Her bölümü düzenleyebilir, taslağı saklayıp PDF alabilirsiniz.'),
        const SizedBox(height: 12),
        if (widget.sites.length > 1)
          DropdownButtonFormField<int>(
            initialValue: _site!.code,
            decoration: const InputDecoration(labelText: 'Site'),
            items: <DropdownMenuItem<int>>[for (final s in widget.sites) DropdownMenuItem<int>(value: s.code, child: Text(s.name))],
            onChanged: (code) {
              if (code == null) return;
              setState(() => _site = widget.sites.firstWhere((s) => s.code == code));
              unawaited(reload());
            },
          ),
        DropdownButtonFormField<int>(
          initialValue: _year,
          decoration: const InputDecoration(labelText: 'Rapor yılı'),
          items: <DropdownMenuItem<int>>[for (final y in years) DropdownMenuItem<int>(value: y, child: Text('$y'))],
          onChanged: (y) {
            if (y == null) return;
            setState(() => _year = y);
            unawaited(reload());
          },
        ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (_report != null) ...<Widget>[
          Text(_report!.saved ? 'Kayıtlı taslak var.' : 'Henüz kaydedilmiş taslak yok; metinler sistemden geliyor.'),
          const SizedBox(height: 8),
          for (final key in kAnnualReportSections) _sectionCard(key),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_rounded), label: const Text('Taslağı kaydet')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(onPressed: _busy ? null : _pdf, icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('PDF')),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _sectionCard(String key) {
    final available = _report?.sections[key]?['available'] == true;
    final controller = _controllers[key];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(kAnnualReportTitles[key] ?? key),
        subtitle: available ? null : const Text('Modül kapalı'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: <Widget>[
          if (key == 'forecast')
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _growth,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Gelecek yıl gider artışı (%)'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _loading ? null : () => unawaited(reload(keepGrowth: true)), child: const Text('Hesapla')),
              ],
            ),
          if (controller != null)
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 14,
              maxLength: kAnnualReportEditMax,
              decoration: const InputDecoration(labelText: 'Bölüm metni (düzenleyebilirsiniz)'),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: controller == null ? null : () => setState(() => controller.text = _systemText(key)),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Sistem taslağına dön'),
            ),
          ),
        ],
      ),
    );
  }
}
