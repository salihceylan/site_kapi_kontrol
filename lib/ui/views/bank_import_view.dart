// Banka dosyası yükleme ekranı (Dalga 2 / 2C): Hesap seç -> Dosya seç -> Sütunları eşle (gerekirse) -> Özet -> İşle.
// Dosya (XLSX / CSV / MT940) CİHAZDA ayrıştırılır; sunucuya yalnız satırlar ve dosya özeti gider. Tutarlar ve sayılar sunucu önizlemesindendir.
// PDF hesap ekstresi (OCR yok, yalnız metin katmanı): PDF sunucuya gönderilir, satırlar sunucuda okunur (dosya saklanmaz); sütun eşleme adımı atlanır,
// satırlar aynı önizleme/eşleşme akışına girer. Güveni düşük PDF satırları otomatik işlenmez, "Kontrol edin"e düşer.
// Geçmiş yüklemeler "Geri al" ile ters kayıtla geri alınır. Hata durumunda eski sayılar gösterilmez.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bank_import.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bank_import_api.dart';
import 'package:site_kapi_kontrol/services/bank_statement_reader.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';
import 'package:site_kapi_kontrol/services/mt940_parser.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/bank_mapping_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/bank_lines_view.dart';

BankFile _readIsolate(({Uint8List bytes, String name}) a) => readBankFile(a.bytes, a.name);

class BankImportView extends StatefulWidget {
  const BankImportView({super.key, required this.scope, this.initialAccountId, this.pickFile});

  final PeopleScope scope;
  final int? initialAccountId;

  /// Testlerde sahte seçici.
  final BulkFilePicker? pickFile;

  @override
  State<BankImportView> createState() => _BankImportViewState();
}

class _BankImportViewState extends State<BankImportView> {
  List<CashAccount> _accounts = const <CashAccount>[];
  int? _accountId;
  bool _loading = true;
  String? _loadError;
  BankFile? _file;
  List<BankLine> _lines = const <BankLine>[];
  BankPdfExtract? _pdf;
  int _skipped = 0;
  BankPreview? _preview;
  bool _working = false;
  String? _error;
  String? _key;
  List<BankImportItem> _imports = const <BankImportItem>[];
  int _attention = 0;
  String? _doneText;

  BankImportService get _svc => BankImportService.of(widget.scope.authService);
  int get _siteCode => widget.scope.siteCode;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final overview = await widget.scope.f4Call((api, t, s) => api.listAccounts(token: t, siteCode: s));
      final banks = overview.activeAccounts.where((a) => a.kind == CashAccountKind.bank).toList();
      final imports = await _svc.run((api, t) => api.listImports(token: t, siteCode: _siteCode));
      final attention = await _svc.run((api, t) => api.attentionCount(token: t, siteCode: _siteCode));
      if (!mounted) return;
      setState(() {
        _accounts = banks;
        _accountId ??= banks.any((a) => a.id == widget.initialAccountId) ? widget.initialAccountId : (banks.length == 1 ? banks.first.id : null);
        _imports = imports;
        _attention = attention;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    }
  }

  void _reset() {
    _file = null;
    _lines = const <BankLine>[];
    _pdf = null;
    _preview = null;
    _key = null;
    _error = null;
    _skipped = 0;
  }

  Future<PickedBulkFile?> _pick() async {
    final custom = widget.pickFile;
    if (custom != null) return custom();
    final file = await FilePicker.pickFile(
      dialogTitle: 'Banka ekstresini seçin',
      type: FileType.custom,
      allowedExtensions: const <String>['xlsx', 'csv', 'pdf', 'sta', 'mt940', '940', 'txt'],
    );
    return file == null ? null : pickedFileOf(file);
  }

  Future<void> _chooseFile() async {
    if (_working || _accountId == null) return;
    final accountId = _accountId!;
    setState(() {
      _working = true;
      _doneText = null;
      _reset();
    });
    try {
      final picked = await _pick();
      if (picked == null) return;
      final bytes = await picked.readBytes();
      final file = await compute(_readIsolate, (bytes: bytes, name: picked.name));
      BankParseResult parsed;
      BankPdfExtract? pdf;
      if (file.kind == BankFileKind.pdf) {
        final extract = await _svc.run((api, t) => api.extractPdf(token: t, siteCode: _siteCode, bytes: bytes));
        pdf = extract;
        parsed = BankParseResult(lines: extract.lines, skipped: extract.unreadable, errors: const <int>[]);
      } else if (file.kind == BankFileKind.mt940) {
        parsed = bankLinesOfMt940(file.mt940!);
      } else {
        final table = file.table!;
        final profile = await _svc.run((api, t) => api.getProfile(token: t, siteCode: _siteCode, accountId: accountId));
        var mapping = profile != null && profile.signature == table.signature && profile.mapping.isComplete ? profile.mapping : null;
        if (mapping == null) {
          if (!mounted) return;
          mapping = await BankMappingDialog.show(context, table: table, initial: profile?.mapping.isComplete == true ? profile!.mapping : table.guess);
          if (mapping == null) return;
          try {
            await _svc.run((api, t) => api.putProfile(token: t, siteCode: _siteCode, accountId: accountId, kind: file.kind, signature: table.signature, mapping: mapping!));
          } on ApiException {
            // profil kaydı başarısız olsa da yükleme sürer; sonraki dosyada yeniden sorulur
          }
        }
        parsed = applyBankMapping(table, mapping);
        if (parsed.truncated) throw const SpreadsheetException('Dosya çok uzun. Satırları dönemlere bölüp ayrı ayrı yükleyin.');
      }
      if (parsed.lines.isEmpty) {
        throw SpreadsheetException(
          pdf == null ? 'Dosyada okunabilen hareket satırı bulunamadı. Sütun eşlemesini kontrol edin.' : "PDF'de okunabilen hareket satırı bulunamadı. Bankanın Excel (xlsx) ya da CSV dökümünü yükleyin.",
        );
      }
      if (parsed.lines.length > bankMaxLines) {
        throw SpreadsheetException('Dosyada ${parsed.lines.length} hareket var; bir seferde en çok $bankMaxLines yüklenebilir. Dosyayı dönemlere bölün.');
      }
      if (parsed.errors.isNotEmpty) {
        throw SpreadsheetException('${parsed.errors.length} satırın tutarı okunamadı (ilk satır: ${parsed.errors.first}). Sütun eşlemesini kontrol edin.');
      }
      final preview = await _svc.run(
        (api, t) => api.preview(token: t, siteCode: _siteCode, accountId: accountId, file: file, lines: parsed.lines, accountIban: file.mt940?.accountIban ?? pdf?.accountIban),
      );
      if (!mounted) return;
      setState(() {
        _file = file;
        _pdf = pdf;
        _lines = parsed.lines;
        _skipped = parsed.skipped;
        _preview = preview;
        _key = 'bi${file.sha256.substring(0, 12)}${Random().nextInt(1 << 30).toRadixString(36)}';
      });
    } on SpreadsheetException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Mt940Exception catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _commit() async {
    final file = _file;
    final preview = _preview;
    final key = _key;
    if (_working || file == null || preview == null || key == null || _accountId == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final r = await _svc.run(
        (api, t) => api.commit(
          token: t,
          siteCode: _siteCode,
          accountId: _accountId!,
          file: file,
          lines: _lines,
          previewHash: preview.hash,
          idempotencyKey: key,
          accountIban: file.mt940?.accountIban ?? _pdf?.accountIban,
        ),
      );
      if (!mounted) return;
      setState(() {
        _doneText = '${r.posted} tahsilat işlendi, ${r.linked} satır mevcut tahsilata bağlandı, ${r.attention} satır sizi bekliyor.';
        _reset();
      });
      unawaited(_loadAll());
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        if (e.code == 'BANK_PREVIEW_STALE') {
          setState(() {
            _preview = null;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _revert(BankImportItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yükleme geri alınsın mı?'),
        content: Text('"${item.fileName}" dosyasından işlenen tahsilatlar ters kayıtla geri alınır ve makbuzlar iptal edilir. Bu işlem kayıt bırakır.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          FilledButton(key: const ValueKey<String>('bank_revert_ok'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Geri al')),
        ],
      ),
    );
    if (ok != true || _working) return;
    setState(() => _working = true);
    try {
      await _svc.run((api, t) => api.revertImport(token: t, siteCode: _siteCode, importId: item.id));
      if (mounted) setState(() => _doneText = 'Yükleme geri alındı.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (mounted) unawaited(_loadAll());
  }

  static const Map<String, String> _warnings = <String, String>{
    'FILE_ALREADY_IMPORTED': 'Bu dosya bu hesaba daha önce yüklenmiş; tekrar yüklenemez.',
    'ACCOUNT_IBAN_MISMATCH': 'Dosyadaki hesap IBAN\'ı, seçtiğiniz hesabın kayıtlı IBAN\'ından farklı. Doğru hesabı seçtiğinizden emin olun.',
    'BALANCE_GAP': 'Satırların bakiyeleri birbirini tutmuyor; dosyada eksik hareket olabilir.',
    'OVERLAP': 'Dosyanın bir kısmı daha önce yüklenmiş; o satırlar atlanacak.',
  };

  /// PDF'e özgü uyarılar: okunamayan satırlar ve güveni düşük satırlar (bunlar işlenmeden önce onayınıza düşer).
  List<Widget> _pdfNotes(BankPdfExtract pdf) {
    final th = Theme.of(context).textTheme;
    final err = TextStyle(color: Theme.of(context).colorScheme.error);
    Widget note(String text, {bool warn = false}) =>
        Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(text, key: warn ? const ValueKey<String>('bank_pdf_warn') : null, style: warn ? err : th.bodySmall));
    return [
      note("PDF'den ${pdf.lines.length} hareket okundu (${pdf.pageCount} sayfa). Metin ekstreden okunur; tutar ve tarihleri bankanızın ekstresiyle karşılaştırın."),
      if (pdf.unreadable > 0) note('${pdf.unreadable} satır güvenle okunamadığı için atlandı (tutarı ya da yönü belirsiz). Bu satırlar için bankanın Excel/CSV dökümünü yükleyin.', warn: true),
      if (pdf.lowConfidence > 0) note('${pdf.lowConfidence} satırın okunması belirsiz (bakiyeyle uyuşmuyor); bunlar otomatik işlenmez, “Kontrol edin”e düşer.', warn: true),
    ];
  }

  static const Map<String, String> _outcomeNames = <String, String>{
    'recognized': 'Tanındı',
    'check': 'Kontrol edin',
    'unmatched': 'Tanınmadı',
    'linked': 'Mevcut tahsilat',
    'duplicate': 'Daha önce yüklenmiş',
    'outgoing': 'Çıkan para',
  };

  /// Okunan satırlar: tarih, tutar, açıklama, sunucunun eşleşme sonucu ve (varsa) açıklamadaki dönem ipucu. Belirsiz PDF satırları işaretlidir.
  Widget _lineList(BankPreview p) {
    const maxShown = 300;
    final th = Theme.of(context).textTheme;
    final byN = <int, BankPreviewLine>{for (final l in p.lines) l.n: l};
    final shown = _lines.length > maxShown ? _lines.sublist(0, maxShown) : _lines;
    Widget tile(int i) {
      final line = shown[i];
      final pl = byN[i + 1];
      final period = bankPeriodLabel(pl?.periodHint);
      final bits = <String>[
        if (pl != null && _outcomeNames.containsKey(pl.outcome)) _outcomeNames[pl.outcome]!,
        if (pl?.apartmentLabel != null) pl!.apartmentLabel!,
        if (period != null) '$period dönemi',
      ];
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: line.uncertain ? Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error, semanticLabel: 'Okunması belirsiz satır') : null,
        title: Text('${line.valueDate}  ${formatSignedMinor(line.amountMinor)}', style: th.bodyMedium),
        subtitle: Text(<String>[if (line.description.isNotEmpty) line.description, if (bits.isNotEmpty) bits.join(' · ')].join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis),
      );
    }

    return ExpansionTile(
      key: const ValueKey<String>('bank_lines_expand'),
      tilePadding: EdgeInsets.zero,
      title: Text('Satırları göster (${_lines.length})', style: th.titleSmall),
      children: [
        for (var i = 0; i < shown.length; i++) tile(i),
        if (_lines.length > maxShown) Padding(padding: const EdgeInsets.all(AppSpace.sm), child: Text('… ve ${_lines.length - maxShown} satır daha', style: th.bodySmall)),
      ],
    );
  }

  Widget _summary(BankPreview p) {
    final s = p.summary;
    final th = Theme.of(context).textTheme;
    Widget row(String text, {bool strong = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(text, style: strong ? th.titleSmall : th.bodyMedium));
    final blocked = p.warnings.contains('FILE_ALREADY_IMPORTED');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_file?.name ?? '', style: th.bodySmall),
          const SizedBox(height: AppSpace.sm),
          row('Tanınan ${s.recognized} satır (${formatMinor(s.recognizedMinor)}) işlenecek', strong: true),
          if (s.check > 0) row('Kontrol edin ${s.check} (işlendikten sonra onayınızı bekler)'),
          if (s.unmatched > 0) row('Tanınmayan ${s.unmatched}'),
          if (s.outgoing > 0) row('Çıkan para ${s.outgoing} (gider/masraf olarak ayrılabilir)'),
          if (s.linkedExisting > 0) row('Zaten işlenmiş ${s.linkedExisting} (mevcut tahsilata bağlanacak, ikinci kez yazılmaz)'),
          if (s.duplicates > 0) row('Daha önce yüklenmiş ${s.duplicates} (atlanacak)'),
          if (_skipped > 0 && _pdf == null) row('Okunamayan/boş $_skipped satır yok sayıldı'),
          if (_pdf != null) ..._pdfNotes(_pdf!),
          for (final w in p.warnings)
            if (_warnings.containsKey(w))
              Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(_warnings[w]!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_lines.isNotEmpty) _lineList(p),
          const SizedBox(height: AppSpace.md),
          FilledButton(
            key: const ValueKey<String>('bank_commit'),
            onPressed: _working || blocked ? null : _commit,
            child: Text(_working ? 'İşleniyor…' : 'İşle'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Banka dosyası')),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            if (_loading) const Center(child: Padding(padding: EdgeInsets.all(AppSpace.xl), child: CircularProgressIndicator())),
            if (!_loading && _loadError != null) ...[Text(_loadError!), TextButton(onPressed: _loadAll, child: const Text('Tekrar dene'))],
            if (!_loading && _loadError == null) ...[
              if (_attention > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.md),
                  child: AppCard(
                    child: ListTile(
                      key: const ValueKey<String>('bank_attention'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.priority_high_rounded),
                      title: Text('$_attention banka satırı sizi bekliyor'),
                      subtitle: const Text('Daireye işleyin ya da gelir/gider olarak ayırın.'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BankLinesView(scope: widget.scope)));
                        if (mounted) unawaited(_loadAll());
                      },
                    ),
                  ),
                ),
              if (_accounts.isEmpty)
                const Text('Önce Kasa sekmesinden bir banka hesabı ekleyin.')
              else ...[
                Text('1. Hesap', style: th.titleSmall),
                const SizedBox(height: AppSpace.xs),
                DropdownButtonFormField<int>(
                  key: const ValueKey<String>('bank_account'),
                  initialValue: _accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Banka hesabı'),
                  items: [for (final a in _accounts) DropdownMenuItem<int>(value: a.id, child: Text(a.name))],
                  onChanged: _working ? null : (v) => setState(() {
                    _accountId = v;
                    _reset();
                  }),
                ),
                const SizedBox(height: AppSpace.md),
                Text('2. Dosya', style: th.titleSmall),
                const SizedBox(height: AppSpace.xs),
                const Text(
                  'Bankanızın ekstre dosyası (XLSX, CSV veya MT940). Dosya telefonunuzda/bilgisayarınızda okunur, yalnız hareket satırları gönderilir. '
                  'PDF hesap ekstresi de yüklenebilir: metni sunucuda okunur (taranmış resim PDF’ler okunamaz), dosya saklanmaz.',
                ),
                const SizedBox(height: AppSpace.sm),
                OutlinedButton.icon(
                  key: const ValueKey<String>('bank_pick_file'),
                  onPressed: _working || _accountId == null ? null : _chooseFile,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(_working && _preview == null ? 'Okunuyor…' : 'Dosya seç'),
                ),
              ],
              if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.md), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              if (_doneText != null) Padding(padding: const EdgeInsets.only(top: AppSpace.md), child: Text(_doneText!, key: const ValueKey<String>('bank_done'))),
              if (_preview != null) Padding(padding: const EdgeInsets.only(top: AppSpace.md), child: _summary(_preview!)),
              const SizedBox(height: AppSpace.xl),
              Text('Geçmiş yüklemeler', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              if (_imports.isEmpty) const Text('Henüz banka dosyası yüklenmedi.'),
              for (final i in _imports)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: AppCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(i.fileName, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${i.accountName} · ${i.lineCount} satır${i.isActive ? '' : ' · geri alındı'}'),
                      trailing: i.isActive && widget.scope.canWrite
                          ? TextButton(key: ValueKey<String>('bank_revert_${i.id}'), onPressed: _working ? null : () => _revert(i), child: const Text('Geri al'))
                          : null,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
