// Sakin "Dekont bildir" penceresi (Dalga 2 / 2B). "Öde" sayfasındaki "Dekont yükle" ve Android "Paylaş" aynı pencereyi açar.
//
// Bildirim deftere YAZILMAZ: yönetim onaylayınca borçtan düşer. Dosya (PDF / JPEG / PNG, en çok 10 MB) cihazda hazırlanır (fotoğraf küçültülür, konum
// bilgisi silinir) ve önce kayıt, sonra dosya gönderilir. Aynı işlem anahtarıyla yeniden denemek çift kayıt üretmez.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/payment_notice.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/finance_payment_api.dart';
import 'package:site_kapi_kontrol/services/payment_notice_api.dart';
import 'package:site_kapi_kontrol/services/payment_notice_file.dart';
import 'package:site_kapi_kontrol/services/share_inbox.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

/// Bildirilebilecek daire seçeneği.
class NoticeApartmentChoice {
  const NoticeApartmentChoice({required this.apartmentId, required this.label, this.reference});

  final int apartmentId;
  final String label;

  /// 2A referans kodu ("GUL-A2-1026"); açıklama alanı bununla dolu gelir.
  final String? reference;
}

class PaymentNoticeDialog extends StatefulWidget {
  const PaymentNoticeDialog({
    super.key,
    required this.authService,
    required this.choices,
    this.apartmentId,
    this.amountMinor,
    this.shared,
    this.pickFile = pickNoticeFile,
    this.now,
  });

  final AuthService authService;
  final List<NoticeApartmentChoice> choices;
  final int? apartmentId;

  /// Önerilen tutar (borç); sakin değiştirebilir.
  final int? amountMinor;

  /// Android "Paylaş" ile gelen dosya (dosya seçimi atlanır).
  final SharedReceipt? shared;
  final Future<SharedReceipt?> Function() pickFile;
  final DateTime Function()? now;

  /// Daire listesini yükler ve pencereyi açar. Bu sitede bildirim kapalıysa nedenini söyler. Gönderildiyse true.
  static Future<bool?> open(
    BuildContext context,
    AuthService authService, {
    int? apartmentId,
    int? amountMinor,
    SharedReceipt? shared,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final info = await FinancePaymentService.of(authService).run((api, token) => api.getMyPaymentInfo(token: token));
      final finance = await authService.getMyFinance();
      final labels = <int, String>{for (final a in finance.items) a.apartmentId: financeApartmentTitle(a.blockName, a.label)};
      final choices = <NoticeApartmentChoice>[
        for (final item in info.items)
          if (item.noticesEnabled)
            NoticeApartmentChoice(
              apartmentId: item.apartmentId,
              label: [if (item.siteName.isNotEmpty) item.siteName, labels[item.apartmentId] ?? 'Daire'].join(' - '),
              reference: item.reference,
            ),
      ];
      if (choices.isEmpty) {
        messenger?.showSnackBar(const SnackBar(content: Text('Bu sitede dekont bildirimi henüz açık değil. Yönetime sorun.')));
        return null;
      }
      if (!context.mounted) return null;
      return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PaymentNoticeDialog(authService: authService, choices: choices, apartmentId: apartmentId, amountMinor: amountMinor, shared: shared),
      );
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(financeMessageOf(e, 'Dekont penceresi açılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'))));
      return null;
    }
  }

  @override
  State<PaymentNoticeDialog> createState() => _PaymentNoticeDialogState();
}

class _PaymentNoticeDialogState extends State<PaymentNoticeDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _sender = TextEditingController();
  final _description = TextEditingController();
  late NoticeApartmentChoice _choice;
  late DateTime _date;
  SharedReceipt? _file;
  String? _fileError;
  String? _error;
  bool _busy = false;
  bool _picking = false;
  String _key = newNoticeKey();

  DateTime _today() {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  @override
  void initState() {
    super.initState();
    _choice = widget.choices.firstWhere((c) => c.apartmentId == widget.apartmentId, orElse: () => widget.choices.first);
    _date = _today();
    _file = widget.shared;
    final amount = widget.amountMinor;
    if (amount != null && amount > 0) _amount.text = formatMinor(amount, symbol: false);
    _description.text = _choice.reference ?? '';
  }

  @override
  void dispose() {
    _amount.dispose();
    _sender.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_picking || _busy) return;
    setState(() {
      _picking = true;
      _fileError = null;
    });
    try {
      final picked = await widget.pickFile();
      if (!mounted) return;
      setState(() {
        if (picked != null) {
          _file = picked;
          _key = newNoticeKey();
        }
      });
    } on NoticeFileException catch (e) {
      if (mounted) setState(() => _fileError = e.message);
    } catch (_) {
      if (mounted) setState(() => _fileError = 'Dosya okunamadı. Başka bir dosya deneyin.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today,
      helpText: 'Ödeme tarihi',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final file = _file;
    if (file == null) {
      setState(() => _fileError = 'Önce dekontu seçin.');
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;
    final minor = parseMoney(_amount.text).minor;
    if (minor == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = PaymentNoticeService.of(widget.authService);
    try {
      final created = await service.run(
        (api, token) => api.createMine(
          token: token,
          body: <String, dynamic>{
            'apartment_id': _choice.apartmentId,
            'amount_minor': minor,
            'paid_on': crmDateParam(_date),
            if (_sender.text.trim().isNotEmpty) 'sender_name': _sender.text.trim(),
            if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
            'origin': widget.shared != null ? 'resident_share' : 'resident_app',
            'file': <String, dynamic>{'name': file.name, 'size': file.bytes.length, 'content_type': file.mime},
            'idempotency_key': _key,
          },
        ),
      );
      if (created.uploadPath != null) {
        await service.run((api, token) => api.putMineContent(token: token, id: created.notice.id, bytes: file.bytes));
      }
      paymentNoticeRevision.value++;
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Dekont gönderildi. Yönetim inceleyince borcunuzdan düşer.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = financeMessageOf(e, 'Dekont gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        // Dosya yüklenemediyse kayıt açık kalır; aynı anahtarla yeniden deneme aynı kaydı kullanır.
        if (e is ApiException && e.statusCode != null && e.statusCode! >= 400 && e.statusCode! < 500 && e.code != 'UPLOAD_ALREADY_COMPLETED') _key = newNoticeKey();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final file = _file;
    return AlertDialog(
      key: const ValueKey<String>('notice_dialog'),
      title: const Text('Dekont bildir'),
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
                  'Ödemeyi yaptıktan sonra dekontu buradan gönderin. Yönetim kontrol edip onaylayınca borcunuzdan düşer; o zamana kadar "İnceleniyor" görünür.',
                  style: th.bodySmall?.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: AppSpace.md),
                if (widget.choices.length > 1) ...[
                  DropdownButtonFormField<int>(
                    key: const ValueKey<String>('notice_apartment'),
                    initialValue: _choice.apartmentId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Daire'),
                    items: [for (final c in widget.choices) DropdownMenuItem<int>(value: c.apartmentId, child: Text(c.label, overflow: TextOverflow.ellipsis))],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _choice = widget.choices.firstWhere((c) => c.apartmentId == v);
                            _description.text = _choice.reference ?? '';
                          }),
                  ),
                  const SizedBox(height: AppSpace.md),
                ] else ...[
                  Text(_choice.label, style: th.titleSmall),
                  const SizedBox(height: AppSpace.md),
                ],
                OutlinedButton.icon(
                  key: const ValueKey<String>('notice_pick'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy || _picking ? null : _pick,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(file == null ? 'Dekont dosyası seç (PDF, JPEG, PNG)' : '${file.name} (${noticeSizeText(file.bytes.length)}) - değiştir'),
                ),
                if (_fileError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Text(_fileError!, key: const ValueKey<String>('notice_file_error'), style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p))),
                  ),
                const SizedBox(height: AppSpace.md),
                MoneyFormField(
                  key: const ValueKey<String>('notice_amount_field'),
                  fieldKey: const ValueKey<String>('notice_amount'),
                  controller: _amount,
                  label: 'Ödenen tutar',
                  enabled: !_busy,
                ),
                const SizedBox(height: AppSpace.md),
                OutlinedButton.icon(
                  key: const ValueKey<String>('notice_date'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy ? null : _pickDate,
                  icon: const Icon(Icons.event_rounded),
                  label: Text('Ödeme tarihi: ${formatDateField(_date)}'),
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  key: const ValueKey<String>('notice_sender'),
                  controller: _sender,
                  enabled: !_busy,
                  maxLength: 80,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Gönderen adı (isteğe bağlı)'),
                ),
                TextFormField(
                  key: const ValueKey<String>('notice_description'),
                  controller: _description,
                  enabled: !_busy,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Açıklama (isteğe bağlı)', helperText: 'Havale açıklamasındaki referans kodu'),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'Gizlilik: dekont ad ve IBAN gibi kişisel veriler içerebilir; yalnız bu ödemeyi eşleştirmek için site yönetimi görür. Fotoğraflardaki konum bilgisi silinir.',
                  key: const ValueKey<String>('notice_privacy'),
                  style: th.bodySmall?.copyWith(color: p.textSecondary),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpace.md),
                  Text(_error!, key: const ValueKey<String>('notice_error'), style: th.bodyMedium?.copyWith(color: AppTone.danger.ink(p))),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(key: const ValueKey<String>('notice_cancel'), onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
        PrimaryActionButton(key: const ValueKey<String>('notice_submit'), label: 'Gönder', icon: Icons.send_rounded, expand: false, loading: _busy, onPressed: _busy ? null : _submit),
      ],
    );
  }
}

