import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_setup_progress.dart';
import 'package:site_kapi_kontrol/services/site_setup_progress_store.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Panel'de (yönetici / süper kullanıcı görünümü) "Site kurulumunuz sürüyor" hatırlatması (P2-15: yarım kalan kurulum
/// devam eder).
///
/// YALNIZ cihazda kaydı olan ve bitirilmemiş / kapatılmamış bir kurulum varsa çizilir; yoksa hiçbir şey çizmez (boşluk
/// bile kalmaz). Kayıt, site kurulduğunda ya da başvurusu onaylandığında açılır ya da sihirbaz bir kez açılınca oluşur;
/// bu kart kimseye "site kur" diye davet etmez (başvuru / kurulum davetleri başka ekranlardadır). Ağ isteği YAPMAZ:
/// ilerleme ("3 / 6 adım") kayıttan okunur. Kayıt değişince ([SiteSetupProgressStore.changes]) kendini tazeler.
///
/// "Kuruluma devam et" sihirbazı açar ([onResume]); "Şimdilik gizle" hatırlatmayı kapatır (sihirbaz Site Yönetimi'nden yine
/// açılır).
class SiteSetupResumeCard extends StatefulWidget {
  const SiteSetupResumeCard({super.key, required this.userId, required this.onResume, this.store});

  final int userId;

  /// Sihirbazı açar (site kodu, kayıtlı site adı).
  final void Function(int siteCode, String siteName) onResume;

  /// İlerleme deposu (verilmezse uygulama geneli ortak depo).
  final SiteSetupProgressStore? store;

  @override
  State<SiteSetupResumeCard> createState() => _SiteSetupResumeCardState();
}

class _SiteSetupResumeCardState extends State<SiteSetupResumeCard> {
  SiteSetupProgress? _progress;
  int _token = 0;

  SiteSetupProgressStore get _store => widget.store ?? SiteSetupProgressStore.shared;

  @override
  void initState() {
    super.initState();
    _store.addListener(_reload);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(SiteSetupResumeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldStore = oldWidget.store ?? SiteSetupProgressStore.shared;
    if (!identical(oldStore, _store)) {
      oldStore.removeListener(_reload);
      _store.addListener(_reload);
    }
    if (oldWidget.userId != widget.userId || !identical(oldStore, _store)) unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    _store.removeListener(_reload);
    super.dispose();
  }

  void _reload() => unawaited(_load());

  Future<void> _load() async {
    final token = ++_token;
    final next = await _store.nextUnfinished(widget.userId);
    if (!mounted || token != _token) return;
    if (next != _progress) setState(() => _progress = next);
  }

  Future<void> _dismiss(SiteSetupProgress progress) async {
    await _store.save(widget.userId, progress.markDismissed());
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    if (progress == null) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final name = progress.siteName.trim().isEmpty ? 'Siteniz' : progress.siteName.trim();
    final fresh = !progress.started;
    final summary = fresh
        ? '$name hazır. Kişileri, modülleri ve finansı birkaç adımda tamamlayın.'
        : '$name · ${progress.doneCount} / ${SiteSetupProgress.stepCount} adım tamam';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: AppCard(
        key: const ValueKey<String>('site_setup_resume_card'),
        level: 2,
        padding: listCardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconTile(icon: Icons.checklist_rtl_rounded, size: 44, gap: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          fresh ? 'Site kurulumunu tamamlayın' : 'Site kurulumunuz yarım kaldı',
                          style: th.titleMedium,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        summary,
                        key: const ValueKey<String>('site_setup_resume_summary'),
                        style: th.bodyMedium?.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PrimaryActionButton(
                  key: const ValueKey<String>('site_setup_resume_open'),
                  label: fresh ? 'Kuruluma başla' : 'Kuruluma devam et',
                  icon: Icons.arrow_forward_rounded,
                  expand: false,
                  onPressed: () => widget.onResume(progress.siteCode, progress.siteName),
                ),
                TextButton(
                  key: const ValueKey<String>('site_setup_resume_dismiss'),
                  onPressed: () => unawaited(_dismiss(progress)),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('Şimdilik gizle'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
