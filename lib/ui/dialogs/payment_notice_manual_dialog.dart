// Yönetici "Elden makbuz / dekont girişi" penceresi (Dalga 2 / 2B). Dosya isteğe bağlıdır; kayıt yine "inceleniyor"a düşer (deftere onaydan sonra yazılır),
// böylece elden alınan para da tek yoldan (karşılaştırma ekranı) tahsilata dönüşür.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/payment_notice.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/services/payment_notice_api.dart';
import 'package:site_kapi_kontrol/services/payment_notice_file.dart';
import 'package:site_kapi_kontrol/services/share_inbox.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart' show showApartmentPicker;
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

class PaymentNoticeManualDialog extends StatefulWidget {
  const PaymentNoticeManualDialog({super.key, required this.scope, this.pickFile = pickNoticeFile, this.now});

  final PeopleScope scope;
  final Future<SharedReceipt?> Function() pickFile;
  final DateTime Function()? now;

  static Future<bool?> show(BuildContext context, PeopleScope scope) =>
      showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => PaymentNoticeManualDialog(scope: scope));

  @override
  State<PaymentNoticeManualDialog> createState() => _PaymentNoticeManualDialogState();
}

class _PaymentNoticeManualDialogState extends State<PaymentNoticeManualDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _sender = TextEditingController();
  final _description = TextEditingController();
  ({int id, String label})? _apartment;
  String _method = 'cash';
  late DateTime _date;
  SharedReceipt? _file;
  String? _fileError;
  String? _error;
  bool _busy = false;
  final String _key = newNoticeKey();

  @override
  void initState() {
    super.initState();
    final wall = istanbulNow(widget.now?.call());
    _date = DateTime(wall.year, wall.month, wall.day);
  }

  @override
  void dispose() {
    _amount.dispose();
    _sender.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickApartment() async {
    final picked = await showApartmentPicker(context, widget.scope);
    if (picked != null && mounted) setState(() => _apartment = (id: picked.id, label: picked.fullLabel));
  }

  Future<void> _pickFile() async {
    try {
      final f = await widget.pickFile();
      if (mounted) setState(() => _file = f ?? _file);
    } on NoticeFileException catch (e) {
      if (mounted) setState(() => _fileError = e.message);
    }
  }

  Future<void> _pickDate() async {
    final wall = istanbulNow(widget.now?.call());
    final today = DateTime(wall.year, wall.month, wall.day);
    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(today.year - 5, today.month, today.day), lastDate: today, helpText: 'Ödeme tarihi');
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final apartment = _apartment;
    if (apartment == null) {
      setState(() => _error = 'Daire seçin.');
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;
    final minor = parseMoney(_amount.text).minor;
    if (minor == null) return;
    final file = _file;
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = PaymentNoticeService.of(widget.scope.authService);
    try {
      final created = await service.run(
        (api, token) => api.createManual(
          token: token,
          siteCode: widget.scope.siteCode,
          body: <String, dynamic>{
            'apartment_id': apartment.id,
            'amount_minor': minor,
            'paid_on': crmDateParam(_date),
            'method': _method,
            if (_sender.text.trim().isNotEmpty) 'sender_name': _sender.text.trim(),
            if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
            if (file != null) 'file': <String, dynamic>{'name': file.name, 'size': file.bytes.length, 'content_type': file.mime},
            'idempotency_key': _key,
          },
        ),
      );
      if (file != null && created.uploadPath != null) {
        await service.run((api, token) => api.putContent(token: token, siteCode: widget.scope.siteCode, id: created.notice.id, bytes: file.bytes));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = financeMessageOf(e, 'Kayıt oluşturulamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return AlertDialog(
      key: const ValueKey<String>('notice_manual'),
      title: const Text('Elden makbuz / dekont girişi'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Kayıt "incelenen dekontlar" listesine düşer; onaylayınca tahsilat ve makbuz oluşur.',
                  style: th.bodySmall?.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: AppSpace.md),
                OutlinedButton.icon(
                  key: const ValueKey<String>('notice_manual_apartment'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy ? null : _pickApartment,
                  icon: const Icon(Icons.apartment_rounded),
                  label: Text(_apartment?.label ?? 'Daire seç'),
                ),
                const SizedBox(height: AppSpace.md),
                MoneyFormField(key: const ValueKey<String>('notice_manual_amount_field'), fieldKey: const ValueKey<String>('notice_manual_amount'), controller: _amount, label: 'Tutar', enabled: !_busy),
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<String>(
                  key: const ValueKey<String>('notice_manual_method'),
                  initialValue: _method,
                  decoration: const InputDecoration(labelText: 'Ödeme yöntemi'),
                  items: [for (final e in kNoticeMethods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: _busy ? null : (v) => setState(() => _method = v ?? 'cash'),
                ),
                const SizedBox(height: AppSpace.md),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy ? null : _pickDate,
                  icon: const Icon(Icons.event_rounded),
                  label: Text('Ödeme tarihi: ${formatDateField(_date)}'),
                ),
                TextFormField(controller: _sender, enabled: !_busy, maxLength: 80, decoration: const InputDecoration(labelText: 'Ödeyen adı (isteğe bağlı)')),
                TextFormField(controller: _description, enabled: !_busy, maxLength: 200, decoration: const InputDecoration(labelText: 'Açıklama (isteğe bağlı)')),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(_file == null ? 'Makbuz / dekont dosyası ekle (isteğe bağlı)' : '${_file!.name} (${noticeSizeText(_file!.bytes.length)})'),
                ),
                if (_fileError != null) Text(_fileError!, style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p))),
                if (_error != null) ...[
                  const SizedBox(height: AppSpace.md),
                  Text(_error!, key: const ValueKey<String>('notice_manual_error'), style: th.bodyMedium?.copyWith(color: AppTone.danger.ink(p))),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
        PrimaryActionButton(key: const ValueKey<String>('notice_manual_submit'), label: 'Kaydet', icon: Icons.save_rounded, expand: false, loading: _busy, onPressed: _busy ? null : _submit),
      ],
    );
  }
}
