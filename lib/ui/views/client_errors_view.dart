import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/account_client_error.dart';
import 'package:site_kapi_kontrol/services/account_api.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "İstemci Hataları" ekranı (yalnız süper kullanıcı): uygulamalardan gelen hata raporları
/// (`GET /admin/client-errors`). Aynı hata tek kayıtta toplanır (sayı, ilk / son görülme, örnek yığın).
///
/// İmleçli sayfalama: sonraki sayfa `cursor` ile istenir ve listenin SONUNA eklenir (aynı parmak izi iki kez
/// gösterilmez). İlk yüklemede iskelet; hata varsa "kayıt yok" yerine hata + "Tekrar Dene" (hata durumunda
/// yanlış boş iletisi yok). Yenileme sürerken eski liste ekranda kalır; eski imleçle gelen sayfa yeni listeyi
/// ezmez (jeton).
class ClientErrorsView extends StatefulWidget {
  const ClientErrorsView({super.key, required this.authService, this.service});

  final AuthService authService;

  /// Testler için; verilmezse [authService] üzerinden kurulur.
  final AccountService? service;

  /// Sayfa başına kayıt.
  static const int pageSize = 50;

  @override
  State<ClientErrorsView> createState() => ClientErrorsViewState();
}

class ClientErrorsViewState extends State<ClientErrorsView> {
  AccountService? _ownService;
  List<ClientErrorItem> _items = const <ClientErrorItem>[];
  String? _next;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadedOnce = false;
  String? _error;
  String? _moreError;
  int _token = 0;
  int _moreToken = 0;

  AccountService get _service =>
      widget.service ?? (_ownService ??= AccountService(authService: widget.authService));

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    ++_token;
    ++_moreToken;
    super.dispose();
  }

  String _messageOf(Object error, String fallback) =>
      error is ApiException && error.message.trim().isNotEmpty ? error.message : fallback;

  /// İlk sayfayı yeniden çeker; mevcut liste yenileme sürerken kalır, süren "Daha fazla yükle" iptal edilir.
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_token;
    ++_moreToken;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _moreError = null;
    });
    try {
      final page = await _service.listClientErrors(limit: ClientErrorsView.pageSize);
      if (!mounted || token != _token) return;
      setState(() {
        _items = page.items;
        _next = page.items.isEmpty ? null : page.nextCursor;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = _messageOf(
          e,
          'İstemci hataları yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  /// Üst üste en çok bu kadar "yalnız yinelenen" sayfa kendiliğinden atlanır (sunucuda devam varken düğme
  /// kaybolmasın, kullanıcı boş dokunuşlarla uğraşmasın); sonra imleç ilerlemiş halde kullanıcıya bırakılır.
  static const int _maxSkippedPages = 5;

  Future<void> _loadMore() async {
    var cursor = _next;
    if (cursor == null || _loadingMore || _loading) return;
    final more = ++_moreToken;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      for (var attempt = 0; attempt < _maxSkippedPages; attempt++) {
        final page = await _service.listClientErrors(
          limit: ClientErrorsView.pageSize,
          cursor: cursor,
        );
        // Bu arada yenileme oldu: eski imleçle gelen sayfa eklenmez.
        if (!mounted || more != _moreToken) return;
        final known = _items.map((e) => e.fingerprint).toSet();
        final fresh = page.items.where((e) => !known.contains(e.fingerprint)).toList();
        // Aynı imleç tekrarlanıyorsa sunucu tutarsızdır: dur (sonsuz döngü olmasın). Aksi hâlde imleç ilerler.
        final next = page.nextCursor == cursor ? null : page.nextCursor;
        if (fresh.isNotEmpty || next == null) {
          setState(() {
            _items = <ClientErrorItem>[..._items, ...fresh];
            _next = next;
            _loadingMore = false;
          });
          announcePolite(
            context,
            fresh.isEmpty ? 'Başka hata kaydı yok.' : '${fresh.length} yeni hata kaydı yüklendi.',
          );
          return;
        }
        // Yalnız yinelenen kayıtlar geldi ama sunucuda devam var: sonraki sayfaya geç. İmleç hemen saklanır; sonraki
        // istek hata verirse "Tekrar Dene" kaldığı yerden sürer.
        cursor = next;
        setState(() => _next = next);
      }
      setState(() => _loadingMore = false);
    } catch (e) {
      if (!mounted || more != _moreToken) return;
      setState(() {
        _loadingMore = false;
        _moreError = _messageOf(e, 'Daha fazla kayıt yüklenemedi. Tekrar deneyin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final Widget list;
    if (_items.isEmpty) {
      if (_loading || (_error == null && !_loadedOnce)) {
        list = const ListSkeleton(rows: 3);
      } else if (_error != null) {
        list = InlineNotice(message: _error!, onRetry: reload);
      } else {
        list = const EmptyCard(
          icon: Icons.bug_report_outlined,
          title: 'Kayıtlı istemci hatası yok.',
          message: 'Uygulamalardan gelen hata raporları (90 gün) burada listelenir.',
          tone: AppTone.success,
        );
      }
    } else {
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InlineNotice(message: _error!, onRetry: reload),
            const SizedBox(height: AppSpace.md),
          ],
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: ClientErrorCard(key: ValueKey<String>('client_error_${item.fingerprint}'), item: item),
            ),
          if (_moreError != null) ...[
            InlineNotice(message: _moreError!, onRetry: _loadMore),
            const SizedBox(height: AppSpace.md),
          ],
          if (_next != null)
            Align(
              alignment: Alignment.center,
              child: PrimaryActionButton(
                label: 'Daha fazla yükle',
                icon: Icons.expand_more_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                loading: _loadingMore,
                // Yenileme sürerken eski imleçle yeni sayfa istenmez.
                onPressed: (_loadingMore || _loading) ? null : _loadMore,
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'İstemci Hataları', icon: Icons.bug_report_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Uygulamalardan gelen hata raporları. Aynı hata tek kayıtta toplanır; kişisel veriler sunucuda '
          'maskelenir ve kayıtlar 90 gün sonra silinir.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        SectionHeader(
          title: 'Hatalar',
          trailing: IconButton(
            onPressed: _loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        list,
      ],
    );
  }
}

/// Bir istemci hatası kartı: tür, ileti, sayı / platform / sürüm çipleri, ilk-son görülme ve açılır örnek yığın.
class ClientErrorCard extends StatefulWidget {
  const ClientErrorCard({super.key, required this.item});

  final ClientErrorItem item;

  @override
  State<ClientErrorCard> createState() => _ClientErrorCardState();
}

class _ClientErrorCardState extends State<ClientErrorCard> {
  bool _showStack = false;

  Future<void> _copy() async {
    final item = widget.item;
    final text = StringBuffer()
      ..writeln('${item.errorType}: ${item.message}')
      ..writeln(
        '${item.platformLabel} • v${item.appVersion.isEmpty ? '?' : item.appVersion} • ${item.count} kez'
        '${item.fatal ? ' • çökme' : ''}',
      );
    if (item.sampleStack.isNotEmpty) text.write('\n${item.sampleStack}');
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (!mounted) return;
    AppSnack.show(context, 'Hata ayrıntısı panoya kopyalandı.', kind: AppSnackKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final hasStack = item.sampleStack.trim().isNotEmpty;
    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              InfoChip(item.fatal ? 'Çökme' : 'Hata', tone: item.fatal ? AppTone.danger : AppTone.warning),
              InfoChip('${item.count} kez', tone: AppTone.primary),
              InfoChip(item.platformLabel),
              if (item.appVersion.isNotEmpty) InfoChip('v${item.appVersion}'),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            item.errorType.isEmpty ? 'Bilinmeyen hata türü' : item.errorType,
            style: th.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (item.message.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(item.message, style: th.bodyMedium),
          ],
          const SizedBox(height: AppSpace.sm),
          Text(
            'İlk görülme: ${formatIstanbulDateTime(item.firstSeen)}',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
          Text(
            'Son görülme: ${formatIstanbulDateTime(item.lastSeen)}',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
          if (hasStack) ...[
            const SizedBox(height: AppSpace.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey<String>('client_error_stack_toggle_${item.fingerprint}'),
                onPressed: () => setState(() => _showStack = !_showStack),
                icon: Icon(_showStack ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                label: Text(_showStack ? 'Örnek yığını gizle' : 'Örnek yığını göster'),
              ),
            ),
            ExpandableSection(
              expanded: _showStack,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: p.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: SelectableText(
                        item.sampleStack,
                        key: ValueKey<String>('client_error_stack_${item.fingerprint}'),
                        style: th.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.35),
                      ),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Ayrıntıyı kopyala'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
