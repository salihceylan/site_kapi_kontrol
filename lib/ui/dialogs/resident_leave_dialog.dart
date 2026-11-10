import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_management.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;

/// Sakin tarafı 360° Daireden Ayrılma Onay Penceresi.
///
/// Sakin bu daireden ayrılmak istediğinde kapı yetkisi, otopark plakaları,
/// misafir linkleri, rezervasyonları ve aidat borcu durumunu net olarak görerek onaylar.
class ResidentLeaveDialog extends StatefulWidget {
  const ResidentLeaveDialog({
    super.key,
    required this.service,
    required this.apartment,
  });

  final ApartmentManagementService service;
  final MyApartment apartment;

  static Future<bool?> show(
    BuildContext context, {
    required ApartmentManagementService service,
    required MyApartment apartment,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ResidentLeaveDialog(service: service, apartment: apartment),
    );
  }

  @override
  State<ResidentLeaveDialog> createState() => _ResidentLeaveDialogState();
}

class _ResidentLeaveDialogState extends State<ResidentLeaveDialog> {
  bool _loading = true;
  String? _error;
  ExitPreview? _preview;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await widget.service.exitPreview(widget.apartment.apartmentId);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // If exitPreview fails (e.g. network), fallback to default empty preview
      setState(() {
        _preview = const ExitPreview();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final apt = widget.apartment;
      if (apt.myRole == 'tenant') {
        await widget.service.exitTenancy(apt.apartmentId);
      } else {
        await widget.service.leave(apt.apartmentId);
      }

      if (!mounted) return;
      AppSnack.show(
        context,
        'Daireden ayrılma işlemi tamamlandı.',
        kind: AppSnackKind.success,
      );
      popIfCurrent(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = crmMessageOf(e, 'Daireden ayrılma işlemi kaydedilemedi. Lütfen tekrar deneyin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final apt = widget.apartment;
    final th = Theme.of(context).textTheme;
    final pal = context.palette;

    Widget body;
    if (_loading) {
      body = const DialogRowsSkeleton(
        rows: 3,
        caption: 'Ayrılma bilgileri hazırlanıyor...',
      );
    } else {
      final p = _preview ?? const ExitPreview();
      body = SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              InlineNotice(message: _error!, onRetry: () => setState(() => _error = null)),
              const SizedBox(height: AppSpace.md),
            ],

            // BAŞLIK BİLGİ KARTI
            DialogPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.home_work_rounded, size: 24, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              apt.label.isNotEmpty ? apt.label : 'Dairem',
                              style: th.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: AppSpace.xs,
                              runSpacing: 4,
                              children: [
                                StatusChip(
                                  label: apt.myRole == 'tenant'
                                      ? 'Kiracı'
                                      : (apt.myRole == 'owner' ? 'Kat Maliki' : 'Aile Üyesi'),
                                  tone: AppTone.primary,
                                ),
                                if (apt.isAdmin)
                                  const StatusChip(
                                    label: 'Daire Yöneticisi',
                                    tone: AppTone.warning,
                                    icon: Icons.admin_panel_settings_rounded,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    'Bu daireden ayrıldığınızda sistemde aşağıdaki değişiklikler uygulanacaktır:',
                    style: th.bodyMedium?.copyWith(color: pal.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),

            // MADDELER KARTI
            DialogPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildItem(
                    context,
                    icon: Icons.lock_clock_rounded,
                    title: 'Kapı Geçiş Yetkileri',
                    description: 'Bu daireye ait kapı geçiş şifreniz, Bluetooth ve QR izinleriniz anında iptal edilecektir.',
                    tone: AppTone.warning,
                  ),
                  const Divider(height: AppSpace.lg),
                  _buildItem(
                    context,
                    icon: Icons.directions_car_rounded,
                    title: 'Otopark & Plaka Tanıma (PTS)',
                    description: p.vehiclesCount > 0
                        ? 'Kayıtlı ${p.vehiclesCount} aracınızın otopark bariyer yetkisi sonlandırılacak ve kota serbest kalacaktır.'
                        : 'Kişisel araç plakası yetkileriniz sonlandırılacaktır.',
                    tone: p.vehiclesCount > 0 ? AppTone.warning : AppTone.neutral,
                  ),
                  if (p.reservationsCount > 0 || p.guestPassesCount > 0) ...[
                    const Divider(height: AppSpace.lg),
                    _buildItem(
                      context,
                      icon: Icons.event_busy_rounded,
                      title: 'Rezervasyon ve Misafir Linkleri',
                      description: '${p.reservationsCount} adet tesis rezervasyonunuz ve ${p.guestPassesCount} adet misafir linkiniz iptal edilecektir.',
                      tone: AppTone.warning,
                    ),
                  ],
                  const Divider(height: AppSpace.lg),
                  _buildItem(
                    context,
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'Aidat & Borç Durumu',
                    description: p.hasDebt
                        ? 'Dairenize ait ${p.debtText} ödenmemiş borç bulunmaktadır. Borç kaydı sistemde saklanır; ev sahibine bilgilendirme iletilir.'
                        : 'Daireye ait vadesi geçmiş borcunuz bulunmamaktadır.',
                    tone: p.hasDebt ? AppTone.danger : AppTone.success,
                  ),
                  if (p.familyCount > 0) ...[
                    const Divider(height: AppSpace.lg),
                    _buildItem(
                      context,
                      icon: Icons.group_remove_rounded,
                      title: 'Hane / Aile Üyeleri',
                      description: 'Kiracılık sonlandığında hanenizdeki ${p.familyCount} aile üyesinin de daire erişimi sona erecektir.',
                      tone: AppTone.warning,
                    ),
                  ],
                  const Divider(height: AppSpace.lg),
                  _buildItem(
                    context,
                    icon: Icons.verified_user_rounded,
                    title: 'Hesabınız Korunur',
                    description: 'Antigravity / AHBU hesabınız, telefonunuz ve profiliniz silinmez. Başka bir daireye veya siteye yeniden katılabilirsiniz.',
                    tone: AppTone.info,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),

            const InlineNotice(
              tone: AppTone.danger,
              icon: Icons.warning_amber_rounded,
              message: 'Daireden ayrılma işlemi geri alınamaz. Diğer üyelere bildirim gitmez. Yeniden katılmak için yöneticiden veya ev sahibinden davet almanız gerekir.',
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: !_submitting,
      child: AppDialog(
        title: 'Bu Daireden Ayrıl',
        subtitle: apt.label.isNotEmpty ? apt.label : null,
        icon: Icons.logout_rounded,
        tone: AppTone.danger,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => popIfCurrent(context, false),
            child: const Text('Vazgeç'),
          ),
          if (!_loading)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'İşleniyor...' : 'Ayrıl'),
            ),
        ],
        child: body,
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required AppTone tone,
  }) {
    final th = Theme.of(context).textTheme;
    final pal = context.palette;

    Color iconColor;
    switch (tone) {
      case AppTone.danger:
        iconColor = Colors.red;
        break;
      case AppTone.warning:
        iconColor = Colors.orange;
        break;
      case AppTone.success:
        iconColor = Colors.green;
        break;
      case AppTone.info:
        iconColor = Theme.of(context).colorScheme.primary;
        break;
      default:
        iconColor = pal.textSecondary;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(description, style: th.bodySmall?.copyWith(color: pal.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
