import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Duyurunun "Alıcılar" sekmesi (Platform Faz 3a): Okumayanlar / Okuyanlar, arama, sayfalı liste.
/// YALNIZ yazma yetkisi olana çizilir (kurul üyesi alıcı adlarını görmez; sunucu da 403 döner).
///
/// Hızlı art arda aramada ya da süzgeç değişiminde eski yanıt yenisini ezmez ([PagedLoader] jetonu);
/// hata asla "alıcı yok" demez. Dokunma hedefleri >= 48 dp, metinler sarar.
class AnnouncementRecipientsPanel extends StatefulWidget {
  const AnnouncementRecipientsPanel({
    super.key,
    required this.scope,
    required this.announcementId,
    required this.readCount,
    required this.unreadCount,
    this.sendEmail = false,
  });

  final PeopleScope scope;
  final int announcementId;
  final int readCount;
  final int unreadCount;

  /// E-posta istendiyse her satırda e-posta durumu da yazılır.
  final bool sendEmail;

  @override
  State<AnnouncementRecipientsPanel> createState() => AnnouncementRecipientsPanelState();
}

class AnnouncementRecipientsPanelState extends State<AnnouncementRecipientsPanel> {
  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  bool _readers = false;
  String _lastSignature = '|false';

  late final PagedLoader<AnnouncementRecipient> _loader = PagedLoader<AnnouncementRecipient>(
    fetch: (offset, limit) async {
      final page = await widget.scope.authService.listAnnouncementRecipients(
        widget.scope.siteCode,
        widget.announcementId,
        read: _readers ? 'true' : 'false',
        query: _query,
        limit: limit,
        offset: offset,
      );
      return (items: page.items, total: page.total);
    },
    keyOf: (r) => r.personId,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Alıcılar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Listeyi yeniden çeker.
  Future<void> reload() => _loader.reload();

  void _applyFilters() {
    _timer?.cancel();
    final next = _search.text.trim();
    final signature = '$next|$_readers';
    if (signature == _lastSignature &&
        (_loader.loading || (_loader.loadedOnce && _loader.error == null))) {
      return;
    }
    _lastSignature = signature;
    _query = next;
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _onSearchChanged(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _applyFilters);
    setState(() {});
  }

  void _selectReaders(bool readers) {
    if (readers == _readers) return;
    _readers = readers;
    _applyFilters();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            ChoiceChip(
              key: const ValueKey<String>('recipients_unread'),
              avatar: const Icon(Icons.mark_email_unread_rounded, size: 18),
              label: Text('Okumayanlar (${widget.unreadCount})'),
              selected: !_readers,
              onSelected: (_) => _selectReaders(false),
            ),
            ChoiceChip(
              key: const ValueKey<String>('recipients_read'),
              avatar: const Icon(Icons.mark_email_read_rounded, size: 18),
              label: Text('Okuyanlar (${widget.readCount})'),
              selected: _readers,
              onSelected: (_) => _selectReaders(true),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          key: const ValueKey<String>('recipients_search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: _onSearchChanged,
          onSubmitted: (_) => _applyFilters(),
          decoration: InputDecoration(
            labelText: 'Alıcı ara',
            hintText: 'Ad veya daire',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Aramayı temizle',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      _applyFilters();
                      setState(() {});
                    },
                  ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CrmListBody<AnnouncementRecipient>(
          loader: _loader,
          emptyIcon: Icons.groups_2_rounded,
          emptyTitle: _readers ? 'Henüz okuyan yok.' : 'Okumayan alıcı yok.',
          filteredTitle: 'Bu arama için alıcı bulunamadı.',
          filtered: _query.isNotEmpty,
          skeletonRows: 2,
          itemBuilder: (context, recipient) =>
              _RecipientRow(recipient: recipient, sendEmail: widget.sendEmail),
        ),
      ],
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({required this.recipient, required this.sendEmail});

  final AnnouncementRecipient recipient;
  final bool sendEmail;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final r = recipient;
    final readText = r.isRead
        ? 'Okudu: ${formatIstanbulDateTime(r.readAt)}'
        : (r.hasAccount ? 'Henüz okumadı' : 'Hesabı olmadığı için uygulamada göremez');
    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(crmPersonName(r.fullName), style: th.titleSmall),
          // Daireler kişinin ŞU ANKİ daireleridir; taşınmışsa boş olabilir: "—" (ekran okuyucuya açıklamalı).
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              if (r.apartments.isEmpty)
                Semantics(
                  label: 'Güncel dairesi yok',
                  excludeSemantics: true,
                  child: const InfoChip('—'),
                )
              else
                for (final apartment in r.apartments) InfoChip(apartment),
              if (!r.hasAccount) const InfoChip('Hesabı yok'),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(readText, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
          if (sendEmail)
            Text(r.emailStatus.label, style: th.bodySmall?.copyWith(color: p.textSecondary)),
        ],
      ),
    );
  }
}
