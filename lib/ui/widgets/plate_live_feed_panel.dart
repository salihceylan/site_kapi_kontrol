import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/license_plate.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Karar rozeti türü (sunucu `decision_kind`; eski kayıtlarda `decision` değerinden türetilir).
enum LiveDecision { acildi, red, tanimsiz, karaListe }

LiveDecision liveDecisionOf(PlateDecisionRow e) => switch (e.decisionKind) {
  'acildi' => LiveDecision.acildi,
  'red' => LiveDecision.red,
  'kara_liste' => LiveDecision.karaListe,
  'tanimsiz' => LiveDecision.tanimsiz,
  _ => switch (e.decision) {
    'ALLOWED' => LiveDecision.acildi,
    'DENIED' => LiveDecision.red,
    _ => LiveDecision.tanimsiz,
  },
};

String _two(int v) => v.toString().padLeft(2, '0');

/// Bugün ise "14:03:22", değilse "29.10 14:03".
String _clock(DateTime d) {
  final now = DateTime.now();
  final time = '${_two(d.hour)}:${_two(d.minute)}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return '$time:${_two(d.second)}';
  return '${_two(d.day)}.${_two(d.month)} $time';
}

/// Yönetici "Canlı akış" sekmesi (Plaka Tanıma): son geçişler kartlar halinde, yenileme aralığı ve liste boyu SUNUCU ayarından gelir
/// (`refresh_seconds`, `limit`); istemcide sabit yok (ilk yanıta kadar yalnız [fallbackRefresh]). Otomatik yenileme aç/kapa, bağlantı hatasında son
/// bilinen liste korunur ve uyarı gösterilir. Salt okur (kurul / görevli için de aynı). Ekran kapanınca zamanlayıcı iptal edilir.
class PlateLiveFeedPanel extends StatefulWidget {
  const PlateLiveFeedPanel({super.key, required this.service, required this.siteCode, this.fallbackRefresh = const Duration(seconds: 5)});

  final PlateRecognitionService service;
  final int siteCode;

  /// Sunucudan ilk yanıt gelmeden (hata) kullanılan yeniden deneme aralığı.
  final Duration fallbackRefresh;

  @override
  State<PlateLiveFeedPanel> createState() => _PlateLiveFeedPanelState();
}

class _PlateLiveFeedPanelState extends State<PlateLiveFeedPanel> {
  PlateLiveFeed? _feed;
  String? _error;
  bool _auto = true;
  bool _busy = false;
  DateTime? _updatedAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(PlateLiveFeedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteCode != widget.siteCode) {
      _feed = null;
      _error = null;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      final feed = await widget.service.liveFeed(widget.siteCode);
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _error = null;
        _updatedAt = DateTime.now();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_auto || !mounted) return;
    final seconds = _feed?.refreshSeconds;
    _timer = Timer(seconds == null ? widget.fallbackRefresh : Duration(seconds: seconds), () => unawaited(_load()));
  }

  void _toggleAuto(bool value) {
    setState(() => _auto = value);
    if (value) {
      unawaited(_load());
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    if (feed == null) {
      if (_error != null) {
        return EmptyState(icon: Icons.cloud_off_rounded, title: 'Bağlantı kurulamadı', message: _error, actionLabel: 'Yeniden dene', onAction: () => unawaited(_load()), tone: AppTone.danger);
      }
      return const Center(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _InsideCounter(count: feed.insideCount),
        const SizedBox(height: AppSpace.sm),
        _controls(feed),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Semantics(
              liveRegion: true,
              child: AppCard(tone: AppTone.danger, padding: const EdgeInsets.all(AppSpace.md), child: Text('Bağlantı kesildi; son bilinen liste gösteriliyor. $_error')),
            ),
          ),
        if (feed.events.isEmpty)
          const EmptyState(icon: Icons.sensors_rounded, title: 'Henüz geçiş yok', message: 'Araçlar kapıdan geçince burada anında görünür.', tone: AppTone.neutral)
        else
          for (final e in feed.events) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: LiveEventCard(event: e)),
      ],
    );
  }

  Widget _controls(PlateLiveFeed feed) {
    final updated = _updatedAt;
    final theme = Theme.of(context).textTheme;
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Semantics(
          label: 'Otomatik yenileme, her ${feed.refreshSeconds} saniyede bir',
          toggled: _auto,
          child: FilterChip(
            key: const ValueKey<String>('live_auto'),
            avatar: Icon(_auto ? Icons.sync_rounded : Icons.sync_disabled_rounded, size: 18),
            label: Text(_auto ? 'Otomatik: ${feed.refreshSeconds} sn' : 'Otomatik yenileme kapalı'),
            selected: _auto,
            onSelected: _toggleAuto,
          ),
        ),
        IconButton(
          key: const ValueKey<String>('live_refresh'),
          tooltip: 'Şimdi yenile',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
          onPressed: _busy ? null : () => unawaited(_load()),
        ),
        if (updated != null) Text('Son güncelleme ${_clock(updated)}', style: theme.bodySmall),
      ],
    );
  }
}

/// Büyük "İçeride: N araç" göstergesi.
class _InsideCounter extends StatelessWidget {
  const _InsideCounter({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      label: 'İçeride $count araç',
      child: ExcludeSemantics(
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
          child: Row(
            children: <Widget>[
              Icon(Icons.local_parking_rounded, size: 32, color: AppTone.info.ink(p)),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(text: 'İçeride: ', style: theme.titleMedium?.copyWith(color: p.textSecondary)),
                        TextSpan(text: '$count', style: theme.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: p.text)),
                        TextSpan(text: ' araç', style: theme.titleMedium?.copyWith(color: p.textSecondary)),
                      ],
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tek geçiş kartı: yön oku, belirgin monospace plaka, karar rozeti, kapı adı + saat. Tek `Semantics` cümlesi.
class LiveEventCard extends StatelessWidget {
  const LiveEventCard({super.key, required this.event});

  final PlateDecisionRow event;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context).textTheme;
    final decision = liveDecisionOf(event);
    final isIn = event.direction == 'giris';
    final isOut = event.direction == 'cikis';
    final dirTone = isIn ? AppTone.success : (isOut ? AppTone.info : AppTone.neutral);
    final dirIcon = isIn ? Icons.south_rounded : (isOut ? Icons.north_rounded : Icons.swap_vert_rounded);
    final dirLabel = isIn ? 'Giriş' : (isOut ? 'Çıkış' : 'Yön bilinmiyor');
    final plate = LicensePlateBadge.format(event.plate);
    final gate = (event.doorName ?? '').isNotEmpty ? event.doorName! : ((event.deviceName ?? '').isNotEmpty ? event.deviceName! : 'Kapı belirtilmemiş');
    final time = event.seenAt == null ? '' : _clock(event.seenAt!);
    final badgeLabel = switch (decision) {
      LiveDecision.acildi => 'AÇILDI',
      LiveDecision.red => 'RED',
      LiveDecision.tanimsiz => 'TANIMSIZ',
      LiveDecision.karaListe => 'KARA LİSTE',
    };
    return Semantics(
      container: true,
      label: 'Plaka $plate, $dirLabel, $badgeLabel, $gate${time.isEmpty ? '' : ', $time'}',
      child: ExcludeSemantics(
        child: AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: dirTone.tint(p), border: Border.all(color: dirTone.hue.withValues(alpha: 0.6))),
                child: Icon(dirIcon, size: 22, color: dirTone.ink(p)),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
                          decoration: BoxDecoration(color: p.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.sm), border: Border.all(color: p.border)),
                          child: Text(plate, style: theme.titleLarge?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w800, letterSpacing: 1.5, color: p.text)),
                        ),
                        _DecisionBadge(decision: decision, label: badgeLabel),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text('$dirLabel  •  $gate${time.isEmpty ? '' : '  •  $time'}', style: theme.bodySmall?.copyWith(color: p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecisionBadge extends StatelessWidget {
  const _DecisionBadge({required this.decision, required this.label});

  final LiveDecision decision;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (Color bg, Color fg, Color edge) = switch (decision) {
      LiveDecision.acildi => (AppTone.success.tint(p), AppTone.success.ink(p), AppTone.success.hue),
      LiveDecision.red => (AppTone.danger.tint(p), AppTone.danger.ink(p), AppTone.danger.hue),
      LiveDecision.tanimsiz => (AppTone.neutral.tint(p), p.textSecondary, p.border),
      LiveDecision.karaListe => (const Color(0xFF111827), Colors.white, const Color(0xFF6B7280)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm), border: Border.all(color: edge)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
    );
  }
}
