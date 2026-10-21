// "Öde" sayfası (Dalga 2 / 2A): alıcı, IBAN ve açıklama kodu satırları (her birinde 48 dp "Kopyala" düğmesi), "Kartla öde — Yakında…" (pasif) ve
// yalnız geri çağrı verilince "Dekont yükle" (2B). Tutar bu sayfanın ucundan GELMEZ: çağıran /app/my-finance kalemindeki bakiyeyi verir (kartla aynı sayı).
// IBAN son 14 günde değiştiyse amber uyarı; ayar yoksa dürüst açıklama. Kopyalama boşluksuzdur (IBAN) ve "Kopyalandı" bildirimi verir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/payment_info.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/finance_payment_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/payment_notice_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';

/// Daire için ödeme bilgisini yükler (testlerde sahte verilir).
typedef PaymentInfoLoader = Future<PaymentInfoItem?> Function();

class PaySheet extends StatefulWidget {
  const PaySheet({
    super.key,
    required this.loader,
    required this.amountMinor,
    this.accountLabel,
    this.onUploadReceipt,
    this.now,
  });

  /// Alt sayfayı açar. [amountMinor]: ödenecek borç (kuruş; çağıranın kartındaki sayı). [onUploadReceipt] verilirse "Dekont yükle" görünür (2B).
  static Future<void> show(
    BuildContext context, {
    required AuthService authService,
    required int apartmentId,
    required int amountMinor,
    String? accountLabel,
    VoidCallback? onUploadReceipt,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => PaySheet(
        loader: () async {
          final info = await FinancePaymentService.of(authService).run((api, token) => api.getMyPaymentInfo(token: token));
          return info.forApartment(apartmentId);
        },
        amountMinor: amountMinor,
        accountLabel: accountLabel,
        // 2B: geri çağrı verilmediyse "Dekont yükle" dekont bildirme penceresini açar (sayfa kapanır; pencere alttaki ekranda açılır).
        onUploadReceipt:
            onUploadReceipt ??
            () {
              Navigator.of(sheetContext).pop();
              unawaited(PaymentNoticeDialog.open(context, authService, apartmentId: apartmentId, amountMinor: amountMinor));
            },
      ),
    );
  }

  final PaymentInfoLoader loader;
  final int amountMinor;
  final String? accountLabel;
  final VoidCallback? onUploadReceipt;
  final DateTime Function()? now;

  @override
  State<PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<PaySheet> {
  PaymentInfoItem? _info;
  bool _loading = true;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await widget.loader();
      if (!mounted || token != _token) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = financeMessageOf(e, 'Ödeme bilgisi yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Center(child: CircularProgressIndicator()));
    } else if (_error != null) {
      body = InlineNotice(message: _error!, onRetry: _load);
    } else {
      body = PayContent(
        info: _info,
        amountMinor: widget.amountMinor,
        accountLabel: widget.accountLabel,
        // Dekont yalnız sitede açıksa (2A "notices_enabled") sunulur.
        onUploadReceipt: _info?.noticesEnabled == true ? widget.onUploadReceipt : null,
        now: widget.now,
      );
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [body]),
      ),
    );
  }
}

/// Sayfanın içeriği (yükleme dışı): saf görünüm, test edilebilir.
class PayContent extends StatelessWidget {
  const PayContent({super.key, required this.info, required this.amountMinor, this.accountLabel, this.onUploadReceipt, this.now, this.copy});

  final PaymentInfoItem? info;
  final int amountMinor;
  final String? accountLabel;
  final VoidCallback? onUploadReceipt;
  final DateTime Function()? now;

  /// Panoya yazma (testlerde sahte; varsayılan sistem panosu).
  final Future<void> Function(String text)? copy;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final item = info;
    final configured = item != null && item.configured;
    final changed = configured && item.changedRecently((now ?? DateTime.now)());
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Öde', style: th.titleLarge),
        const SizedBox(height: AppSpace.sm),
        Semantics(
          container: true,
          label: 'Ödenecek tutar: ${moneySemanticLabel(amountMinor)}.${accountLabel == null ? '' : ' $accountLabel.'}',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ödenecek tutar', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                Text(formatMinor(amountMinor), key: const ValueKey<String>('pay_amount'), style: th.headlineMedium),
                if (accountLabel != null) Text(accountLabel!, style: th.bodySmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (!configured)
          const InlineNotice(
            key: ValueKey<String>('pay_not_configured'),
            tone: AppTone.info,
            icon: Icons.info_outline_rounded,
            message: 'Site yönetimi ödeme bilgisini henüz girmedi. Ödemenizi şimdilik site yönetimine yapabilirsiniz.',
          )
        else ...[
          if (changed)
            InlineNotice(
              key: const ValueKey<String>('pay_changed_warning'),
              tone: AppTone.warning,
              icon: Icons.warning_amber_rounded,
              message: 'Ödeme bilgisi ${_dm(item.detailsChangedAt!)} tarihinde değişti. Emin değilseniz yönetimle görüşün.',
            ),
          if (changed) const SizedBox(height: AppSpace.md),
          _CopyRow(
            rowKey: 'pay_row_payee',
            title: 'Alıcı',
            value: item.payeeName ?? '',
            copyText: item.payeeName ?? '',
            copyLabel: 'Alıcı adını kopyala',
            copy: copy,
          ),
          _CopyRow(
            rowKey: 'pay_row_iban',
            title: 'IBAN',
            value: item.ibanDisplay ?? '',
            copyText: item.iban ?? '',
            copyLabel: "IBAN'ı kopyala",
            copy: copy,
          ),
          _CopyRow(
            rowKey: 'pay_row_ref',
            title: 'Açıklama kodu',
            value: item.reference ?? '',
            copyText: item.reference ?? '',
            copyLabel: 'Açıklama kodunu kopyala',
            copy: copy,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Bu kodu havale açıklamasına yazın; ödemeniz dairenize kendiliğinden işlenir.'
            '${item.referenceShort == null ? '' : ' Düzenli ödeme talimatında ${item.referenceShort} yazabilirsiniz.'}',
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.xs),
          Text('FAST veya havale ile komisyonsuz ödeyebilirsiniz.', style: th.bodySmall?.copyWith(color: p.textSecondary)),
        ],
        const SizedBox(height: AppSpace.lg),
        if (configured && onUploadReceipt != null) ...[
          OutlinedButton.icon(
            key: const ValueKey<String>('pay_upload_receipt'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: onUploadReceipt,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Dekont yükle'),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        Semantics(
          container: true,
          label: 'Kartla öde, yakında. Şu an kullanılamıyor.',
          child: ExcludeSemantics(
            child: Row(
              key: const ValueKey<String>('pay_card_soon'),
              children: [
                const Expanded(
                  child: Opacity(
                    opacity: 0.6,
                    child: FilledButton(onPressed: null, child: Text('Kartla öde — Yakında…')),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                const StatusDot(label: 'Yakında', tone: AppTone.neutral),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _dm(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year}';
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.rowKey,
    required this.title,
    required this.value,
    required this.copyText,
    required this.copyLabel,
    required this.copy,
  });

  final String rowKey;
  final String title;
  final String value;
  final String copyText;
  final String copyLabel;
  final Future<void> Function(String text)? copy;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await (copy ?? (text) => Clipboard.setData(ClipboardData(text: text)))(copyText);
    messenger?.showSnackBar(const SnackBar(content: Text('Kopyalandı')));
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      key: ValueKey<String>(rowKey),
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              label: '$title: $value',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                    Text(value, style: th.titleMedium),
                  ],
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: copyLabel,
            excludeSemantics: true,
            child: TextButton.icon(
              key: ValueKey<String>('${rowKey}_copy'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => unawaited(_copy(context)),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Kopyala'),
            ),
          ),
        ],
      ),
    );
  }
}
