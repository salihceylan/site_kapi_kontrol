import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';

/// Sihirbazın hata bildirimi: ortaya çıkınca (ya da iletisi değişince) görünür konuma kaydırılır, ekran okuyucuya
/// duyurulur ve klavye / ekran okuyucu odağı bildirime taşınır. Böylece düğmeye basıp hata alan kullanıcı, odağı
/// pasifleşen (yükleniyor) düğmede kalıp bağlamı kaybetmez; hata ekran dışında kalmaz.
class BulkErrorNotice extends StatefulWidget {
  const BulkErrorNotice({
    super.key,
    required this.message,
    this.onRetry,
    this.tone = AppTone.danger,
    this.takeFocus = true,
  });

  final String message;
  final VoidCallback? onRetry;
  final AppTone tone;
  final bool takeFocus;

  @override
  State<BulkErrorNotice> createState() => _BulkErrorNoticeState();
}

class _BulkErrorNoticeState extends State<BulkErrorNotice> {
  final FocusNode _focus = FocusNode(debugLabel: 'bulk_error_notice');

  @override
  void initState() {
    super.initState();
    _arrive();
  }

  @override
  void didUpdateWidget(BulkErrorNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) _arrive();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _arrive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Scrollable.maybeOf(context) != null) {
        Scrollable.ensureVisible(context, duration: Duration.zero, alignment: 0.1);
      }
      announcePolite(context, widget.message);
      if (widget.takeFocus && _focus.canRequestFocus) _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      child: InlineNotice(message: widget.message, tone: widget.tone, onRetry: widget.onRetry),
    );
  }
}
