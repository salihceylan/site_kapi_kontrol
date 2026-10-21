import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/neighbor_post.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/neighbor_board_api.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart' show PeopleSite;

/// "Komşu Panosu" (`neighbor_board` modülü). Sakin: yayındaki ilanları görür, ilan yazar (yönetici onayına gider),
/// başkasının ilanını şikayet eder, kendi ilanını geri çeker. Yönetici ([PeopleSite.canWrite]): bekleyen ilanı
/// onaylar / reddeder, şikayetli ya da yayındaki ilanı gerekçeyle kaldırır.
///
/// Telefon bildirimi, ilana fotoğraf ve yorum henüz yoktur ("Yakında").
class NeighborBoardView extends StatefulWidget {
  const NeighborBoardView({super.key, required this.authService, this.service, this.sites = const <PeopleSite>[]});

  final AuthService authService;
  final NeighborBoardService? service;
  final List<PeopleSite> sites;

  @override
  State<NeighborBoardView> createState() => NeighborBoardViewState();
}

class NeighborBoardViewState extends State<NeighborBoardView> {
  static const List<(String, String)> _managerTabs = <(String, String)>[
    ('pending', 'Onay bekleyen'),
    ('reported', 'Şikayetli'),
    ('published', 'Yayındaki'),
    ('rejected', 'Reddedilen'),
    ('removed', 'Kaldırılan'),
  ];

  late NeighborBoardService _service = widget.service ?? NeighborBoardService(authService: widget.authService);
  late PeopleSite? _site = widget.sites.isEmpty ? null : widget.sites.first;
  String _tab = 'pending';
  List<NeighborPost> _items = const <NeighborPost>[];
  bool _loading = false;
  String? _error;

  bool get _manager => _site?.canWrite ?? false;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void didUpdateWidget(NeighborBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.authService, widget.authService) || !identical(oldWidget.service, widget.service)) {
      _service = widget.service ?? NeighborBoardService(authService: widget.authService);
    }
    final current = _site;
    if (current == null || !widget.sites.any((s) => s.code == current.code)) {
      _site = widget.sites.isEmpty ? null : widget.sites.first;
      unawaited(reload());
    }
  }

  Future<void> reload() async {
    final site = _site;
    if (site == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = site.canWrite
          ? await _service.listManaged(site.code, _tab)
          : await _service.listResident(site.code);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _messageOf(e, 'İlanlar yüklenemedi.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messageOf(Object e, String fallback) => e is ApiException && e.message.trim().isNotEmpty ? e.message : fallback;

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_messageOf(e, 'İşlem tamamlanamadı.'))));
    }
    if (mounted) await reload();
  }

  Future<String?> _askText(String title, {required String label, required int max, bool required = true}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLength: max,
          maxLines: 3,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (required && text.isEmpty) return;
              Navigator.pop(ctx, text);
            },
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
  }

  Future<void> _newPost() async {
    final site = _site;
    if (site == null) return;
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni ilan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('İlanınız yönetici onayından sonra komşularınıza görünür.'),
              TextField(controller: title, maxLength: 120, decoration: const InputDecoration(labelText: 'Başlık')),
              TextField(
                controller: body,
                maxLength: 2000,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Metin'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Onaya gönder')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => _service.create(site.code, title.text.trim(), body.text.trim()),
      'İlanınız yönetici onayına gönderildi.',
    );
  }

  Future<void> _report(NeighborPost post) async {
    final reason = await _askText('İlanı şikayet et', label: 'Neden?', max: 200);
    if (reason == null || !mounted) return;
    await _run(() => _service.report(post.id, reason), 'Şikayetiniz yöneticiye iletildi.');
  }

  Future<void> _decide(NeighborPost post, String action) async {
    final site = _site;
    if (site == null) return;
    String? note;
    if (action != 'approve') {
      note = await _askText(action == 'reject' ? 'Reddet' : 'Kaldır', label: 'Gerekçe', max: 300);
      if (note == null || !mounted) return;
    }
    final done = switch (action) {
      'approve' => 'İlan yayınlandı.',
      'reject' => 'İlan reddedildi.',
      _ => 'İlan kaldırıldı.',
    };
    await _run(() => _service.decide(site.code, post.id, action, note: note), done);
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    if (site == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Komşu Panosu bu sitede açık değil.')));
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), 
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (widget.sites.length > 1)
            DropdownButton<int>(
              isExpanded: true,
              value: site.code,
              items: <DropdownMenuItem<int>>[
                for (final s in widget.sites)
                  DropdownMenuItem<int>(value: s.code, child: Text(s.name.trim().isEmpty ? 'İsimsiz site' : s.name)),
              ],
              onChanged: (code) {
                setState(() => _site = widget.sites.firstWhere((s) => s.code == code));
                unawaited(reload());
              },
            ),
          if (_manager)
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final (code, label) in _managerTabs)
                  ChoiceChip(
                    label: Text(label),
                    selected: _tab == code,
                    onSelected: (_) {
                      setState(() => _tab = code);
                      unawaited(reload());
                    },
                  ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _newPost,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Yeni ilan'),
              ),
            ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            )
          else if (!_loading && _items.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Henüz ilan yok.')),
          for (final post in _items) _card(post),
          const SizedBox(height: 8),
          Text(
            'Yakında: telefon bildirimi, fotoğraf ve yorum.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _card(NeighborPost post) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(post.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${post.authorName}${post.createdAt == null ? '' : ' - ${_date(post.createdAt!)}'}'
              '${post.status == NeighborPostStatus.published ? '' : ' - ${NeighborPostStatus.label(post.status)}'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(post.body),
            if (post.decisionNote != null) ...<Widget>[
              const SizedBox(height: 6),
              Text('Yönetici notu: ${post.decisionNote}', style: theme.textTheme.bodySmall),
            ],
            if (_manager && post.reportCount > 0) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                '${post.reportCount} şikayet: ${post.reportReasons.join(' / ')}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: _actions(post)),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(NeighborPost post) {
    if (_manager) {
      return <Widget>[
        if (post.status == NeighborPostStatus.pending) ...<Widget>[
          FilledButton(onPressed: () => _decide(post, 'approve'), child: const Text('Onayla')),
          OutlinedButton(onPressed: () => _decide(post, 'reject'), child: const Text('Reddet')),
        ],
        if (post.status == NeighborPostStatus.published)
          OutlinedButton(onPressed: () => _decide(post, 'remove'), child: const Text('Kaldır')),
      ];
    }
    final active = post.status == NeighborPostStatus.published || post.status == NeighborPostStatus.pending;
    if (post.isMine && active) {
      return <Widget>[
        TextButton(
          onPressed: () => _run(() => _service.withdraw(post.id), 'İlan geri çekildi.'),
          child: const Text('Geri çek'),
        ),
      ];
    }
    if (!post.isMine && post.status == NeighborPostStatus.published) {
      return <Widget>[TextButton.icon(onPressed: () => _report(post), icon: const Icon(Icons.flag_outlined), label: const Text('Şikayet et'))];
    }
    return const <Widget>[];
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}
