import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/app_config.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/update_required_view.dart';

/// Sunucu bakım modundayken gösterilen tam ekran. İleti sunucudan gelir (`maintenance.message`);
/// yoksa genel bir metin gösterilir. "Yeniden dene" yapılandırmayı sunucudan yeniden sorgular.
class MaintenanceView extends StatefulWidget {
  const MaintenanceView({
    super.key,
    required this.onRetry,
    this.message,
    this.config,
    this.onOperatorLogin,
    this.operatorNotice,
  });

  /// Verilirse "Yönetici girişi" düğmesi görünür (süper kullanıcı bakımı kapatabilsin).
  final VoidCallback? onOperatorLogin;

  /// Yönetici girişi denemesinin sonucu (örn. "bu cihazda başka hesap açık"); yoksa `null`.
  final String? operatorNotice;

  /// Sunucudaki bakım iletisi (boş/`null` ise genel metin).
  final String? message;

  /// Destek bilgisi göstermek için (isteğe bağlı).
  final AppConfig? config;

  /// Yapılandırmayı yeniden yükler; yeni yapılandırmayı döndürür, ağ hatasında `null`.
  /// Bakım bittiyse kapı bu ekranı kendiliğinden kaldırır.
  final Future<AppConfig?> Function() onRetry;

  static const String defaultMessage =
      'Sistemimiz kısa süreli bakımda. Lütfen birkaç dakika sonra tekrar deneyin.';

  @override
  State<MaintenanceView> createState() => _MaintenanceViewState();
}

enum _RetryOutcome { none, stillMaintenance, unreachable }

class _MaintenanceViewState extends State<MaintenanceView> {
  bool _checking = false;
  _RetryOutcome _outcome = _RetryOutcome.none;

  Future<void> _retry() async {
    if (_checking) return;
    setState(() => _checking = true);
    AppConfig? fresh;
    try {
      fresh = await widget.onRetry();
    } catch (_) {
      fresh = null;
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _outcome = fresh == null
          ? _RetryOutcome.unreachable
          : _RetryOutcome.stillMaintenance;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final hPad = MediaQuery.sizeOf(context).width < 400
        ? AppSpace.lg
        : AppSpace.xl;
    final message = (widget.message ?? '').trim().isEmpty
        ? MaintenanceView.defaultMessage
        : widget.message!.trim();
    final support = gateSupportSummary(widget.config);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(hPad),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AppCard(
                level: 2,
                padding: EdgeInsets.all(hPad),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: IconOrb(
                        icon: Icons.construction_rounded,
                        tone: AppTone.warning,
                        size: 72,
                        glow: true,
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    Semantics(
                      header: true,
                      child: Text(
                        'Bakım çalışması',
                        textAlign: TextAlign.center,
                        style: th.titleLarge,
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: th.bodyMedium,
                    ),
                    if (_outcome != _RetryOutcome.none && !_checking) ...[
                      const SizedBox(height: AppSpace.md),
                      InlineNotice(
                        tone: _outcome == _RetryOutcome.unreachable
                            ? AppTone.warning
                            : AppTone.info,
                        message: _outcome == _RetryOutcome.unreachable
                            ? 'Sunucuya ulaşılamadı. Bağlantınızı kontrol edip tekrar deneyin.'
                            : 'Sistem hâlâ bakımda. Lütfen biraz sonra tekrar deneyin.',
                      ),
                    ],
                    const SizedBox(height: AppSpace.xl),
                    ElevatedButton.icon(
                      onPressed: _checking ? null : _retry,
                      icon: _checking
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: p.textSecondary,
                              ),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        _checking ? 'Kontrol ediliyor...' : 'Yeniden dene',
                      ),
                    ),
                    if (widget.operatorNotice != null) ...[
                      const SizedBox(height: AppSpace.md),
                      InlineNotice(
                        tone: AppTone.info,
                        message: widget.operatorNotice!,
                      ),
                    ],
                    if (widget.onOperatorLogin != null) ...[
                      const SizedBox(height: AppSpace.sm),
                      TextButton(
                        onPressed: widget.onOperatorLogin,
                        child: const Text('Yönetici girişi'),
                      ),
                    ],
                    if (support != null) ...[
                      const SizedBox(height: AppSpace.lg),
                      Text(
                        support,
                        textAlign: TextAlign.center,
                        style: th.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
