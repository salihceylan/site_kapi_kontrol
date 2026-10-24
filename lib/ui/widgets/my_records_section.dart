import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/design/license_plate.dart';

/// Profilde "Kayıtlarım" bölümü (Platform Faz 2a, F2.10): sakinin KENDİ güncel kayıtları — dairelerim,
/// ilişkim (malik / kiracı / aile üyesi / sakin), giriş tarihim ve araçlarım. SALT OKUNUR: değişiklik
/// site yöneticisinden istenir. Sunucu yalnız çağıranın kendi kayıtlarını döndürür.
///
/// Görünürlük: yüklenirken küçük iskelet, hata olursa hata + "Tekrar Dene" (hata ASLA "kayıt yok"
/// diye gösterilmez). Kayıt yoksa bölüm gizlenir ([showWhenEmpty] true ise kısa bir açıklama yazılır;
/// daire sakini profilinde açıktır). Hesap değişince (yeni [authService] örneği) yeniden yüklenir.
class MyRecordsSection extends StatefulWidget {
  const MyRecordsSection({
    super.key,
    required this.authService,
    this.showWhenEmpty = false,
  });

  final AuthService authService;
  final bool showWhenEmpty;

  @override
  State<MyRecordsSection> createState() => MyRecordsSectionState();
}

class MyRecordsSectionState extends State<MyRecordsSection> {
  List<MyRecord> _records = const <MyRecord>[];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void didUpdateWidget(MyRecordsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.authService, widget.authService)) {
      // Hesap değişti: eski hesabın kayıtları yeni hesaba sızmasın.
      _records = const <MyRecord>[];
      _loadedOnce = false;
      unawaited(reload());
    }
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  /// Kayıtları yeniden çeker (mevcut liste yenileme sürerken ekranda kalır).
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await widget.authService.getMyRecords();
      if (!mounted || token != _token) return;
      setState(() {
        _records = records;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(
          e,
          'Kayıtlarınız yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final Widget body;
    if (_records.isEmpty && (_loading || (_error == null && !_loadedOnce))) {
      body = const ListSkeleton(rows: 1, inCard: true);
    } else if (_records.isEmpty && _error != null) {
      body = InlineNotice(message: _error!, onRetry: reload);
    } else if (_records.isEmpty) {
      if (!widget.showWhenEmpty) return const SizedBox.shrink();
      body = Text(
        'Henüz size ait bir kayıt görünmüyor. Site yöneticiniz dairenizi tanımladığında burada listelenir.',
        style: th.bodyMedium?.copyWith(color: p.textSecondary),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InlineNotice(message: _error!, onRetry: reload),
            const SizedBox(height: AppSpace.md),
          ],
          for (var i = 0; i < _records.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.md),
            _MyRecordPanel(record: _records[i]),
          ],
        ],
      );
    }
    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Kayıtlarım',
            trailing: IconButton(
              onPressed: _loading ? null : reload,
              tooltip: 'Kayıtlarımı yenile',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Bu bilgiler site yöneticiniz tarafından tutulur. Değişiklik için yöneticinizle iletişime geçin.',
            style: th.bodySmall,
          ),
          const SizedBox(height: AppSpace.md),
          body,
        ],
      ),
    );
  }
}

class _MyRecordPanel extends StatelessWidget {
  const _MyRecordPanel({required this.record});

  final MyRecord record;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final site = record.siteName.trim();
    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (site.isNotEmpty)
            Text(site, style: th.bodySmall?.copyWith(color: p.textSecondary)),
          Text(record.fullLabel, style: th.titleSmall),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              RelationChip(record.relation),
              InfoChip('Giriş: ${formatCrmDate(record.moveInDate)}'),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text('Araçlarım', style: th.bodySmall?.copyWith(color: p.textSecondary)),
          if (record.vehicles.isEmpty)
            Text('Kayıtlı araç yok.', style: th.bodyMedium)
          else
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                for (final vehicle in record.vehicles) LicensePlateBadge(plate: vehicle.displayPlate, compact: true),
              ],
            ),
        ],
      ),
    );
  }
}
