import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/announcements_admin_view.dart';
import 'package:site_kapi_kontrol/ui/views/announcements_inbox_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/push_soft_prompt_card.dart';

/// "Duyurular" ekranı (Platform Faz 3a, çekirdek `announcements` modülü). Kullanıcının rolüne göre iki
/// görünüm barındırır:
///
/// - **Gelen kutusu** ([showInbox]): daire sakini (ve sakin modundaki yönetici): kronolojik duyuru listesi,
///   okundu işaretleme, çekmece rozeti. Yeni duyurular uygulama açıkken yaklaşık 20 saniyede bir
///   kontrol edilir (anlık itme DEĞİL); açıklama metni bunu söyler.
/// - **Yönetim** ([manageSites] / [readOnlySites]): yönetici / süper kullanıcı: oluşturma, düzenleme,
///   yayınlama, geri çekme, alıcılar; kurul üyesi aynı ekranı SALT OKUNUR görür.
///
/// İkisi birden varsa (yönetim kurulu üyesi olan sakin) üstte iki seçenek çıkar; tek görünüm varsa
/// seçenek çizilmez. Hiçbiri yoksa açıklayıcı boş durum gösterilir. [AnnouncementsViewState.reload] sayfa
/// kabuğunun aşağı çekip yenilemesinden çağrılır.
class AnnouncementsView extends StatefulWidget {
  const AnnouncementsView({
    super.key,
    required this.authService,
    this.manageSites = false,
    this.readOnlySites = const <PeopleSite>[],
    this.showInbox = false,
    this.inboxSites = const <PeopleSite>[],
    this.notifier,
    this.preferInbox = false,
  });

  final AuthService authService;
  final bool manageSites;
  final List<PeopleSite> readOnlySites;
  final bool showInbox;
  final List<PeopleSite> inboxSites;
  final AnnouncementNotifier? notifier;

  /// true (şeritten / bildirimden gelindi): her iki görünüm de varsa gelen kutusu AÇILIR. Varsayılan
  /// (false): gelen kutusu varsa o, yoksa yönetim.
  final bool preferInbox;

  @override
  State<AnnouncementsView> createState() => AnnouncementsViewState();
}

enum _Mode { inbox, manage }

class AnnouncementsViewState extends State<AnnouncementsView> {
  _Mode? _chosen;
  final GlobalKey<AnnouncementsInboxViewState> _inboxKey =
      GlobalKey<AnnouncementsInboxViewState>();
  final GlobalKey<AnnouncementsAdminViewState> _adminKey =
      GlobalKey<AnnouncementsAdminViewState>();

  // Telefon bildirimi (Faz 3b-B): açıklama cümlesi bu cihazın durumuna göre seçilir; gelen kutusunda "Aç" kartı.
  late final PushService _push = PushService.instance;

  @override
  void initState() {
    super.initState();
    widget.notifier?.addListener(_onNotifier);
    _push.activeHere.addListener(_onNotifier);
    if (widget.preferInbox) _chosen = _Mode.inbox;
  }

  @override
  void didUpdateWidget(AnnouncementsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notifier, widget.notifier)) {
      oldWidget.notifier?.removeListener(_onNotifier);
      widget.notifier?.addListener(_onNotifier);
    }
    if (widget.preferInbox && !oldWidget.preferInbox) _chosen = _Mode.inbox;
  }

  @override
  void dispose() {
    widget.notifier?.removeListener(_onNotifier);
    _push.activeHere.removeListener(_onNotifier);
    super.dispose();
  }

  void _onNotifier() {
    if (!mounted) return;
    // Telefon bildirimi durumu bir kare kurulurken değişebilir: yeniden çizim sonraki kareye bırakılır.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  bool get _hasManage => widget.manageSites || widget.readOnlySites.isNotEmpty;
  bool get _hasInbox => widget.showInbox;

  /// Gösterilen görünüm: seçilen hâlâ varsa o, yoksa gelen kutusu, yoksa yönetim.
  _Mode? get _mode {
    final chosen = _chosen;
    if (chosen == _Mode.inbox && _hasInbox) return _Mode.inbox;
    if (chosen == _Mode.manage && _hasManage) return _Mode.manage;
    if (_hasInbox) return _Mode.inbox;
    if (_hasManage) return _Mode.manage;
    return null;
  }

  /// Çekip yenileme: görünen görünümün verisini yeniden çeker.
  Future<void> reload() async {
    switch (_mode) {
      case _Mode.inbox:
        await (_inboxKey.currentState?.reload() ?? Future<void>.value());
      case _Mode.manage:
        await (_adminKey.currentState?.reload() ?? Future<void>.value());
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final mode = _mode;
    final Widget content;
    switch (mode) {
      case _Mode.inbox:
        content = AnnouncementsInboxView(
          key: _inboxKey,
          authService: widget.authService,
          notifier: widget.notifier,
          sites: widget.inboxSites,
        );
      case _Mode.manage:
        content = AnnouncementsAdminView(
          key: _adminKey,
          authService: widget.authService,
          manageSites: widget.manageSites,
          readOnlySites: widget.readOnlySites,
        );
      case null:
        content = const EmptyCard(
          icon: Icons.campaign_rounded,
          title: 'Duyuru bulunamadı.',
          message: 'Duyurular, bir siteye bağlı olduğunuzda burada görünür.',
        );
    }
    // Telefon bildirimi YALNIZ bu cihazda açık, kayıtlı ve sunucuda push açıkken gelir (Faz 3b-B); normal duyurular
    // ayrıca kullanıcının tercihlerine (anahtar, sessiz saatler) bağlıdır.
    final closedNote = _push.activeHere.value
        ? 'uygulama kapalıyken bu cihaza telefon bildirimi gelir (Bildirim Tercihleri\'nize göre).'
        : 'uygulama kapalıyken bu cihaza telefon bildirimi gelmez.';
    final description = switch (mode) {
      _Mode.inbox =>
        (widget.notifier?.isDegraded ?? false)
            ? 'Yönetimin size gönderdiği duyurular burada görünür. Bağlantı sorunu: yeni duyurular '
                  'daha seyrek kontrol ediliyor; $closedNote'
            : 'Yönetimin size gönderdiği duyurular burada görünür. Yeni duyurular uygulama açıkken '
                  'yaklaşık 20 saniyede bir kontrol edilir; $closedNote',
      _Mode.manage =>
        'Sitenizdeki sakinlere duyuru gönderin, okunma durumunu izleyin. Duyurular uygulamada '
            've (isterseniz) e-postayla iletilir.',
      null => 'Sitenizin duyuruları burada görünür.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Duyurular', icon: Icons.campaign_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(description, style: th.bodyMedium),
        const SizedBox(height: AppSpace.lg),
        // Yalnız koşullar sağlanınca görünür; aksi hâlde yer kaplamaz.
        if (mode == _Mode.inbox)
          PushSoftPromptCard(authService: widget.authService, pushService: _push),
        if (_hasInbox && _hasManage) ...[
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              ChoiceChip(
                key: const ValueKey<String>('announcements_mode_inbox'),
                avatar: const Icon(Icons.inbox_rounded, size: 18),
                label: const Text('Gelen kutusu'),
                selected: mode == _Mode.inbox,
                onSelected: (_) => setState(() => _chosen = _Mode.inbox),
              ),
              ChoiceChip(
                key: const ValueKey<String>('announcements_mode_manage'),
                avatar: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text('Yönetim görünümü'),
                selected: mode == _Mode.manage,
                onSelected: (_) => setState(() => _chosen = _Mode.manage),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        content,
      ],
    );
  }
}
