import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/app_config.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mağaza bağlantısını açan işlev; testlerde değiştirilebilir. `false`/hata = açılamadı.
typedef StoreLauncher = Future<bool> Function(Uri uri);

/// Varsayılan: bağlantıyı harici uygulamada (mağaza/tarayıcı) açar.
Future<bool> openStoreUrl(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Sunucudaki destek bilgilerinden tek satırlık özet ("Destek: e-posta · telefon · saat"); yoksa `null`.
String? gateSupportSummary(AppConfig? config) {
  if (config == null) return null;
  final parts = <String>[
    ?config.supportEmail,
    ?config.supportPhone,
    ?config.supportHours,
  ];
  if (parts.isEmpty) return null;
  return 'Destek: ${parts.join(' · ')}';
}

Future<bool> _safeOpen(StoreLauncher launcher, String url) async {
  try {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.toLowerCase() != 'https') return false;
    return await launcher(uri);
  } catch (_) {
    return false;
  }
}

/// Zorunlu güncelleme ekranı: kurulu sürüm sunucudaki `min_supported_version` altında.
///
/// Tam ekrandır, geri dönüş yoktur. [storeUrl] varsa "Güncelle" düğmesi mağazayı açar; yoksa genel yönerge
/// gösterilir. Bağlantı açılamazsa kullanıcıya elle güncelleme yönergesi verilir.
class UpdateRequiredView extends StatefulWidget {
  const UpdateRequiredView({
    super.key,
    required this.installedVersion,
    required this.minimumVersion,
    this.storeUrl,
    this.config,
    this.launcher = openStoreUrl,
    this.onOperatorLogin,
    this.operatorNotice,
  });

  final String installedVersion;
  final String minimumVersion;

  /// Verilirse "Yönetici girişi" düğmesi görünür (süper kullanıcı kapıyı geçip ayarları düzeltebilsin).
  final VoidCallback? onOperatorLogin;

  /// Yönetici girişi denemesinin sonucu (örn. "bu cihazda başka hesap açık"); yoksa `null`.
  final String? operatorNotice;

  /// Platformun mağaza bağlantısı (yalnız https); yoksa `null`.
  final String? storeUrl;

  /// Destek bilgisi göstermek için (isteğe bağlı).
  final AppConfig? config;

  final StoreLauncher launcher;

  @override
  State<UpdateRequiredView> createState() => _UpdateRequiredViewState();
}

class _UpdateRequiredViewState extends State<UpdateRequiredView> {
  bool _opening = false;
  bool _openFailed = false;

  Future<void> _open() async {
    final url = widget.storeUrl;
    if (url == null || _opening) return;
    setState(() {
      _opening = true;
      _openFailed = false;
    });
    final ok = await _safeOpen(widget.launcher, url);
    if (!mounted) return;
    setState(() {
      _opening = false;
      _openFailed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final hPad = MediaQuery.sizeOf(context).width < 400
        ? AppSpace.lg
        : AppSpace.xl;
    final hasUrl = widget.storeUrl != null;
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
                        icon: Icons.system_update_rounded,
                        tone: AppTone.primary,
                        size: 72,
                        glow: true,
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    Semantics(
                      header: true,
                      child: Text(
                        'Güncelleme gerekli',
                        textAlign: TextAlign.center,
                        style: th.titleLarge,
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      'Uygulamanın bu sürümü (${widget.installedVersion}) artık '
                      'desteklenmiyor. Devam etmek için lütfen ${widget.minimumVersion} '
                      'veya daha yeni bir sürüme güncelleyin.',
                      textAlign: TextAlign.center,
                      style: th.bodyMedium,
                    ),
                    if (!hasUrl) ...[
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        'Uygulamayı mağazadan (Google Play veya App Store) '
                        'güncelleyebilirsiniz.',
                        textAlign: TextAlign.center,
                        style: th.bodyMedium,
                      ),
                    ],
                    if (_openFailed) ...[
                      const SizedBox(height: AppSpace.md),
                      const InlineNotice(
                        tone: AppTone.warning,
                        message:
                            'Mağaza bağlantısı açılamadı. Lütfen uygulamayı '
                            'mağazadan elle güncelleyin.',
                      ),
                    ],
                    if (hasUrl) ...[
                      const SizedBox(height: AppSpace.xl),
                      ElevatedButton.icon(
                        onPressed: _opening ? null : _open,
                        icon: const Icon(Icons.system_update_alt_rounded),
                        label: const Text('Güncelle'),
                      ),
                    ],
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

/// `latest_version` için kapatılabilir yumuşak uyarı kartı (uygulama engellenmez).
///
/// Kapat'a basınca [onDismiss] çağrılır; kapı o sürüm için bir daha göstermez.
class SoftUpdateBanner extends StatefulWidget {
  const SoftUpdateBanner({
    super.key,
    required this.latestVersion,
    required this.onDismiss,
    this.storeUrl,
    this.launcher = openStoreUrl,
  });

  final String latestVersion;
  final VoidCallback onDismiss;
  final String? storeUrl;
  final StoreLauncher launcher;

  @override
  State<SoftUpdateBanner> createState() => _SoftUpdateBannerState();
}

class _SoftUpdateBannerState extends State<SoftUpdateBanner> {
  bool _failed = false;

  Future<void> _open() async {
    final url = widget.storeUrl;
    if (url == null) return;
    final ok = await _safeOpen(widget.launcher, url);
    if (!mounted) return;
    if (!ok) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final hasUrl = widget.storeUrl != null;
    return Semantics(
      container: true,
      liveRegion: true,
      child: AppCard(
        level: 3,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Yeni sürüm hazır (${widget.latestVersion})',
              style: th.titleSmall,
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              _failed || !hasUrl
                  ? 'Uygulamayı mağazadan güncelleyebilirsiniz.'
                  : 'Yeni özellikler ve düzeltmeler için güncelleyin.',
              style: th.bodySmall,
            ),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                TextButton(
                  onPressed: widget.onDismiss,
                  child: Text(hasUrl ? 'Sonra' : 'Tamam'),
                ),
                if (hasUrl)
                  FilledButton(onPressed: _open, child: const Text('Güncelle')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
