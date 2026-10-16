import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:site_kapi_kontrol/config/app_config.dart' as build_config;
import 'package:site_kapi_kontrol/models/app_config.dart' as remote;
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/app_config_service.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/views/help_content.dart';
import 'package:site_kapi_kontrol/ui/views/legal_document_view.dart';
import 'package:site_kapi_kontrol/ui/views/legal_markdown.dart';
import 'package:site_kapi_kontrol/ui/views/legal_parts.dart';
import 'package:site_kapi_kontrol/ui/views/onboarding_tour.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dış uygulamada bir adres açar (e-posta, telefon, https); açılamazsa false.
typedef HelpLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLauncher(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

Future<String> _defaultVersionLoader() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber.trim();
    return build.isEmpty ? info.version : '${info.version} ($build)';
  } catch (_) {
    // Platform bilgisi okunamadı: derleme sabiti gösterilir.
    return build_config.AppConfig.versionDisplay;
  }
}

/// "Yardım ve Destek" ekranı (yan menüden açılır): ilk kullanım turu, role göre "Nasıl yapılır", sık
/// sorulan sorular, destek iletişimi, "Hesabım ve verilerim" bilgisi, yasal belgeler ve uygulama sürümü.
///
/// Durumlar: destek bilgisi ve belge listesi ağdan gelir; yükleniyor | hata (neden + "Yeniden dene";
/// "yakında"/"boş" denmez) | veri | yok. Destek bilgisi tanımlı değilse "Destek bilgisi yakında" yazar.
class HelpView extends StatefulWidget {
  const HelpView({
    super.key,
    required this.role,
    this.residentMode = false,
    this.userId,
    this.legalApi,
    this.configService,
    this.versionLoader,
    this.launcher,
    this.onOpenProfile,
    this.onOpenLink,
  });

  final UserRole role;

  /// Site yöneticisi sakin modundaysa true (sakin yardımı gösterilir).
  final bool residentMode;

  /// Turu yeniden açınca "görüldü" işaretlensin diye (yoksa işaretlenmez).
  final int? userId;

  final LegalApi? legalApi;
  final AppConfigService? configService;

  /// Uygulama sürümü metni kaynağı (testler için).
  final Future<String> Function()? versionLoader;
  final HelpLauncher? launcher;

  /// "Profilim ekranına git" (ekran kapanır, çağıran menüyü Profilim'e alır). Verilmezse düğme yok.
  final VoidCallback? onOpenProfile;
  final LegalLinkOpener? onOpenLink;

  /// Ekranı yeni sayfa olarak açar.
  static Future<void> open(
    BuildContext context, {
    required UserRole role,
    bool residentMode = false,
    int? userId,
    VoidCallback? onOpenProfile,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => HelpView(
          role: role,
          residentMode: residentMode,
          userId: userId,
          onOpenProfile: onOpenProfile,
        ),
      ),
    );
  }

  @override
  State<HelpView> createState() => _HelpViewState();
}

enum _Load { loading, ready, failed }

class _HelpViewState extends State<HelpView> {
  late final LegalApi _legalApi = widget.legalApi ?? LegalApi.defaultInstance();
  late final AppConfigService _config = widget.configService ?? AppConfigService.instance;

  _Load _supportStatus = _Load.loading;
  remote.AppConfig? _supportConfig;

  _Load _legalStatus = _Load.loading;
  List<LegalDocumentSummary> _legalDocs = const <LegalDocumentSummary>[];
  String? _legalError;
  bool _legalInFlight = false;
  bool _supportInFlight = false;

  String? _version;
  bool _openingDocument = false;
  bool _tourOpening = false;

  @override
  void initState() {
    super.initState();
    final cached = _config.current;
    if (cached != null) {
      _supportConfig = cached;
      _supportStatus = _Load.ready;
    }
    unawaited(_loadSupport(silent: cached != null));
    unawaited(_loadLegal());
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    final text = await (widget.versionLoader ?? _defaultVersionLoader)();
    if (!mounted) return;
    setState(() => _version = text);
  }

  Future<void> _loadSupport({bool silent = false, bool force = false}) async {
    if (_supportInFlight) return;
    _supportInFlight = true;
    if (!silent && _supportStatus != _Load.loading) {
      setState(() => _supportStatus = _Load.loading);
    }
    remote.AppConfig? config;
    try {
      config = await _config.load(force: force);
    } catch (_) {
      config = null;
    }
    _supportInFlight = false;
    if (!mounted) return;
    setState(() {
      if (config != null) {
        _supportConfig = config;
        _supportStatus = _Load.ready;
      } else if (_supportConfig == null) {
        _supportStatus = _Load.failed;
      }
      // Sessiz yenileme başarısızsa eldeki (önbellekteki) bilgi kalır.
    });
  }

  Future<void> _loadLegal() async {
    if (_legalInFlight) return;
    _legalInFlight = true;
    if (_legalStatus != _Load.loading) {
      setState(() {
        _legalStatus = _Load.loading;
        _legalError = null;
      });
    }
    List<LegalDocumentSummary>? docs;
    String? failure;
    try {
      docs = await _legalApi.listDocuments();
    } on ApiException catch (e) {
      failure = e.message;
    } catch (_) {
      failure = LegalMessages.loadFailed;
    }
    _legalInFlight = false;
    if (!mounted) return;
    setState(() {
      if (docs != null) {
        _legalDocs = docs;
        _legalStatus = _Load.ready;
      } else {
        _legalStatus = _Load.failed;
        _legalError = failure;
      }
    });
    if (docs == null && failure != null) announcePolite(context, failure);
  }

  Future<void> _refresh() async {
    await Future.wait<void>(<Future<void>>[
      _loadSupport(silent: _supportConfig != null, force: true),
      _loadLegal(),
    ]);
  }

  Future<void> _openDocument(LegalDocumentSummary document) async {
    if (_openingDocument) return;
    _openingDocument = true;
    try {
      await LegalDocumentView.open(
        context,
        documentId: document.id,
        title: document.title,
        api: _legalApi,
        onOpenLink: widget.onOpenLink,
      );
    } finally {
      _openingDocument = false;
    }
  }

  Future<void> _showTour() async {
    if (_tourOpening) return;
    _tourOpening = true;
    try {
      await OnboardingTour.show(
        context,
        role: widget.role,
        residentMode: widget.residentMode,
        userId: widget.userId,
      );
    } finally {
      _tourOpening = false;
    }
  }

  Future<void> _launch(Uri uri, {required String fallbackText}) async {
    final opened = await (widget.launcher ?? _defaultLauncher)(uri);
    if (opened || !mounted) return;
    // Açılamadı (uygun uygulama yok): değer panoya kopyalanır, kullanıcı elle kullanabilir.
    await Clipboard.setData(ClipboardData(text: fallbackText));
    if (!mounted) return;
    AppSnack.show(
      context,
      'Uygulama açılamadı; bilgi panoya kopyalandı.',
      kind: AppSnackKind.warning,
    );
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    AppSnack.show(context, 'Panoya kopyalandı.', kind: AppSnackKind.success);
    announcePolite(context, 'Panoya kopyalandı.');
  }

  void _openProfile() {
    final callback = widget.onOpenProfile;
    if (callback == null) return;
    Navigator.of(context).pop();
    callback();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final audience = HelpContent.audienceFor(widget.role, residentMode: widget.residentMode);
    final topics = HelpContent.howToFor(audience);
    final hPad = MediaQuery.sizeOf(context).width < 400 ? AppSpace.md : AppSpace.lg;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: wrappedTitleToolbarHeight(context),
        titleTextStyle: wrappedTitleStyle(context),
        title: const Text('Yardım ve Destek', maxLines: 2, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(hPad, AppSpace.sm, hPad, AppSpace.xxl),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    AppCard(
                      level: 2,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const IconOrb(icon: Icons.support_agent_rounded, size: 48, glow: true),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Semantics(
                                  header: true,
                                  child: Text('Size nasıl yardımcı olabiliriz?', style: th.titleLarge),
                                ),
                                const SizedBox(height: AppSpace.xs),
                                Text(
                                  'Adım adım anlatımlar, sık sorulan sorular ve destek bilgileri burada.',
                                  style: th.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    _tourCard(context),
                    const SizedBox(height: AppSpace.xl),
                    const SectionHeader(title: 'Nasıl yapılır', icon: Icons.menu_book_rounded),
                    const SizedBox(height: AppSpace.sm),
                    for (final topic in topics) ...<Widget>[
                      _TopicTile(topic: topic),
                      const SizedBox(height: AppSpace.sm),
                    ],
                    const SizedBox(height: AppSpace.lg),
                    const SectionHeader(title: 'Sık sorulan sorular', icon: Icons.quiz_rounded),
                    const SizedBox(height: AppSpace.sm),
                    for (final faq in HelpContent.faqs) ...<Widget>[
                      _FaqTile(faq: faq),
                      const SizedBox(height: AppSpace.sm),
                    ],
                    const SizedBox(height: AppSpace.lg),
                    const SectionHeader(title: 'Destek', icon: Icons.headset_mic_rounded),
                    const SizedBox(height: AppSpace.sm),
                    _supportCard(context),
                    const SizedBox(height: AppSpace.xl),
                    const SectionHeader(title: 'Hesabım ve verilerim', icon: Icons.privacy_tip_rounded),
                    const SizedBox(height: AppSpace.sm),
                    _accountCard(context),
                    const SizedBox(height: AppSpace.xl),
                    const SectionHeader(title: 'Yasal belgeler', icon: Icons.gavel_rounded),
                    const SizedBox(height: AppSpace.sm),
                    _legalCard(context),
                    const SizedBox(height: AppSpace.xl),
                    Center(
                      child: Text(
                        _version == null ? 'Sürüm okunuyor...' : 'Uygulama sürümü: $_version',
                        key: const ValueKey<String>('help_version'),
                        textAlign: TextAlign.center,
                        style: th.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tourCard(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppCard(
      onTap: _showTour,
      semanticLabel: 'Tanıtım turunu yeniden göster',
      child: Row(
        children: <Widget>[
          const IconOrb(icon: Icons.slideshow_rounded, size: 40, shape: IconOrbShape.squircle),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Tanıtım turunu göster', style: th.titleMedium),
                const SizedBox(height: AppSpace.xs),
                Text('Uygulamanın temel özelliklerini kısaca yeniden gözden geçirin.', style: th.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }

  // --- Destek ----------------------------------------------------------------------------------

  Widget _supportCard(BuildContext context) {
    final th = Theme.of(context).textTheme;
    switch (_supportStatus) {
      case _Load.loading:
        return const AppCard(child: _InlineLoading(label: 'Destek bilgisi yükleniyor'));
      case _Load.failed:
        return AppCard(
          child: LegalRetryNotice(
            message: 'Destek bilgisi alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
            onRetry: () => unawaited(_loadSupport(force: true)),
          ),
        );
      case _Load.ready:
        final config = _supportConfig;
        final email = _validEmail(config?.supportEmail);
        final phone = _validPhone(config?.supportPhone);
        final web = _validHttps(config?.supportWebUrl);
        final hours = config?.supportHours;
        if (config == null || (email == null && phone == null && web == null && hours == null)) {
          return AppCard(
            child: Row(
              children: <Widget>[
                const IconOrb(icon: Icons.schedule_rounded, tone: AppTone.neutral, size: 40, shape: IconOrbShape.squircle),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    'Destek bilgisi yakında',
                    key: const ValueKey<String>('help_support_soon'),
                    style: th.titleMedium,
                  ),
                ),
              ],
            ),
          );
        }
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (email != null)
                _SupportRow(
                  icon: Icons.mail_outline_rounded,
                  label: 'E-posta',
                  value: email,
                  actions: <Widget>[
                    _actionButton(
                      'E-posta gönder',
                      Icons.send_rounded,
                      () => unawaited(_launch(Uri(scheme: 'mailto', path: email), fallbackText: email)),
                    ),
                    _actionButton('Kopyala', Icons.copy_rounded, () => unawaited(_copy(email))),
                  ],
                ),
              if (phone != null)
                _SupportRow(
                  icon: Icons.phone_outlined,
                  label: 'Telefon',
                  value: phone,
                  actions: <Widget>[
                    _actionButton(
                      'Ara',
                      Icons.call_rounded,
                      () => unawaited(
                        _launch(
                          Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')),
                          fallbackText: phone,
                        ),
                      ),
                    ),
                    _actionButton('Kopyala', Icons.copy_rounded, () => unawaited(_copy(phone))),
                  ],
                ),
              if (hours != null)
                _SupportRow(icon: Icons.schedule_rounded, label: 'Çalışma saatleri', value: hours),
              if (web != null)
                _SupportRow(
                  icon: Icons.language_rounded,
                  label: 'Web sitesi',
                  value: web.host,
                  actions: <Widget>[
                    _actionButton(
                      'Web sitesini aç',
                      Icons.open_in_new_rounded,
                      () => unawaited(_launch(web, fallbackText: web.toString())),
                    ),
                  ],
                ),
            ],
          ),
        );
    }
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    );
  }

  /// Sunucudan gelen değerlerin kaba doğrulaması: geçersizse (boşluk içeren e-posta, https olmayan adres...)
  /// o satır hiç gösterilmez.
  static String? _validEmail(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text) ? text : null;
  }

  static String? _validPhone(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return RegExp(r'^\+?[0-9()\-\s]{7,24}$').hasMatch(text) ? text : null;
  }

  static Uri? _validHttps(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
    return uri;
  }

  // --- Hesabım ve verilerim --------------------------------------------------------------------

  Widget _accountCard(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final onOpenProfile = widget.onOpenProfile;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(HelpContent.accountAndDataText, style: th.bodyMedium),
          if (onOpenProfile != null) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _openProfile,
                icon: const Icon(Icons.account_circle_outlined, size: 18),
                label: const Text('Profilim ekranına git'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Yasal belgeler --------------------------------------------------------------------------

  Widget _legalCard(BuildContext context) {
    final th = Theme.of(context).textTheme;
    switch (_legalStatus) {
      case _Load.loading:
        return const AppCard(child: _InlineLoading(label: 'Belgeler yükleniyor'));
      case _Load.failed:
        return AppCard(
          child: LegalRetryNotice(
            message: _legalError ?? LegalMessages.loadFailed,
            onRetry: () => unawaited(_loadLegal()),
          ),
        );
      case _Load.ready:
        if (_legalDocs.isEmpty) {
          return AppCard(
            child: Text('Şu an yayımlanmış bir belge yok.', style: th.bodyMedium),
          );
        }
        return AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Column(
            children: <Widget>[
              for (final document in _legalDocs)
                ListTile(
                  key: ValueKey<String>('help_legal_${document.id}'),
                  leading: const Icon(Icons.description_outlined),
                  title: Text(document.title),
                  subtitle: Text(_legalSubtitle(document)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  minVerticalPadding: AppSpace.sm,
                  onTap: () => unawaited(_openDocument(document)),
                ),
            ],
          ),
        );
    }
  }

  static String _legalSubtitle(LegalDocumentSummary document) {
    final date = formatLegalDate(document.effectiveDate);
    return date == null ? 'Sürüm: ${document.version}' : 'Sürüm: ${document.version} · Yürürlük: $date';
  }
}

/// Yükleniyor satırı (iskelet + ekran okuyucu etiketi).
class _InlineLoading extends StatelessWidget {
  const _InlineLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: const ExcludeSemantics(
        child: ShimmerScope(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FractionallySizedBox(
                widthFactor: 0.5,
                alignment: Alignment.centerLeft,
                child: SkeletonBox(),
              ),
              SizedBox(height: AppSpace.md),
              SkeletonBox(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportRow extends StatelessWidget {
  const _SupportRow({
    required this.icon,
    required this.label,
    required this.value,
    this.actions = const <Widget>[],
  });

  final IconData icon;
  final String label;
  final String value;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2, right: AppSpace.md),
            child: ExcludeSemantics(child: Icon(icon, size: 22, color: p.textSecondary)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: th.bodySmall),
                const SizedBox(height: 2),
                Text(value, style: th.bodyLarge),
                if (actions.isNotEmpty)
                  Wrap(spacing: AppSpace.xs, runSpacing: 0, children: actions),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Katlanır kart iskeleti: soru/başlık + açılınca içerik. `ExpansionTile` açık/kapalı durumunu ekran
/// okuyucuya bildirir; başlık sarar (kırpılmaz).
class _ExpandCard extends StatelessWidget {
  const _ExpandCard({required this.title, required this.children, this.leading});

  final String title;
  final List<Widget> children;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: leading,
          title: Text(title, style: th.titleMedium),
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xs),
          childrenPadding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          expandedAlignment: Alignment.centerLeft,
          children: children,
        ),
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic});

  final HelpTopic topic;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return _ExpandCard(
      title: topic.title,
      leading: ExcludeSemantics(child: Icon(topic.icon, color: p.textSecondary)),
      children: <Widget>[
        for (var i = 0; i < topic.steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 28,
                  child: Text('${i + 1}.', style: th.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Expanded(child: Text(topic.steps[i], style: th.bodyLarge)),
              ],
            ),
          ),
        if (topic.note != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: InlineNotice(tone: AppTone.info, message: topic.note!),
          ),
      ],
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.faq});

  final HelpFaq faq;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return _ExpandCard(
      title: faq.question,
      children: <Widget>[Text(faq.answer, style: th.bodyLarge)],
    );
  }
}
